import unittest

from Tools.flyover_images import validate_images
from Tools.flyover_schema_values import FlyoverArtifactError
from Tools.Tests.flyover_test_support import flyover_manifest_fixture


class FlyoverImagesTests(unittest.TestCase):
    def test_image_coverage_and_capture_extent(self):
        manifest = flyover_manifest_fixture()
        profiles = {item['id']: item for item in manifest['profiles']}
        screens = {item['id']: item for item in manifest['screens']}
        variants = {(screen['id'], variant['id']): variant
                    for screen in manifest['screens'] for variant in screen['variants']}
        validate_images(manifest['images'], profiles, screens, variants)
        manifest['images'][0]['captureExtent'] = 'fullContent'
        with self.assertRaisesRegex(FlyoverArtifactError, 'does not match its variant'):
            validate_images(manifest['images'], profiles, screens, variants)
