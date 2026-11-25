"""Rebuild the North American boundary release from publisher downloads or a verified local cache."""

import argparse
from collections import defaultdict
from dataclasses import dataclass
import gzip
import hashlib
import importlib.metadata
import io
import json
from pathlib import Path
import platform
import re
import subprocess
import tempfile
import zlib
from urllib.parse import urlencode
from zipfile import ZipFile

import numpy as np
import pyproj
import shapefile
import shapely
from shapely.geometry import MultiPolygon, shape

from statcan_topology import ring_topology
from tracking_accuracy import (
    CAP_METRES,
    DECIMALS,
    RESTORE_METRES,
    certify_tracking,
    restore_tracking,
)


CANADA = dict(
    zip(
        "10 11 12 13 24 35 46 47 48 59 60 61 62".split(),
        "NL PE NS NB QC ON MB SK AB BC YT NT NU".split(),
        strict=True,
    )
)
US_CODES = set(
    "AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY PR AS GU MP VI".split()
)
UNTRACKED_US_CODES = {"AS", "GU", "MP", "VI"}
US_PROJECTIONS = {
    "AK": 3338,
    "HI": 26963,
    "PR": 32161,
}
# Independently checked against full-precision GeoJSON for the first 12 features and
# the native and WGS84 ArcGIS PBF ring lengths for Nunavut. A partial but parseable
# feature must never silently replace a complete feature in this known release.
CA_2026_TOPOLOGY = {
    "10": (19189, 1, 1151095),
    "11": (111, 0, 41300),
    "12": (3451, 0, 281201),
    "13": (711, 0, 128962),
    "24": (21579, 7, 1217789),
    "35": (37084, 5, 1590328),
    "46": (303, 0, 35260),
    "47": (1, 0, 1346),
    "48": (1, 0, 3554),
    "59": (28116, 1, 1524898),
    "60": (50, 0, 10553),
    "61": (2384, 0, 444917),
    "62": (62405, 3, 5091805),
}
FIELDS = ["PRUID", "DGUID", "PRENAME", "PRFNAME"]
US_TRACKING_TOLERANCE = 180
CA_DISPLAY_TOLERANCE = 45
CA_DUPLICATE_TOLERANCE = 0.02
# Land samples include both sides of three international boundary segments and all four
# excluded US territories. Offshore samples expose the products' different water semantics.
PROBES = {
    "Whitehorse": (-135.0568, 60.7212, "ca-YT"),
    "Yellowknife": (-114.3718, 62.4540, "ca-NT"),
    "Iqaluit": (-68.5167, 63.7467, "ca-NU"),
    "Charlottetown": (-63.1311, 46.2382, "ca-PE"),
    "St John's": (-52.7126, 47.5615, "ca-NL"),
    "Halifax": (-63.5752, 44.6488, "ca-NS"),
    "Fredericton": (-66.6431, 45.9636, "ca-NB"),
    "Quebec City": (-71.2080, 46.8139, "ca-QC"),
    "Toronto": (-79.3832, 43.6532, "ca-ON"),
    "Winnipeg": (-97.1385, 49.8951, "ca-MB"),
    "Regina": (-104.6189, 50.4452, "ca-SK"),
    "Edmonton": (-113.4938, 53.5461, "ca-AB"),
    "Victoria": (-123.3656, 48.4284, "ca-BC"),
    "Port Jefferson": (-73.067, 40.946, "us-NY"),
    "Vancouver": (-123.12, 49.28, "ca-BC"),
    "Lake Simcoe": (-79.35, 44.47, "ca-ON"),
    "Lake Ontario south of Toronto": (-79.40, 43.60, None),
    "Ottawa": (-75.6972, 45.4215, "ca-ON"),
    "Gatineau": (-75.7013, 45.4765, "ca-QC"),
    "Buffalo": (-78.8784, 42.8864, "us-NY"),
    "Fort Erie": (-78.9197, 42.9018, "ca-ON"),
    "Prairie US": (-110, 48.99, "us-MT"),
    "Prairie Canada": (-110, 49.01, "ca-SK"),
    "Alaska border west": (-141.04, 64, "us-AK"),
    "Yukon border east": (-140.96, 64, "ca-YT"),
    "Pago Pago": (-170.701, -14.279, None),
    "Hagåtña": (144.7504, 13.4757, None),
    "Saipan": (145.75, 15.2, None),
    "Charlotte Amalie": (-64.9307, 18.3419, None),
    "Honolulu": (-157.8583, 21.3069, "us-HI"),
    "Adak": (-176.64, 51.88, "us-AK"),
    "Attu": (173.19, 52.84, "us-AK"),
    "Central Lake Ontario": (-77.7, 43.66, None),
    "Atlantic": (-55, 43, None),
    "North Pacific": (180, 48, None),
}
# The cartographic products clip these waters from the displayed coastline.
OFFSHORE_PROBES = {
    "Long Island Sound": (-73.066, 40.998, "us-NY"),
    "Strait of Georgia": (-123.65, 49.28, "ca-BC"),
}
NB_CHANNEL = (-64.5260309, 46.089227)
TEXAS_FIX = (-93.558908, 31.097843)
TEXAS_BORDER_VERTEX = (-93.553852, 31.094584)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def write_json(path, value):
    path.write_text(
        json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    )


