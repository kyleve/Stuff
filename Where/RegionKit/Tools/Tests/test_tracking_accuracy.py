"""Offline coverage and displacement regressions for the US tracking release."""

import unittest

import shapely
from shapely.geometry import MultiPolygon, Polygon, box

from tracking_accuracy import certify_tracking, restore_tracking


class TrackingAccuracyTests(unittest.TestCase):
    def setUp(self):
        # The long shared edge bends east between two straight sections. Sampling
        # only its endpoints, or only the outer corners, reports zero displacement.
        shared = [(0, 0), (0, 0.25), (0.002, 0.5), (0, 0.75), (0, 1)]
        left = [(-1, 0), *shared, (-1, 1)]
        right = [(1, 0), (1, 1), *reversed(shared)]
        self.source = {"A": Polygon(left), "B": Polygon(right)}
        self.simple = {"A": box(-1, 0, 0, 1), "B": box(0, 0, 1, 1)}

    def test_selective_restoration_uses_the_same_shared_edge_in_both_directions(self):
        with self.assertRaisesRegex(ValueError, "displacement"):
            certify_tracking(self.source, self.simple, "source")
        restored = restore_tracking(self.source, self.simple)
        self.assertTrue(shapely.coverage_is_valid(list(restored.values())))
        report = certify_tracking(self.source, restored, "source")
        self.assertEqual(set(report["members"]), {"us-A", "us-B"})
        self.assertLessEqual(report["maximumUpperBoundMetres"], 25)
        for geometry in restored.values():
            self.assertIn((0.002, 0.5), geometry.exterior.coords)

    def test_decoded_neighbors_must_agree_even_inside_displacement_cap(self):
        # Add a point on one side of a straight shared line. Displacement is zero.
        a = Polygon([(-1, 0), (0, 0), (0, 0.5), (0, 1), (-1, 1)])
        b = Polygon([(1, 0), (1, 1), (0, 1), (0, 0.5), (0, 0)])
        with self.assertRaisesRegex(ValueError, "Different tracking chords"):
            certify_tracking(
                {"A": a, "B": b}, {"A": a, "B": self.simple["B"]}, "source"
            )

    def test_island_hole_and_rounding_are_included_in_certificate(self):
        exterior = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        hole = [(0, 0), (0.20000004, 0), (0.2, 0.2), (0, 0.2)]
        island = box(2, 2, 3, 3)
        source = {"A": MultiPolygon([Polygon(exterior, [hole]), island])}
        simplified = {"A": shapely.set_precision(source["A"], 1e-7)}
        report = certify_tracking(
            source, restore_tracking(source, simplified), "source"
        )
        self.assertGreater(report["maximumUpperBoundMetres"], 0)
        for missing in (
            Polygon(exterior, [hole]),
            MultiPolygon([Polygon(exterior), island]),
        ):
            with self.assertRaisesRegex(ValueError, "count changed"):
                certify_tracking(
                    source, {"A": shapely.set_precision(missing, 1e-7)}, "source"
                )
