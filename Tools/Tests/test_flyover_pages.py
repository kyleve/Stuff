import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

from Tools.flyover_bundle import pack_bundle
from Tools.flyover_pages import compose, latest_release, version_images
from Tools.Tests.flyover_bundle_support import SHA, create_bundle


class FlyoverPagesTests(unittest.TestCase):
    def test_image_urls_change_with_bytes_and_match_variant_references(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            paths = []
            for index, content in enumerate((b'first capture', b'next capture', b'first capture')):
                atlas = create_bundle(root / str(index), ('where',)) / 'where'
                manifest = json.loads((atlas / 'manifest.json').read_text())
                original = manifest['images'][0]['relativePath']
                (atlas / original).write_bytes(content)
                version_images(atlas)
                manifest = json.loads((atlas / 'manifest.json').read_text())
                updated = manifest['images'][0]['relativePath']
                paths.append(updated)
                self.assertFalse((atlas / original).exists())
                self.assertEqual((atlas / updated).read_bytes(), content)
                self.assertEqual(manifest['screens'][0]['variants'][0]['imagesByProfile']['phone-light'], updated)
            self.assertNotEqual(paths[0], paths[1])
            self.assertEqual(paths[0], paths[2])

    def test_selects_latest_complete_run_not_latest_edited_release(self):
        releases = [{'tag_name': tag, 'draft': draft} for tag, draft in (
            ('v100', False), ('flyover-atlas-10-1', False), ('flyover-atlas-9-9', False),
            ('flyover-atlas-11-1', True), ('flyover-atlas-10-2', False))]
        self.assertEqual(latest_release(releases)['tag_name'], 'flyover-atlas-10-2')
        self.assertIsNone(latest_release([]))

    def test_first_deploy_keeps_installer_and_has_empty_index(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'index.html').write_text('installer')
            with patch('Tools.flyover_pages.subprocess.check_output', return_value='[[]]'):
                compose(root, 'owner/repo')
            self.assertEqual((root / 'index.html').read_text(), 'installer')
            self.assertIn('No published', (root / 'flyover/index.html').read_text())

    def test_compose_validates_digest_and_preserves_installer(self):
        for valid in (True, False):
            with self.subTest(valid=valid), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                source = create_bundle(root / 'source', ('where',))
                archive = root / 'atlases.zip'
                pack_bundle(source, archive, SHA)
                release = {'tag_name': 'flyover-atlas-10-1', 'draft': False, 'target_commitish': SHA,
                           'assets': [{'name': 'atlases.zip', 'size': archive.stat().st_size,
                                       'digest': 'sha256:' + (hashlib.sha256(archive.read_bytes()).hexdigest() if valid else '0' * 64)}]}
                output = root / 'output'
                output.mkdir()
                (output / 'index.html').write_text('installer')
                def download(arguments, **kwargs):
                    shutil.copyfile(archive, Path(arguments[-1]) / 'atlases.zip')
                with patch('Tools.flyover_pages.subprocess.check_output', return_value=json.dumps([[release]])), \
                     patch('Tools.flyover_pages.subprocess.run', side_effect=download):
                    if valid:
                        compose(output, 'owner/repo')
                        self.assertTrue((output / 'flyover/where/index.html').is_file())
                    else:
                        with self.assertRaisesRegex(ValueError, 'digest'):
                            compose(output, 'owner/repo')
                        self.assertFalse((output / 'flyover').exists())
                self.assertEqual((output / 'index.html').read_text(), 'installer')