def toolchain():
    pyproj.network.set_network_enabled(False)
    database = Path(pyproj.datadir.get_data_dir()) / "proj.db"
    return {
        "python": platform.python_version(),
        "packages": {
            name: importlib.metadata.version(name)
            for name in ("shapely", "pyproj", "pyshp", "numpy", "certifi")
        },
        "zlib": zlib.ZLIB_RUNTIME_VERSION,
        "GEOS": shapely.geos_version_string,
        "PROJ": pyproj.proj_version_str,
        "projectionDatabaseSHA256": digest(database),
        "projectionNetworkEnabled": False,
    }


class SourceCache:
    def __init__(self, directory, replay=None):
        self.directory = directory
        self.directory.mkdir(parents=True, exist_ok=True)
        self.inputs = []
        self.pins = None if replay is None else {row["key"]: row for row in replay}
        if replay is not None:
            require(len(replay) == len(self.pins), "Duplicate input key in lock")

    def get(self, key, url):
        if self.pins is not None:
            pin = self.pins[key]
            require(
                pin["url"] == url and re.fullmatch("[a-f0-9]{64}", pin["sha256"]),
                f"Unexpected source pin for {key}",
            )
            path = self.directory / pin["sha256"]
            require(
                path.is_file()
                and path.stat().st_size == pin["bytes"]
                and digest(path) == pin["sha256"],
                f"Missing or corrupt cached input {key}: {path}",
            )
        else:
            with tempfile.NamedTemporaryFile(dir=self.directory) as incoming:
                # A separate destination per request prevents interrupted downloads from entering the cache.
                subprocess.run(
                    [
                        "curl",
                        "--fail",
                        "--silent",
                        "--show-error",
                        "--location",
                        "--compressed",
                        "--proto",
                        "=https",
                        "--retry",
                        "3",
                        "--connect-timeout",
                        "20",
                        "--max-time",
                        "900",
                        "--output",
                        incoming.name,
                        url,
                    ],
                    check=True,
                )
                incoming_path = Path(incoming.name)
                checksum = digest(incoming_path)
                path = self.directory / checksum
                # link creates the immutable entry atomically and handles concurrent refreshes.
                try:
                    path.hardlink_to(incoming_path)
                except FileExistsError:
                    require(digest(path) == checksum, f"Corrupt cache entry: {path}")
                pin = {
                    "key": key,
                    "url": url,
                    "sha256": checksum,
                    "bytes": path.stat().st_size,
                }
        self.inputs.append(pin)
        return path


@dataclass
class Member:
    code: str
    properties: dict
    membership: dict
    geometry: object
    projection: int


def node(node_id, name, kind, source, parent):
    return {
        "id": node_id,
        "name": name,
        "kind": kind,
        "source": source,
        "isLoggable": True,
        "parentID": parent,
    }


def reproject(geometry, source, target, operations=None):
    # Freeze one area-appropriate operation for the whole feature or connected coverage.
    # PROJ otherwise chooses among regional datum transformations coordinate by coordinate.
    reference = geometry if isinstance(geometry, shapely.Geometry) else geometry[0]
    point = reference.representative_point()
    selector = pyproj.Transformer.from_crs(source, target, always_xy=True)
    selector.transform(point.x, point.y, errcheck=True)
    operation = selector.get_last_used_operation()
    if operations is not None:
        operations[f"{source}-to-{target}"] = operation.definition
    return shapely.transform(geometry, operation.transform, interleaved=False)


