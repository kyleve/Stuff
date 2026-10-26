import unittest

from Tools.flyover_canvas import validate_canvas
from Tools.flyover_schema_values import FlyoverArtifactError
from Tools.Tests.flyover_test_support import flyover_manifest_fixture


class FlyoverCanvasTests(unittest.TestCase):
    def test_geometry_and_catalog_parity(self):
        manifest = flyover_manifest_fixture()
        groups = {item['id']: item for item in manifest['groups']}
        screens = {item['id']: item for item in manifest['screens']}
        validate_canvas(manifest['canvas'], groups, screens, {})
        manifest['canvas']['screenFrames'][0]['frame'] = dict(x=0, y=0, width=1, height=1)
        with self.assertRaisesRegex(FlyoverArtifactError, 'does not match its screen frame'):
            validate_canvas(manifest['canvas'], groups, screens, {})
