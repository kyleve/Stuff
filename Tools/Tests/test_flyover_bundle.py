import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from Tools.flyover_bundle import pack_bundle, unpack_bundle, validate_bundle
from Tools.Tests.flyover_bundle_support import SHA, create_bundle


class FlyoverBundleTests(unittest.TestCase):
    def test_round_trip_contains_all_apps(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = create_bundle(root / 'source')
            archive = root / 'atlases.zip'
            pack_bundle(source, archive, SHA)
            destination = root / 'destination'
            destination.mkdir()
            self.assertEqual(len(unpack_bundle(archive, destination, SHA)['apps']), 2)
            self.assertEqual((destination / 'second/manifest.json').read_bytes(),
                             (source / 'second/manifest.json').read_bytes())

    def test_identity_dirty_and_asset_mismatches_fail(self):
        for change in ('sha', 'dirty', 'app', 'extra', 'missing'):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as temporary:
                source = create_bundle(Path(temporary) / 'source')
                path = source / 'where/manifest.json'
                manifest = json.loads(path.read_text())
                if change == 'sha':
                    manifest['build']['commit'] = 'b' * 40
                elif change == 'dirty':
                    manifest['build']['dirty'] = True
                elif change == 'app':
                    manifest['application']['id'] = 'other'
                elif change == 'extra':
                    (source / 'secret').write_text('not public')
                else:
                    (source / 'where/index.html').unlink()
                path.write_text(json.dumps(manifest))
                with self.assertRaises(ValueError):
                    validate_bundle(source, SHA)

    def test_zip_paths_links_duplicates_and_size_are_rejected_before_extraction(self):
        for name in ('../escape', '/absolute', 'one/../escape', 'one\\escape', 'one//escape', 'link', 'duplicate', 'large'):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                archive = root / 'bad.zip'
                with zipfile.ZipFile(archive, 'w') as output:
                    info = zipfile.ZipInfo(name)
                    if name == 'link':
                        info.external_attr = (stat.S_IFLNK | 0o777) << 16
                    output.writestr(info, b'123')
                    if name == 'duplicate':
                        output.writestr(name, b'123')
                destination = root / 'destination'
                destination.mkdir()
                with patch('Tools.flyover_bundle.MAX_BYTES', 2 if name == 'large' else 1000):
                    with self.assertRaises(ValueError):
                        unpack_bundle(archive, destination)
                self.assertEqual(list(destination.iterdir()), [])

    def test_wrong_expected_revision_and_file_budget_fail(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = create_bundle(Path(temporary) / 'source')
            with self.assertRaises(ValueError):
                validate_bundle(source, 'b' * 40)
            with patch('Tools.flyover_bundle.MAX_FILES', 1), self.assertRaises(ValueError):
                validate_bundle(source)