def us_members(cache, year, product):
    if product == "censusTIGER":
        base = f"tl_{year}_us_state"
        folder = f"TIGER{year}/STATE"
    elif product == "censusCartographic":
        base = f"cb_{year}_us_state_500k"
        folder = f"GENZ{year}/shp"
    else:
        raise ValueError(f"Unknown Census product: {product}")
    path = cache.get(
        f"{product}-state", f"https://www2.census.gov/geo/tiger/{folder}/{base}.zip"
    )
    members, inventory = {}, {}
    with ZipFile(path) as archive:
        crs = pyproj.CRS.from_wkt(archive.read(f"{base}.prj").decode())
        require(crs.to_epsg() == 4269, f"Unexpected {product} spatial reference: {crs}")
        with shapefile.Reader(
            **{
                suffix: io.BytesIO(archive.read(f"{base}.{suffix}"))
                for suffix in ("shp", "shx", "dbf")
            }
        ) as reader:
            for record in reader.iterRecords():
                code, name = record.STUSPS, record.NAME
                fips = record.STATEFP
                require(
                    code in US_CODES
                    and code not in inventory
                    and re.fullmatch("[0-9]{2}", fips)
                    and fips == record.GEOID
                    and name,
                    f"Unexpected {product} record {code}/{fips}",
                )
                catalog_id = None if code in UNTRACKED_US_CODES else f"us-{code}"
                row = {
                    "STUSPS": code,
                    "STATEFP": fips,
                    "GEOID": record.GEOID,
                    "NAME": name,
                    "countryID": "united-states",
                    "catalogID": catalog_id,
                }
                inventory[code] = row
                if catalog_id is None:
                    continue
                kind = {"DC": "federalDistrict", "PR": "territory"}.get(code, "state")
                props = node(catalog_id, name, kind, product, "united-states")
                row["coordinateOperations"] = {}
                geometry = reproject(
                    shape(reader.shape(record.oid).__geo_interface__),
                    4269,
                    4326,
                    row["coordinateOperations"],
                )
                members[code] = Member(
                    code, props, row, geometry, US_PROJECTIONS.get(code, 5070)
                )
    require(
        set(inventory) == US_CODES
        and len({row["STATEFP"] for row in inventory.values()}) == 56,
        f"{product} STATE membership changed",
    )
    return [members[key] for key in sorted(members)], [
        inventory[key] for key in sorted(inventory)
    ]


def arc_features(document):
    require(
        document.get("type") == "FeatureCollection"
        and not document.get("error")
        and not document.get("exceededTransferLimit"),
        "ArcGIS returned an error or incomplete feature set",
    )
    return document["features"]


