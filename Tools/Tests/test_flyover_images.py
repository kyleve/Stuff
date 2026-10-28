import unittest

from Tools.flyover_images import validate_images
from Tools.flyover_schema_values import FlyoverArtifactError
from Tools.Tests.flyover_test_support import flyover_manifest_fixture


class FlyoverImagesTests(unittest.TestCase):
    def test_image_coverage_and_capture_extent(self):
        manifest = flyover_manifest_fixture()
        profiles = {item["id"]: item for item in manifest["profiles"]}
        screens = {item["id"]: item for item in manifest["screens"]}
        variants = {
            (screen["id"], variant["id"]): variant
            for screen in manifest["screens"]
            for variant in screen["variants"]
        }
        validate_images(manifest["images"], profiles, screens, variants)
        manifest["images"][0]["captureExtent"] = "fullContent"
        with self.assertRaisesRegex(FlyoverArtifactError, "does not match its variant"):
            validate_images(manifest["images"], profiles, screens, variants)

    def test_optional_thumbnail_variants_require_safe_ordered_matching_sizes(self):
        from Tools.flyover_schema import validate_manifest

        for mutation, message in (
            ({"relativePath": "../small.png"}, "unsafe"),
            ({"relativePath": "images/large.png"}, "duplicate"),
            ({"pixelWidth": 0}, "positive"),
            ({"pixelHeight": True}, "integer"),
            ({"pixelHeight": 1024}, "below the largest"),
            ({"pixelWidth": 128}, "aspect ratio"),
        ):
            with self.subTest(mutation=mutation):
                manifest = flyover_manifest_fixture()
                image = manifest["images"][0]
                image.update(
                    thumbnailRelativePath="images/large.png",
                    thumbnailPixelWidth=512,
                    thumbnailPixelHeight=1024,
                    thumbnailVariants=[
                        {
                            "relativePath": "images/small.png",
                            "pixelWidth": 64,
                            "pixelHeight": 128,
                        }
                    ],
                )
                validate_manifest(manifest)
                image["thumbnailVariants"][0].update(mutation)
                with self.assertRaisesRegex(FlyoverArtifactError, message):
                    validate_manifest(manifest)

    def test_thumbnail_variants_reject_duplicates_descending_sizes_and_missing_base(
        self,
    ):
        from Tools.flyover_schema import validate_manifest

        for mode in ("duplicate", "descending", "missing"):
            with self.subTest(mode=mode):
                manifest = flyover_manifest_fixture()
                image = manifest["images"][0]
                small = {
                    "relativePath": "images/small.png",
                    "pixelWidth": 64,
                    "pixelHeight": 128,
                }
                image.update(
                    thumbnailRelativePath="images/large.png",
                    thumbnailPixelWidth=512,
                    thumbnailPixelHeight=1024,
                    thumbnailVariants=[small],
                )
                if mode == "duplicate":
                    image["thumbnailVariants"].append(dict(small))
                elif mode == "descending":
                    image["thumbnailVariants"].append(
                        {**small, "relativePath": "images/other.png"}
                    )
                else:
                    for field in (
                        "thumbnailRelativePath",
                        "thumbnailPixelWidth",
                        "thumbnailPixelHeight",
                    ):
                        del image[field]
                with self.assertRaises(FlyoverArtifactError):
                    validate_manifest(manifest)
