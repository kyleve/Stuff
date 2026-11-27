"""Offline coverage and displacement regressions for tracking sources."""

import unittest

import shapely
from shapely.geometry import MultiPolygon, Polygon, box

from tracking_accuracy import certify_tracking, restore_tracking


class TrackingAccuracyTests(unittest.TestCase):
    def setUp(self):
        self.pins = {k: {"archive": "sha"} for k in ("A", "B")}
        # The long shared edge bends east between two straight sections. Sampling
        # only its endpoints, or only the outer corners, reports zero displacement.
        shared = [(0, 0), (0, 0.25), (0.002, 0.5), (0, 0.75), (0, 1)]
        left = [(-1, 0), *shared, (-1, 1)]
        right = [(1, 0), (1, 1), *reversed(shared)]
        self.source = {"A": Polygon(left), "B": Polygon(right)}
        self.simple = {"A": box(-1, 0, 0, 1), "B": box(0, 0, 1, 1)}

    def test_selective_restoration_uses_the_same_shared_edge_in_both_directions(self):
        with self.assertRaisesRegex(ValueError, "displacement"):
            certify_tracking(self.source, self.simple, self.pins, {})
        restored = restore_tracking(self.source, self.simple)
        self.assertTrue(shapely.coverage_is_valid(list(restored.values())))
        report = certify_tracking(self.source, restored, self.pins, {})
        self.assertEqual(set(report), {"A", "B"})
        self.assertLessEqual(
            max(row["upperBoundMetres"] for row in report.values()), 25
        )
        for geometry in restored.values():
            self.assertIn((0.002, 0.5), geometry.exterior.coords)

    def test_decoded_neighbors_must_agree_even_inside_displacement_cap(self):
        # Add a point on one side of a straight shared line. Displacement is zero.
        a = Polygon([(-1, 0), (0, 0), (0, 0.5), (0, 1), (-1, 1)])
        b = Polygon([(1, 0), (1, 1), (0, 1), (0, 0.5), (0, 0)])
        with self.assertRaisesRegex(ValueError, "Different tracking chords"):
            certify_tracking(
                {"A": a, "B": b}, {"A": a, "B": self.simple["B"]}, self.pins, {}
            )

    def test_chords_follow_seams_that_meet_on_the_output_grid(self):
        # A slight separation at the publisher's precision becomes one shared bend
        # at seven decimals. Dropping it on only one side opens a narrow gap which
        # GEOS (correctly) accepts as a nonoverlapping polygonal coverage.
        left = Polygon([(-1, 0), (0, 0), (-0.00001, 0.5), (0, 1), (-1, 1)])
        right = Polygon([(1, 0), (1, 1), (0, 1), (-0.00001, 0.5), (0, 0)])
        original_right = Polygon(
            [(x + 0.00000002, y) for x, y in right.exterior.coords]
        )
        final = {"A": left, "B": box(0, 0, 1, 1)}
        self.assertTrue(shapely.coverage_is_valid(list(final.values())))
        # Only B was repaired. A must still participate in the shared-edge check.
        with self.assertRaisesRegex(ValueError, "Different tracking chords"):
            certify_tracking(
                {"A": left, "B": original_right},
                final,
                self.pins,
                {"B": right},
            )

    def test_certificate_bounds_original_before_a_seam_repair(self):
        # Losing the original bend in a repair must not grant it a zero error bound.
        with self.assertRaisesRegex(ValueError, "displacement"):
            certify_tracking(self.source, self.simple, self.pins, self.simple)

    def test_island_hole_and_rounding_are_included_in_certificate(self):
        exterior = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        hole = [(0, 0), (0.20000004, 0), (0.2, 0.2), (0, 0.2)]
        island = box(2, 2, 3, 3)
        source = {"A": MultiPolygon([Polygon(exterior, [hole]), island])}
        simplified = {"A": shapely.set_precision(source["A"], 1e-7)}
        report = certify_tracking(
            source, restore_tracking(source, simplified), {"A": self.pins["A"]}, {}
        )
        self.assertGreater(report["A"]["upperBoundMetres"], 0)
        for missing in (
            Polygon(exterior, [hole]),
            MultiPolygon([Polygon(exterior), island]),
        ):
            with self.assertRaisesRegex(ValueError, "count changed"):
                certify_tracking(
                    source,
                    {"A": shapely.set_precision(missing, 1e-7)},
                    {"A": self.pins["A"]},
                    {},
                )