def canadian_sources(cache, year, product):
    directory, edition = {
        "statcanDigital": ("Digital", "a"),
        "statcanCartographic": ("Cartographic", "b"),
    }[product]
    root = f"https://geo.statcan.gc.ca/geo_wa/rest/services/{year}/{directory}_boundary_files/MapServer"
    layer_name = f"lpr_000{edition}{str(year)[-2:]}s_e"
    service = json.loads(
        cache.get(f"{product}-service", f"{root}?f=pjson").read_bytes()
    )
    layers = [r for r in service["layers"] if r["name"] == layer_name]
    require(
        len(layers) == 1 and f"{year}-01-01" in service["serviceDescription"],
        "Unexpected Canadian release",
    )
    layer_url = f"{root}/{layers[0]['id']}"
    layer = json.loads(
        cache.get(f"{product}-layer", f"{layer_url}?f=pjson").read_bytes()
    )
    require(
        layer["name"] == layer_name
        and layer["geometryType"] == "esriGeometryPolygon"
        and layer["sourceSpatialReference"]["wkid"] == 3347
        and set(FIELDS)
        <= {
            row["name"]
            for row in layer["fields"]
            if row["type"] == "esriFieldTypeString"
        },
        "Unexpected Canadian province layer schema",
    )

    def query(params):
        return f"{layer_url}/query?" + urlencode(params)

    inventory_url = query(
        {
            "where": "1=1",
            "outFields": ",".join(FIELDS),
            "returnGeometry": "false",
            "orderByFields": "PRUID",
            "f": "geojson",
        }
    )
    rows = arc_features(
        json.loads(cache.get(f"{product}-inventory", inventory_url).read_bytes())
    )
    inventory = {row["properties"]["PRUID"]: row["properties"] for row in rows}
    require(
        len(rows) == len(CANADA) and inventory.keys() == CANADA.keys(),
        "Unexpected Canadian province inventory",
    )
    members = []
    for uid, code in CANADA.items():
        url = query(
            {
                "where": f"PRUID='{uid}'",
                "outFields": ",".join(FIELDS),
                "returnGeometry": "true",
                "outSR": "4326",
                "geometryPrecision": str(DECIMALS),
                "f": "geojson",
            }
        )
        path = cache.get(f"{product}-{uid}", url)
        payload = path.read_bytes()
        record = arc_features(json.loads(payload))
        require(
            len(record) == 1
            and record[0]["properties"] == inventory[uid]
            and record[0]["geometry"]["type"] in ("Polygon", "MultiPolygon")
            and inventory[uid]["DGUID"] == f"{year}A0002{uid}",
            f"Unexpected Canadian feature {uid}",
        )
        del record
        geometry = shapely.from_geojson(payload).geoms[0]
        if product == "statcanCartographic" and year == 2026:
            topology = counts(geometry)
            require(
                tuple(topology[k] for k in ("parts", "holes", "vertices"))
                == CA_2026_TOPOLOGY[uid],
                f"2026 publisher topology has changed for PRUID {uid}; verify the full source",
            )
        else:
            # Verify completeness with an independent native-coordinate serialization on
            # releases for which no reviewed counts exist. Cache this response for replay.
            verification_url = query(
                {
                    "where": f"PRUID='{uid}'",
                    "outFields": "PRUID",
                    "returnGeometry": "true",
                    "outSR": "3347",
                    "f": "pbf",
                }
            )
            native = cache.get(f"{product}-{uid}-topology", verification_url)
            rings, vertices = ring_topology(native.read_bytes())
            actual = counts(geometry)
            require(
                (actual["parts"] + actual["holes"], actual["vertices"])
                == (rings, vertices),
                f"Canadian GeoJSON is incomplete against the native polygon for {uid}",
            )
        props = node(
            f"ca-{code}",
            inventory[uid]["PRENAME"],
            "territory" if int(uid) >= 60 else "province",
            product,
            "canada",
        )
        membership = {
            **inventory[uid],
            "postalCode": code,
            "countryID": "canada",
            "catalogID": props["id"],
        }
        members.append(Member(code, props, membership, geometry, 3347))
    return members


def counts(geometry):
    parts = shapely.get_parts(geometry)
    return {
        "parts": len(parts),
        "holes": int(shapely.get_num_interior_rings(parts).sum()),
        "vertices": int(shapely.get_num_coordinates(geometry)),
    }


def repaired(geometry, code, repairs):
    require(
        geometry.geom_type in ("Polygon", "MultiPolygon") and not geometry.is_empty,
        f"Empty or non-polygonal feature: {code}",
    )
    if geometry.is_valid:
        return geometry
    pieces = shapely.get_parts(geometry)
    fixed = []
    for index, part in enumerate(pieces):
        if part.is_valid:
            fixed.append(part)
            continue
        result = shapely.make_valid(part, method="structure", keep_collapsed=False)
        area_delta = abs(result.area / part.area - 1) if part.area else 1
        require(
            result.geom_type in ("Polygon", "MultiPolygon")
            and not result.is_empty
            and area_delta <= 1e-8,
            f"Substantial change repairing {code}, part {index}: {shapely.is_valid_reason(part)}",
        )
        repairs.append(
            {
                "member": code,
                "part": index,
                "reason": shapely.is_valid_reason(part),
                "before": counts(part),
                "after": counts(result),
                "relativeAreaChange": float(f"{area_delta:.3g}"),
            }
        )
        fixed.extend(shapely.get_parts(result))
    result = MultiPolygon(fixed)
    require(
        result.is_valid,
        f"Unresolved multipart topology in {code}: {shapely.is_valid_reason(result)}",
    )
    return result


