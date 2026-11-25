"""Small offline fixtures for the GIS maintainer tool. Run with its pinned virtual environment."""

import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
from zipfile import ZipFile

import pyproj
import shapefile
import shapely
from shapely.geometry import MultiPolygon, Point, Polygon, box

import convert_boundaries as boundaries


def native_polygon_fixture(length=5, extra_feature=False):
    # One tiny synthetic ArcGIS PBF. All test field lengths fit in one byte.
    def field(number, data):
        return bytes((number * 8 + 2, len(data))) + data

    geometry = field(2, bytes((length,))) + field(3, bytes(length * 2))
    feature = field(15, field(2, geometry))
    result = bytes((7 * 8, 3)) + feature * (2 if extra_feature else 1)
    return field(2, field(1, result))


class ArcGISFixture:
    def __init__(self, root, year=2021):
        self.root = root
        self.year = year
        self.inventory = [
            {
                "type": "Feature",
                "properties": {
                    "PRUID": uid,
                    "PRENAME": code,
                    "PRFNAME": code,
                    "DGUID": f"{year}A0002{uid}",
                },
                "geometry": None,
            }
            for uid, code in boundaries.CANADA.items()
        ]
        self.error = None
        self.pbf = native_polygon_fixture()

    def get(self, key, _url):
        layer_name = f"lpr_000b{str(self.year)[-2:]}s_e"
        if key == "statcan-service":
            value = {
                "layers": [{"name": layer_name, "id": 7}],
                "serviceDescription": f"{self.year}-01-01",
            }
        elif key == "statcan-layer":
            value = {
                "name": layer_name,
                "geometryType": "esriGeometryPolygon",
                "sourceSpatialReference": {"wkid": 3347},
                "fields": [
                    {"name": f, "type": "esriFieldTypeString"}
                    for f in boundaries.FIELDS
                ],
            }
        elif key == "statcan-inventory":
            value = {"type": "FeatureCollection", "features": self.inventory}
        elif key.endswith("-topology"):
            path = self.root / key
            path.write_bytes(self.pbf)
            return path
        elif self.error is not None:
            value = self.error
        else:
            feature = next(
                f for f in self.inventory if f["properties"]["PRUID"] == key[-2:]
            )
            value = {
                "type": "FeatureCollection",
                "features": [
                    {
                        **feature,
                        "geometry": json.loads(
                            shapely.to_geojson(box(-75, 45, -74, 46))
                        ),
                    }
                ],
            }
        path = self.root / key
        path.write_text(json.dumps(value))
        return path


