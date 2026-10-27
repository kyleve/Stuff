import unittest

from Tools.flyover_schema_values import (
    FlyoverArtifactError,
    integer,
    number,
    safe_image_path,
)


class FlyoverSchemaValuesTests(unittest.TestCase):
    def test_numeric_validation_rejects_booleans_and_nonfinite_values(self):
        for value in (True, False, float("nan"), float("inf")):
            with self.subTest(value=value), self.assertRaises(FlyoverArtifactError):
                number(value, "dimension")
        with self.assertRaises(FlyoverArtifactError):
            integer(True, "count")

    def test_image_paths_are_relative_and_confined(self):
        for value in (
            "../outside.png",
            "/images/image.png",
            "images/../image.png",
            "assets/image.png",
        ):
            with self.subTest(value=value), self.assertRaises(FlyoverArtifactError):
                safe_image_path(value)