def canonical(geometry):
    geometry = shapely.set_precision(geometry, 10**-DECIMALS)
    require(geometry.is_valid and not geometry.is_empty, "Invalid normalized geometry")
    # GEOS normalizes component order, hole order and ring starting vertices. RFC 7946 uses CCW exteriors.
    geometry = shapely.orient_polygons(shapely.normalize(geometry))
    xy, ring = shapely.get_coordinates(
        shapely.get_rings(shapely.get_parts(geometry)), return_index=True
    )
    require(
        np.isfinite(xy).all()
        and (abs(xy[:, 0]) <= 180).all()
        and (abs(xy[:, 1]) <= 90).all(),
        "Non-finite or out-of-range longitude/latitude",
    )
    require(
        (abs(np.diff(xy[:, 0]))[np.diff(ring) == 0] <= 180).all(),
        "Polygon edge crosses the antimeridian; split it before publishing",
    )
    return geometry


def sample_displacement(original, simplified, projection):
    # Sample full-detail vertices (including islands and holes). STRtree finds the nearest output
    # ring. Apply the local projection scale at each sample to report approximate ground metres.
    coords = shapely.get_coordinates(original)
    samples = coords[np.linspace(0, len(coords) - 1, min(len(coords), 256), dtype=int)]
    rings = shapely.get_rings(shapely.get_parts(simplified))
    indices, distances = shapely.STRtree(rings).query_nearest(
        shapely.points(samples), return_distance=True, all_matches=False
    )
    lon, lat = pyproj.Transformer.from_crs(projection, 4326, always_xy=True).transform(
        *samples[indices[0]].T
    )
    factors = pyproj.Proj(projection).get_factors(lon, lat)
    scale = np.minimum(factors.meridional_scale, factors.parallel_scale)
    return {
        "sampledVertices": len(samples),
        "maximumSampledMetres": round(float(np.max(distances / scale)), 2),
    }


def border_probes():
    probes = {name: (lon, lat) for name, (lon, lat, _) in PROBES.items()}
    probes.update({name: (lon, lat) for name, (lon, lat, _) in OFFSHORE_PROBES.items()})
    probes["New Brunswick tidal channel"] = NB_CHANNEL
    probes["Texas–Louisiana"] = TEXAS_FIX
    probes["Texas–Louisiana source vertex"] = TEXAS_BORDER_VERTEX
    # Cross each international boundary at three positions. Report water and land, gaps and
    # overlaps at roughly 20 m intervals within 500 m of each publisher's boundary vicinity.
    for place, lon, lat, dl, da in (
        ("49th", -111.5, 49, 0, 0.0002),
        ("Alaska/Yukon", -141.002, 64, 0.0004, 0),
        ("Niagara River", -79.0671, 43.091, 0.00025, 0),
    ):
        for i in range(-25, 26):
            probes[f"{place} {i:+d}"] = (lon + i * dl, lat + i * da)
    return probes


def matches(geometry, points):
    # Prepared polygon predicates keep the large northern archipelago probes inexpensive.
    shapely.prepare(geometry)
    return shapely.covers(geometry, points)


def repair_digital_seams(projected, group, repairs):
    # The 2026 Ontario/Nunavut seam has adjacent vertices about 1.2 cm apart
    # on one side. Limit the repair to members with invalid shared edges, then
    # let the caller revalidate the entire coverage.
    corrected = projected.copy()
    for i, edges in enumerate(shapely.coverage_invalid_edges(projected)):
        if edges.is_empty:
            continue
        original = projected[i]
        clean = shapely.remove_repeated_points(
            original, tolerance=CA_DUPLICATE_TOLERANCE
        )
        removed = int(
            shapely.get_num_coordinates(original) - shapely.get_num_coordinates(clean)
        )
        if removed:
            corrected[i] = clean
            repairs.append(
                {
                    "member": group[i].code,
                    "nearDuplicateVerticesRemoved": removed,
                    "toleranceMetres": CA_DUPLICATE_TOLERANCE,
                }
            )
    return corrected


