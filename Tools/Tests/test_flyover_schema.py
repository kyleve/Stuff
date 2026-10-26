import unittest

from Tools.flyover_schema import validate_manifest
from Tools.flyover_schema_values import FlyoverArtifactError
from Tools.Tests.flyover_test_support import flyover_manifest_fixture


class FlyoverSchemaTests(unittest.TestCase):
    def test_valid_catalog_needs_no_files(self):
        validate_manifest(flyover_manifest_fixture())

    def test_checks_schema_at_the_pure_boundary(self):
        for value in ([], {}, {'schemaVersion': True}, {'schemaVersion': 2}):
            with self.subTest(value=value), self.assertRaises(FlyoverArtifactError):
                validate_manifest(value)

    def test_rejects_inconsistent_catalog_references(self):
        for mutate, message in (
            (lambda m: m['groups'][0].update(rootScreenID='missing'), 'not in its screenIDs'),
            (lambda m: m['screens'][0].update(groupID='missing'), 'does not match its group'),
            (lambda m: m['screens'][0].update(incomingRouteIDs=['missing']), 'does not match manifest.routes'),
            (lambda m: m['screens'][0]['variants'].append(m['screens'][0]['variants'][0]), 'duplicate identifier'),
        ):
            with self.subTest(message=message):
                manifest = flyover_manifest_fixture()
                mutate(manifest)
                with self.assertRaisesRegex(FlyoverArtifactError, message):
                    validate_manifest(manifest)
