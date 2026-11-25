"""Restore selected TIGER vertices and certify the emitted tracking rings against the source."""

import base64
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess

import shapely
from shapely.geometry import MultiPolygon, Point, Polygon, mapping


CAP_METRES = 25
RESTORE_METRES = 24
DECIMALS = 7
# Both WGS84 curvature radii are below 6,400,000 m. Longitude also scales by cos(latitude).
METRES_PER_DEGREE = math.radians(6_400_000)


def edge(a, b):
    return (a, b) if a < b else (b, a)


def chain_bound(points):
    """Bound both directions between this chain and its chord in ground metres.

    In the scaled plane, distance to a segment is convex along each source edge,
    so its maximum occurs at a vertex. Conversely the connected chain projects
    continuously onto the whole chord, since they share endpoints. This plane
    overestimates WGS84 ground lengths throughout the chain's latitude range.
    """
    if len(points) == 2:
        return 0, 0
    latitudes = [p[1] for p in points]
    latitude = max(0, min(latitudes), -max(latitudes))
    sx = METRES_PER_DEGREE * math.cos(math.radians(latitude))
    ax, ay = points[0]
    bx, by = points[-1]
    dx, dy = (bx - ax) * sx, (by - ay) * METRES_PER_DEGREE
    length_squared = dx * dx + dy * dy
    maximum, furthest = 0, 0
    for i, (lon, lat) in enumerate(points[1:-1], 1):
        x, y = (lon - ax) * sx, (lat - ay) * METRES_PER_DEGREE
        t = max(0, min(1, (dx * x + dy * y) / length_squared))
        squared = (x - t * dx) ** 2 + (y - t * dy) ** 2
        if squared > maximum:
            maximum, furthest = squared, i
    return math.sqrt(maximum), furthest


def restore_chain(points):
    # Identical shared arcs have the same farthest-point tie break on both sides.
    if points[0] > points[-1]:
        return restore_chain(points[::-1])[::-1]
    maximum, split = chain_bound(points)
    if maximum <= RESTORE_METRES:
        return [points[0], points[-1]]
    return restore_chain(points[: split + 1])[:-1] + restore_chain(points[split:])


class SourceRing:
    """Correspondence between a full unrounded ring and its seven-decimal vertices."""

    def __init__(self, ring):
        source = list(ring.coords)
        self.points = [(round(x, DECIMALS), round(y, DECIMALS)) for x, y in source[:-1]]
        self.indices = {p: i for i, p in enumerate(self.points)}
        if len(self.indices) != len(self.points):
            raise ValueError("Rounded source ring has an ambiguous vertex")
        if any(abs(a[0] - b[0]) > 180 for a, b in zip(source, source[1:])):
            raise ValueError(
                "Split the TIGER ring at the antimeridian before certification"
            )
        # The same interpolation parameter pairs every point on each raw and rounded edge.
        self.rounding = METRES_PER_DEGREE * max(
            map(math.dist, source[:-1], self.points)
        )

    def chains(self, ring):
        indices = [self.indices[p] for p in ring.coords[:-1]]
        n = len(self.points)
        for direction in (1, -1):
            pairs = list(zip(indices, indices[1:] + indices[:1], strict=True))
            if sum((direction * (j - i)) % n for i, j in pairs) == n:
                break
        else:
            raise ValueError(
                "Simplified ring does not traverse the source ring exactly once"
            )
        for i, j in pairs:
            if i == j:
                raise ValueError("Repeated point in simplified ring")
            if direction < 0:
                i, j = j, i
            chain = (
                self.points[i : j + 1]
                if i < j
                else self.points[i:] + self.points[: j + 1]
            )
            yield chain if direction > 0 else chain[::-1]


def corresponding_rings(source, simplified):
    """Pair exteriors and holes with their retained vertices, independent of their order."""
    source_parts = list(shapely.get_parts(source))
    candidates = list(shapely.get_parts(simplified))
    if len(source_parts) != len(candidates):
        raise ValueError("TIGER polygon part count changed")
    parts = [(SourceRing(part.exterior), part.interiors) for part in source_parts]

    def take(ring, available):
        anchor = ring.coords[0]
        hits = [
            i for i, (original, _) in enumerate(available) if anchor in original.indices
        ]
        matches = [
            i
            for i in hits
            if all(p in available[i][0].indices for p in ring.coords[:-1])
        ]
        if len(matches) != 1:
            raise ValueError(
                f"Cannot match retained TIGER vertices to one source ring at {anchor}"
            )
        return available.pop(matches[0])

    for part in candidates:
        exterior, source_holes = take(part.exterior, parts)
        if len(source_holes) != len(part.interiors):
            raise ValueError("TIGER polygon hole count changed")
        pairs = [(exterior, part.exterior)]
        holes = [(SourceRing(r), None) for r in source_holes]
        for hole in part.interiors:
            original, _ = take(hole, holes)
            pairs.append((original, hole))
        yield pairs