def convert_subdivisions(members, country, probes, tolerance, restore=None):
    groups = defaultdict(list)
    for member in members:
        groups[member.projection].append(member)
    converted = {}
    rows, repairs, operations = {}, [], {}
    source_hits = defaultdict(list)
    output_hits = defaultdict(list)
    points = shapely.points(list(probes.values()))
    for epsg, group in sorted(groups.items()):
        require(
            pyproj.CRS.from_epsg(epsg).axis_info[0].unit_conversion_factor == 1,
            "Simplification requires a metric CRS",
        )
        raw = [repaired(m.geometry, m.code, repairs) for m in group]
        projected = [
            repaired(g, m.code, repairs)
            for m, g in zip(group, reproject(raw, 4326, epsg, operations), strict=True)
        ]
        working = projected
        digital = group[0].properties["source"] == "statcanDigital"
        if digital and not shapely.coverage_is_valid(working):
            working = repair_digital_seams(projected, group, repairs)
        require(
            shapely.coverage_is_valid(working),
            f"Source contains overlaps or unmatched edges in EPSG:{epsg}",
        )
        simplified = (
            shapely.coverage_simplify(working, tolerance) if tolerance else working
        )
        require(
            not tolerance or shapely.coverage_is_valid(simplified),
            f"Invalid simplified coverage in EPSG:{epsg}",
        )
        canonical_group = {
            m.code: canonical(g)
            for m, g in zip(
                group,
                reproject(simplified, epsg, 4326, operations)
                if tolerance or working is not projected
                else raw,
                strict=True,
            )
        }
        if restore is not None:
            canonical_group = restore(
                {m.code: m.geometry for m in group}, canonical_group
            )
        forward = pyproj.Transformer.from_pipeline(operations[f"4326-to-{epsg}"])
        for m, before, planar in zip(group, raw, projected, strict=True):
            final = canonical_group[m.code]
            source_counts = counts(before)
            final_counts = counts(final)
            require(
                source_counts["parts"] == final_counts["parts"]
                and source_counts["holes"] == final_counts["holes"],
                f"Simplification changed component or hole counts for {m.code}: {source_counts} -> {final_counts}",
            )
            rows[m.code] = {
                "raw": counts(m.geometry),
                "repairedSource": source_counts,
                "candidate": final_counts,
                "projectionEPSG": epsg,
                **sample_displacement(
                    planar,
                    shapely.transform(final, forward.transform, interleaved=False),
                    epsg,
                ),
            }
            for name, source_hit, output_hit in zip(
                probes, matches(before, points), matches(final, points), strict=True
            ):
                if source_hit:
                    source_hits[name].append(m.code)
                if output_hit:
                    output_hits[name].append(m.code)
            converted[m.code] = final

    require(
        shapely.coverage_is_valid(list(converted.values())),
        f"Final shared borders do not match in {country}",
    )
    features = [(m.properties, converted[m.code]) for m in members]
    return (
        features,
        {
            "members": rows,
            "repairs": repairs,
            "coordinateOperations": operations,
        },
        source_hits,
        output_hits,
    )


def normalized_file(path, features):
    # Stream one feature at a time. A zero mtime and empty embedded filename give deterministic gzip.
    with (
        path.open("wb") as output,
        gzip.GzipFile(
            filename="", mode="wb", fileobj=output, mtime=0, compresslevel=9
        ) as stream,
    ):
        stream.write(b'{"type":"FeatureCollection","features":[')
        for i, (properties, geometry) in enumerate(features):
            if i:
                stream.write(b",")
            stream.write(b'{"type":"Feature","properties":')
            stream.write(
                json.dumps(
                    properties, ensure_ascii=False, separators=(",", ":")
                ).encode()
            )
            stream.write(b',"geometry":')
            stream.write(shapely.to_geojson(geometry).encode())
            stream.write(b"}")
        stream.write(b"]}\n")


def join_memberships(tracking, display):
    def inventory(rows):
        # Names and coordinate operations can change between publisher vintages.
        return sorted(
            (
                row.get("countryID"),
                row.get("STUSPS", ""),
                row.get("STATEFP", ""),
                row.get("GEOID", ""),
                row.get("PRUID", ""),
                row.get("DGUID", ""),
                row.get("postalCode", ""),
                row.get("catalogID") or "",
            )
            for row in rows
        )

    require(
        inventory(tracking) == inventory(display),
        "Tracking and display source inventories disagree",
    )


