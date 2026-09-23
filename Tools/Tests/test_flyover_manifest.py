import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

try:
    from Tools.Tests.flyover_test_support import (
        create_flyover_artifact,
        write_manifest,
    )
except ModuleNotFoundError as error:
    if error.name != "Tools":
        raise
    from flyover_test_support import create_flyover_artifact, write_manifest


MODULE_PATH = Path(__file__).resolve().parents[1] / "flyover_manifest.py"
SPEC = importlib.util.spec_from_file_location("flyover_manifest", MODULE_PATH)
flyover_manifest = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
sys.modules[SPEC.name] = flyover_manifest
SPEC.loader.exec_module(flyover_manifest)


class FlyoverManifestTests(unittest.TestCase):
    def test_validates_generated_artifact_and_builds_allowlist(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = create_flyover_artifact(Path(temporary))

            artifact = flyover_manifest.validate_artifact(root)

            self.assertEqual(artifact.root, root)
            self.assertEqual(
                artifact.allowed_paths,
                frozenset(
                    {
                        "index.html",
                        "manifest.json",
                        "manifest.js",
                        "assets/app.js",
                        "assets/styles.css",
                        "images/screen-0001/variant-0001/phone-light.png",
                    }
                ),
            )

    def test_rejects_invalid_marker_and_symbolic_links(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary_root = Path(temporary)
            root = create_flyover_artifact(temporary_root / "atlas")
            (root / ".flyover-generated").write_text("schemaVersion=2\n")
            with self.assertRaisesRegex(
                flyover_manifest.FlyoverArtifactError,
                "generated marker is unsupported",
            ):
                flyover_manifest.validate_artifact(root)

            (root / ".flyover-generated").write_bytes(b"\xff")
            with self.assertRaisesRegex(
                flyover_manifest.FlyoverArtifactError,
                "could not read",
            ):
                flyover_manifest.validate_artifact(root)

            (root / ".flyover-generated").write_text("schemaVersion=1\n")
            (root / "leak").symlink_to(temporary_root / "outside")
            with self.assertRaisesRegex(
                flyover_manifest.FlyoverArtifactError,
                "contains a symbolic link",
            ):
                flyover_manifest.validate_artifact(root)

    def test_rejects_unsafe_missing_duplicate_and_extra_images(self):
        scenarios = (
            ("../outside.png", "unsafe image path"),
            ("/outside.png", "unsafe image path"),
            ("images/missing.png", "manifest image is missing"),
        )
        for relative_path, message in scenarios:
            with self.subTest(relative_path=relative_path):
                with tempfile.TemporaryDirectory() as temporary:
                    root = create_flyover_artifact(Path(temporary))
                    manifest_path = root / "manifest.json"
                    manifest = json.loads(manifest_path.read_text())
                    manifest["images"][0]["relativePath"] = relative_path
                    if relative_path == "images/missing.png":
                        manifest["screens"][0]["variants"][0]["imagesByProfile"][
                            "phone-light"
                        ] = relative_path
                    write_manifest(root, manifest)
                    with self.assertRaisesRegex(
                        flyover_manifest.FlyoverArtifactError,
                        message,
                    ):
                        flyover_manifest.validate_artifact(root)

        with tempfile.TemporaryDirectory() as temporary:
            root = create_flyover_artifact(Path(temporary))
            manifest_path = root / "manifest.json"
            manifest = json.loads(manifest_path.read_text())
            manifest["images"].append(dict(manifest["images"][0]))
            write_manifest(root, manifest)
            with self.assertRaisesRegex(
                flyover_manifest.FlyoverArtifactError,
                "duplicate screen, variant, and profile record",
            ):
                flyover_manifest.validate_artifact(root)

        with tempfile.TemporaryDirectory() as temporary:
            root = create_flyover_artifact(Path(temporary))
            (root / "images/extra.png").write_bytes(b"PNG")
            with self.assertRaisesRegex(
                flyover_manifest.FlyoverArtifactError,
                "image files do not match",
            ):
                flyover_manifest.validate_artifact(root)

    def test_rejects_non_object_boolean_schema_and_mismatched_script(self):
        scenarios = (
            ([], "not a JSON object"),
            ({"schemaVersion": True, "images": []}, "schemaVersion 1"),
        )
        for manifest, message in scenarios:
            with self.subTest(manifest=manifest):
                with tempfile.TemporaryDirectory() as temporary:
                    root = create_flyover_artifact(Path(temporary))
                    write_manifest(root, manifest)
                    with self.assertRaisesRegex(
                        flyover_manifest.FlyoverArtifactError,
                        message,
                    ):
                        flyover_manifest.validate_artifact(root)

        with tempfile.TemporaryDirectory() as temporary:
            root = create_flyover_artifact(Path(temporary))
            (root / "manifest.js").write_text("window.FLYOVER_MANIFEST = {};\n")
            with self.assertRaisesRegex(
                flyover_manifest.FlyoverArtifactError,
                "manifest.js does not match manifest.json",
            ):
                flyover_manifest.validate_artifact(root)

    def test_rejects_incomplete_and_internally_inconsistent_manifests(self):
        scenarios = (
            (
                lambda manifest: manifest.pop("application"),
                "manifest.application is not an object",
            ),
            (
                lambda manifest: manifest["build"].pop("generatedAt"),
                "manifest.build is missing generatedAt",
            ),
            (
                lambda manifest: manifest["canvas"].pop("screenFrames"),
                "manifest.canvas is missing screenFrames",
            ),
            (
                lambda manifest: manifest["groups"][0].update(
                    {
                        "rootScreenID": "missing-screen",
                        "screenIDs": ["missing-screen"],
                    }
                ),
                "references an unknown screen",
            ),
            (
                lambda manifest: manifest["images"][0].update(
                    {"profileID": "missing-profile"}
                ),
                "references an unknown profile",
            ),
            (
                lambda manifest: manifest.update({"images": []}),
                "manifest.images is empty",
            ),
        )
        for mutate, message in scenarios:
            with self.subTest(message=message):
                with tempfile.TemporaryDirectory() as temporary:
                    root = create_flyover_artifact(Path(temporary))
                    manifest = json.loads((root / "manifest.json").read_text())
                    mutate(manifest)
                    write_manifest(root, manifest)

                    with self.assertRaisesRegex(
                        flyover_manifest.FlyoverArtifactError,
                        message,
                    ):
                        flyover_manifest.validate_artifact(root)

    def test_accepts_optional_complete_thumbnail_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = create_flyover_artifact(Path(temporary))
            thumbnail_relative = (
                "images/screen-0001/variant-0001/phone-light-thumbnail.png"
            )
            thumbnail = root / thumbnail_relative
            thumbnail.write_bytes(b"THUMBNAIL")
            manifest = json.loads((root / "manifest.json").read_text())
            manifest["images"][0].update(
                {
                    "thumbnailRelativePath": thumbnail_relative,
                    "thumbnailPixelWidth": 300,
                    "thumbnailPixelHeight": 650,
                }
            )
            write_manifest(root, manifest)

            artifact = flyover_manifest.validate_artifact(root)

            self.assertIn(thumbnail_relative, artifact.allowed_paths)

    def test_rejects_incomplete_or_undeclared_thumbnail_assets(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = create_flyover_artifact(Path(temporary))
            manifest = json.loads((root / "manifest.json").read_text())
            manifest["images"][0]["thumbnailRelativePath"] = (
                "images/screen-0001/variant-0001/phone-light-thumbnail.png"
            )
            write_manifest(root, manifest)
            with self.assertRaisesRegex(
                flyover_manifest.FlyoverArtifactError,
                "incomplete thumbnail metadata",
            ):
                flyover_manifest.validate_artifact(root)

        with tempfile.TemporaryDirectory() as temporary:
            root = create_flyover_artifact(Path(temporary))
            (root / "images/screen-0001/variant-0001/extra-thumbnail.png").write_bytes(
                b"THUMBNAIL"
            )
            with self.assertRaisesRegex(
                flyover_manifest.FlyoverArtifactError,
                "image files do not match",
            ):
                flyover_manifest.validate_artifact(root)


if __name__ == "__main__":
    unittest.main()