class BoundaryConversionTests(unittest.TestCase):
    def test_named_layer_inventory_error_and_incomplete_geometry(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture = ArcGISFixture(Path(directory))
            members = boundaries.canadian_sources(fixture, fixture.year)
            self.assertEqual(13, len(members))
            self.assertEqual("territory", members[-1].properties["kind"])
            self.assertEqual("ca-NU", members[-1].membership["catalogID"])
            fixture.pbf = native_polygon_fixture(length=6)
            with self.assertRaisesRegex(
                ValueError, "incomplete against the native polygon"
            ):
                boundaries.canadian_sources(fixture, fixture.year)
            fixture.pbf = native_polygon_fixture(extra_feature=True)
            with self.assertRaisesRegex(
                ValueError, "Expected one ArcGIS protobuf field"
            ):
                boundaries.canadian_sources(fixture, fixture.year)
            fixture.error = {"error": {"code": 500}}
            with self.assertRaisesRegex(ValueError, "incomplete feature"):
                boundaries.canadian_sources(fixture, fixture.year)
            fixture.error = {
                "type": "FeatureCollection",
                "features": [],
                "exceededTransferLimit": True,
            }
            with self.assertRaisesRegex(ValueError, "incomplete feature"):
                boundaries.canadian_sources(fixture, fixture.year)
            fixture.inventory.pop()
            with self.assertRaisesRegex(ValueError, "inventory"):
                boundaries.canadian_sources(fixture, fixture.year)
            fixture = ArcGISFixture(Path(directory), 2026)
            with self.assertRaisesRegex(ValueError, "topology has changed"):
                boundaries.canadian_sources(fixture, fixture.year)

    def test_us_archive_validates_all_records_without_converting_untracked_territories(
        self,
    ):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            base = path / "tl_2026_us_state"
            with shapefile.Writer(str(base)) as writer:
                for field in ("STUSPS", "NAME", "STATEFP", "GEOID"):
                    writer.field(field, "C", size=16)
                for index, code in enumerate(sorted(boundaries.US_CODES)):
                    fips = f"{index:02d}"
                    writer.record(code, code, fips, fips)
                    if code in boundaries.UNTRACKED_US_CODES:
                        writer.null()
                    else:
                        writer.poly(
                            [[(-75, 40), (-75, 41), (-74, 41), (-74, 40), (-75, 40)]]
                        )
            base.with_suffix(".prj").write_text(pyproj.CRS.from_epsg(4269).to_wkt())
            archive_path = path / "state.zip"
            with ZipFile(archive_path, "w") as archive:
                for source in path.glob(f"{base.name}.*"):
                    archive.write(source, source.name)
            cache = Mock()
            cache.get.return_value = archive_path
            members, inventory = boundaries.us_members(cache, 2026)
            self.assertEqual(52, len(members))
            self.assertEqual(56, len(inventory))
            excluded = {row["STUSPS"] for row in inventory if row["catalogID"] is None}
            self.assertEqual(boundaries.UNTRACKED_US_CODES, excluded)
            with patch.object(boundaries, "US_CODES", boundaries.US_CODES | {"NEW"}):
                with self.assertRaisesRegex(ValueError, "membership changed"):
                    boundaries.us_members(cache, 2026)

    def test_replay_rejects_modified_same_size_bytes_without_fetching(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            initial = root / "initial"
            initial.write_bytes(b"abcd")
            expected = boundaries.digest(initial)
            initial.rename(root / expected)
            pins = [
                {
                    "key": "fixture",
                    "url": "https://example.org/data",
                    "sha256": expected,
                    "bytes": 4,
                }
            ]
            cache = boundaries.SourceCache(root, pins)
            with patch(
                "subprocess.run", side_effect=AssertionError("replay fetched a URL")
            ):
                self.assertEqual(root / expected, cache.get("fixture", pins[0]["url"]))
                (root / expected).write_bytes(b"wxyz")
                with self.assertRaisesRegex(ValueError, "corrupt cached input"):
                    cache.get("fixture", pins[0]["url"])

    def test_only_subdivisions_are_normalized_and_holes_and_islands_survive(self):
        mainland = Polygon(
            [(-101, 40), (-100, 40), (-100, 41), (-101, 41), (-101, 40)],
            [
                [
                    (-100.8, 40.2),
                    (-100.8, 40.6),
                    (-100.4, 40.6),
                    (-100.4, 40.2),
                    (-100.8, 40.2),
                ]
            ],
        )
        island = box(-98.5, 40, -98.4, 40.1)
        neighbor = box(-100, 40, -99, 41)
        members = [
            boundaries.Member(
                "KS",
                boundaries.node("us-KS", "Kansas", "state", "census", "united-states"),
                {},
                MultiPolygon([mainland, island]),
                5070,
            ),
            boundaries.Member(
                "MO",
                boundaries.node(
                    "us-MO", "Missouri", "state", "census", "united-states"
                ),
                {},
                neighbor,
                5070,
            ),
        ]
        probes = {
            "hole": (-100.6, 40.4),
            "island": (-98.45, 40.05),
            "neighbor": (-99.5, 40.5),
        }
        features, report, source, candidate = boundaries.convert_subdivisions(
            members, "united-states", probes
        )
        self.assertEqual(["us-KS", "us-MO"], [pair[0]["id"] for pair in features])
        self.assertEqual(
            [source[name] for name in probes], [candidate[name] for name in probes]
        )
        self.assertEqual(
            {"parts": 2, "holes": 1},
            {k: report["members"]["KS"]["candidate"][k] for k in ("parts", "holes")},
        )
        self.assertNotIn("outline", report)
        kansas, missouri = (feature[1] for feature in features)
        self.assertFalse(kansas.covers(Point(*probes["hole"])))
        self.assertTrue(kansas.covers(Point(*probes["island"])))
        self.assertFalse(kansas.covers(Point(*probes["neighbor"])))
        self.assertTrue(missouri.covers(Point(*probes["neighbor"])))

    def test_rejects_an_unsplit_antimeridian_edge(self):
        with self.assertRaisesRegex(ValueError, "antimeridian"):
            boundaries.canonical(box(-179, 50, 179, 51))
        split = MultiPolygon([box(178, 50, 179, 51), box(-179, 50, -178, 51)])
        self.assertEqual(2, len(boundaries.canonical(split).geoms))


if __name__ == "__main__":
    unittest.main()