def classify_release(role, probes, us, canada):
    samples = {}
    for name, xy in probes.items():
        before, after = [
            [f"us-{code}" for code in us[index][name]]
            + [f"ca-{code}" for code in canada[index][name]]
            for index in (2, 3)
        ]
        samples[name] = {"lonLat": list(xy), "source": before, "candidate": after}
        if name in PROBES:
            expected = PROBES[name][2]
        elif name in OFFSHORE_PROBES:
            expected = OFFSHORE_PROBES[name][2] if role == "tracking" else None
        elif name == "New Brunswick tidal channel" and role == "display":
            expected = None
        elif name == "Texas–Louisiana" and role == "tracking":
            expected = "us-TX"
        else:
            continue
        require(
            before == after == ([expected] if expected else []),
            f"Unexpected {role} classification at {name}: {before} -> {after}",
        )
    return samples


def source_records(us_year, us_display_year, ca_year):
    products = {
        "censusTIGER": (
            us_year,
            "TIGER/Line national STATE",
            "Legal boundaries, including assigned water",
        ),
        "censusCartographic": (
            us_display_year,
            "Cartographic states at 1:500,000",
            "Generalized shorelines",
        ),
        "statcanDigital": (
            ca_year,
            "Census digital province/territory boundaries",
            "Geographic boundaries, including assigned water",
        ),
        "statcanCartographic": (
            ca_year,
            "Census detailed cartographic province/territory boundaries",
            "Landmass and coastal islands",
        ),
    }
    sources = {}
    for product, (year, name, includes) in products.items():
        census = product.startswith("census")
        sources[product] = {
            "product": f"{year} {name}",
            "publisher": "U.S. Census Bureau"
            if census
            else "Government of Canada, Statistics Canada",
            "referenceDate": f"{year}-01-01",
            "license": "U.S. Government work, public domain"
            if census
            else "https://open.canada.ca/en/open-government-licence-canada",
            "includes": includes,
        }
    return sources


