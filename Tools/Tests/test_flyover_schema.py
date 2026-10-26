import unittest
import json
from pathlib import Path

from Tools.flyover_schema import validate_manifest
from Tools.flyover_schema_values import FlyoverArtifactError
from Tools.Tests.flyover_test_support import flyover_manifest_fixture


class FlyoverSchemaTests(unittest.TestCase):
    def test_shared_native_wire_fixture(self):
        path = (
            Path(__file__).resolve().parents[2]
            / "Shared/Flyover/Tests/Fixtures/manifest-v1.json"
        )
        validate_manifest(json.loads(path.read_text()))

    def test_profile_viewport_size_is_optional_but_must_be_positive(self):
        manifest = flyover_manifest_fixture()
        validate_manifest(manifest)
        for size in (
            {"width": 0, "height": 874},
            {"width": 402},
            {"width": True, "height": 874},
        ):
            manifest["profiles"][0]["viewportSize"] = size
            with self.subTest(size=size), self.assertRaises(FlyoverArtifactError):
                validate_manifest(manifest)

    def test_valid_catalog_needs_no_files(self):
        validate_manifest(flyover_manifest_fixture())

    def test_checks_schema_at_the_pure_boundary(self):
        for value in ([], {}, {"schemaVersion": True}, {"schemaVersion": 2}):
            with self.subTest(value=value), self.assertRaises(FlyoverArtifactError):
                validate_manifest(value)

    def test_rejects_inconsistent_catalog_references(self):
        for mutate, message in (
            (
                lambda m: m["groups"][0].update(rootScreenID="missing"),
                "not in its screenIDs",
            ),
            (
                lambda m: m["screens"][0].update(groupID="missing"),
                "does not match its group",
            ),
            (
                lambda m: m["screens"][0].update(incomingRouteIDs=["missing"]),
                "does not match manifest.routes",
            ),
            (
                lambda m: m["screens"][0]["variants"].append(
                    m["screens"][0]["variants"][0]
                ),
                "duplicate identifier",
            ),
        ):
            with self.subTest(message=message):
                manifest = flyover_manifest_fixture()
                mutate(manifest)
                with self.assertRaisesRegex(FlyoverArtifactError, message):
                    validate_manifest(manifest)