def restore_member(source, simplified, forced):
    polygons, origins = [], {}
    for pairs in corresponding_rings(source, simplified):
        rings = []
        for original, ring in pairs:
            retained = []
            for chain in original.chains(ring):
                key = edge(chain[0], chain[-1])
                refined = chain if key in forced else restore_chain(chain)
                for a, b in zip(refined, refined[1:]):
                    origins[edge(a, b)] = key
                retained.extend(refined[:-1])
            rings.append(retained)
        polygons.append(Polygon(rings[0], rings[1:]))
    geometry = (
        MultiPolygon(polygons)
        if simplified.geom_type == "MultiPolygon"
        else polygons[0]
    )
    if geometry.is_valid:
        return geometry, set()
    # A restored bend can intersect a nearby chord. Restore both implicated source arcs
    # in full, including on their other owner, and check the whole coverage again.
    reason = shapely.is_valid_reason(geometry)
    match = re.search(r"\[([^ ]+) ([^\]]+)\]", reason)
    if not match:
        raise ValueError(f"Cannot locate invalid restored TIGER boundary: {reason}")
    location = Point(float(match[1]), float(match[2]))
    implicated = set()
    for ring in shapely.get_rings(shapely.get_parts(geometry)):
        coords = list(ring.coords)
        for a, b in zip(coords, coords[1:]):
            if shapely.LineString([a, b]).distance(location) < 1e-8:
                implicated.add(origins[edge(a, b)])
    if not implicated - forced:
        raise ValueError(
            f"Full source chains cannot repair restored TIGER boundary: {reason}"
        )
    return geometry, implicated


def restore_tracking(source, simplified):
    if source.keys() != simplified.keys() or not source:
        raise ValueError("TIGER coverage membership changed")
    forced = set()
    while True:
        output, repairs = {}, set()
        for code, geometry in simplified.items():
            output[code], implicated = restore_member(source[code], geometry, forced)
            repairs.update(implicated)
        if not repairs:
            if not shapely.coverage_is_valid(list(output.values())):
                raise ValueError(
                    "Restored TIGER shared borders do not form a valid coverage"
                )
            return output
        forced.update(repairs)


def decode_twkb(data):
    """Read the exact 2D, seven-decimal MultiPolygon format written by the release generator."""
    stream = iter(data)
    if (next(stream), next(stream)) != (0xE6, 0):
        raise ValueError("Unexpected tracking TWKB header")

    def unsigned():
        value = 0
        for shift in range(0, 64, 7):
            byte = next(stream)
            value |= (byte & 127) << shift
            if byte < 128:
                return value
        raise ValueError("Oversized tracking TWKB integer")

    def delta():
        number = unsigned()
        return (number >> 1) ^ -(number & 1)

    x = y = 0
    polygons = []
    for _ in range(unsigned()):
        rings = []
        for _ in range(unsigned()):
            ring = []
            for _ in range(unsigned()):
                x += delta()
                y += delta()
                ring.append((x / 10**DECIMALS, y / 10**DECIMALS))
            rings.append(ring)
        polygons.append(Polygon(rings[0], rings[1:]))
    if next(stream, None) is not None:
        raise ValueError("Trailing bytes in tracking TWKB")
    return MultiPolygon(polygons)


def certify_tracking(source, final, tiger_sha256):
    if source.keys() != final.keys() or not source:
        raise ValueError("TIGER certification membership changed")
    encoder = Path(__file__).with_name("tiny_wkb.rb")
    # Use the offline generator's encoder. Adoption hashes the independently regenerated files.
    result = subprocess.run(
        [
            "ruby",
            "-rjson",
            "-rbase64",
            "-r",
            str(encoder.resolve()),
            "-e",
            "STDIN.each_line { |line| puts Base64.strict_encode64(TinyWKB.encode(JSON.parse(line))) }",
        ],
        input="".join(json.dumps(mapping(g)) + "\n" for g in final.values()),
        text=True,
        capture_output=True,
        check=True,
    )
    members = {}
    # Each source edge owned by two states must map to precisely the same output chord.
    chords = {}
    for code, line in zip(final, result.stdout.splitlines(), strict=True):
        data = base64.b64decode(line, validate=True)
        decoded = decode_twkb(data)
        if not decoded.is_valid:
            raise ValueError(f"Invalid tracking TWKB for {code}")
        maximum = 0
        for pairs in corresponding_rings(source[code], decoded):
            for original, ring in pairs:
                for chain in original.chains(ring):
                    chord = edge(chain[0], chain[-1])
                    upper, _ = chain_bound(chain)
                    maximum = max(maximum, upper + original.rounding)
                    for a, b in zip(chain, chain[1:]):
                        if chords.setdefault(edge(a, b), chord) != chord:
                            raise ValueError(
                                f"Different tracking chords on shared TIGER edge in {code}"
                            )
        if maximum > CAP_METRES:
            raise ValueError(
                f"TIGER displacement in {code} exceeds {CAP_METRES} m: {maximum}"
            )
        members[f"us-{code}"] = {
            "sha256": hashlib.sha256(data).hexdigest(),
            "upperBoundMetres": math.ceil(maximum * 1000) / 1000,
        }
    return {
        "sourceSHA256": tiger_sha256,
        "capMetres": CAP_METRES,
        "maximumUpperBoundMetres": max(
            row["upperBoundMetres"] for row in members.values()
        ),
        "members": members,
    }