def build_release(cache, output, us_year, us_display_year, ca_year):
    chain = toolchain()
    probes = border_probes()
    report = {"sourceMembership": {}}
    normalized = {}
    for role, us_product, ca_product, year in (
        ("tracking", "censusTIGER", "statcanDigital", us_year),
        ("display", "censusCartographic", "statcanCartographic", us_display_year),
    ):
        tracking = role == "tracking"
        us, inventory = us_members(cache, year, us_product)
        canada = canadian_sources(cache, ca_year, ca_product)
        report["sourceMembership"][role] = inventory + [m.membership for m in canada]
        if not tracking:
            join_memberships(
                report["sourceMembership"]["tracking"],
                report["sourceMembership"]["display"],
            )
        print(
            f"Verified membership and source topology for {us_product} and {ca_product}.",
            flush=True,
        )
        us_result = convert_subdivisions(
            us,
            "united-states",
            probes,
            US_TRACKING_TOLERANCE if tracking else 0,
            restore_tracking if tracking else None,
        )
        if tracking:
            tiger = next(
                row for row in cache.inputs if row["key"] == "censusTIGER-state"
            )
            report["usTrackingAccuracy"] = certify_tracking(
                {m.code: m.geometry for m in us},
                {
                    props["id"].removeprefix("us-"): geometry
                    for props, geometry in us_result[0]
                },
                tiger["sha256"],
            )
            # Keep the historically displaced shared bend observable on each side.
            point = reproject(shapely.Point(TEXAS_BORDER_VERTEX), 4326, 5070)
            distances = {}
            for props, geometry in us_result[0]:
                if props["id"] in ("us-TX", "us-LA"):
                    distances[props["id"]] = round(
                        float(point.distance(reproject(geometry, 4326, 5070).boundary)),
                        3,
                    )
            require(
                set(distances) == {"us-TX", "us-LA"}
                and all(d <= CAP_METRES for d in distances.values()),
                "Texas–Louisiana regression vertex exceeded 25 m",
            )
            report["texasLouisianaVertex"] = {
                "lonLat": TEXAS_BORDER_VERTEX,
                "distanceMetresEPSG5070": distances,
            }
        ca_result = convert_subdivisions(
            canada, "canada", probes, 0 if tracking else CA_DISPLAY_TOLERANCE
        )
        samples = classify_release(role, probes, us_result, ca_result)
        report[role] = {
            "united-states": us_result[1],
            "canada": ca_result[1],
            "probes": samples,
            "sampleDisagreements": [
                name
                for name, row in samples.items()
                if row["source"] != row["candidate"]
            ],
        }
        features = sorted(us_result[0], key=lambda pair: pair[0]["name"]) + sorted(
            ca_result[0], key=lambda pair: pair[0]["name"]
        )
        geojson = output / (
            "north-america.geojson.gz"
            if tracking
            else "north-america-display.geojson.gz"
        )
        normalized_file(geojson, features)
        normalized[role] = {"file": geojson.name, "sha256": digest(geojson)}
        print(f"Normalized {len(features)} {role} features.", flush=True)
    report_path = output / "report.json"
    write_json(report_path, report)
    lock = {
        "version": 3,
        "usYear": us_year,
        "usDisplayYear": us_display_year,
        "caYear": ca_year,
        "inputs": cache.inputs,
        "toolchain": chain,
        "conversion": {
            "algorithm": "GEOS coverage_simplify (coverage-wide Visvalingam-Whyatt)",
            "usTracking": {
                "initialToleranceMetres": US_TRACKING_TOLERANCE,
                "maximumDisplacementMetres": CAP_METRES,
                "restorationMethod": f"Restore source vertices on chains exceeding {RESTORE_METRES} m; certify final TWKB against the source.",
            },
            "usDisplay": {"toleranceMetres": 0, "publisherScale": 500000},
            "caTracking": {
                "toleranceMetres": 0,
                "nearDuplicateToleranceMetres": CA_DUPLICATE_TOLERANCE,
            },
            "caDisplay": {"toleranceMetres": CA_DISPLAY_TOLERANCE},
            "coordinateDecimals": DECIMALS,
            "usSourceEPSG": 4269,
            "usProjections": {"continental": 5070, **US_PROJECTIONS},
            "canadianProjection": 3347,
            "canadianRequest": {
                "outSR": 4326,
                "geometryPrecision": DECIMALS,
                "serverReprojects": True,
            },
            "normalizedEPSG": 4326,
            "winding": "CCW exterior, CW holes",
        },
        "sources": source_records(us_year, us_display_year, ca_year),
        "normalized": normalized,
        "report": {"file": report_path.name, "sha256": digest(report_path)},
    }
    write_json(output / "sources.lock.json", lock)
    return lock


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--refresh", action="store_true")
    mode.add_argument("--replay", type=Path)
    parser.add_argument("--us-year", type=int)
    parser.add_argument("--us-display-year", type=int)
    parser.add_argument("--ca-year", type=int)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    previous = None
    if args.replay:
        require(
            all(y is None for y in (args.us_year, args.us_display_year, args.ca_year)),
            "Replay takes the vintages from the lock",
        )
        previous = json.loads(args.replay.read_text())
        require(
            previous.get("version") == 3,
            "Unsupported release lock version; refresh with --us-year, --us-display-year and --ca-year to create a paired release",
        )
        require(
            previous["toolchain"] == toolchain(),
            "GIS toolchain differs from the frozen release",
        )
        us_year, us_display_year, ca_year = (
            previous["usYear"],
            previous["usDisplayYear"],
            previous["caYear"],
        )
    else:
        us_year, us_display_year, ca_year = (
            args.us_year,
            args.us_display_year,
            args.ca_year,
        )
    require(
        all(
            isinstance(year, int) and 2000 <= year <= 2099
            for year in (us_year, us_display_year, ca_year)
        ),
        "Refresh requires explicit four-digit US tracking, US display and Canadian release years",
    )
    args.output.mkdir(parents=True, exist_ok=True)
    require(not any(args.output.iterdir()), "Candidate output must be empty")
    cache = SourceCache(args.cache, previous["inputs"] if previous else None)
    release = build_release(cache, args.output, us_year, us_display_year, ca_year)
    if previous is not None:
        require(
            release == previous,
            "Replayed input, options or output diverged from the frozen release",
        )


if __name__ == "__main__":
    main()
