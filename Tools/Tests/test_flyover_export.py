import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from Tools.flyover_export import ExportRequest, build_environment, export_atlas
from Tools.Tests.flyover_test_support import create_flyover_artifact


class FlyoverExportTests(unittest.TestCase):
    def test_capture_validation_and_publication_order(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            destination = root / 'atlas'
            events = []
            def run(arguments, *, environment=None):
                if environment is None:
                    events.append('build')
                    create_flyover_artifact(Path(arguments[1]))
                else:
                    events.append('capture')
                    self.assertEqual(arguments[1:], ['--only',
                        'WhereUISnapshotTests/WhereFlyoverWebExportTests/exportsRequestedAtlas()'])
                    self.assertEqual(environment['FLYOVER_EXPORT_PROFILES'], 'phone-light')
                    self.assertFalse(destination.exists())
            with patch.dict(os.environ, {'FLYOVER_WEB_BUILD_RUNNER': 'build'}), \
                 patch('Tools.flyover_export.build_environment', return_value={}), \
                 patch('Tools.flyover_export.run_capture_process', side_effect=run):
                export_atlas(ExportRequest(destination, ('phone-light',)), root)
            self.assertEqual(events, ['build', 'capture'])
            self.assertTrue((destination / 'manifest.json').is_file())
            self.assertEqual(list(root.iterdir()), [destination])

    def test_capture_and_validation_failures_preserve_previous_artifact(self):
        for phase in ('capture', 'validation'):
            with self.subTest(phase=phase), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                destination = create_flyover_artifact(root / 'atlas')
                (destination / 'retained').write_text('old')
                def run(arguments, *, environment=None):
                    if environment is None:
                        create_flyover_artifact(Path(arguments[1]))
                    elif phase == 'capture':
                        raise subprocess.CalledProcessError(19, arguments)
                    else:
                        (Path(environment['FLYOVER_EXPORT_DIRECTORY']) / 'manifest.json').write_text('{}')
                with patch.dict(os.environ, {'FLYOVER_WEB_BUILD_RUNNER': 'build'}), \
                     patch('Tools.flyover_export.build_environment', return_value={}), \
                     patch('Tools.flyover_export.run_capture_process', side_effect=run):
                    with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                        export_atlas(ExportRequest(destination, ('phone-light',)), root)
                self.assertEqual((destination / 'retained').read_text(), 'old')
                self.assertEqual(list(root.iterdir()), [destination])

    def test_git_failure_is_not_a_clean_tree(self):
        result = subprocess.CompletedProcess([], 71, stdout='')
        with patch('Tools.flyover_export.subprocess.run', return_value=result):
            with self.assertRaisesRegex(ValueError, 'could not read the Git working-tree status'):
                build_environment(Path('/workspace'), Path('/output'))

    def test_existing_output_is_excluded_from_dirty_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / 'generated'
            output.mkdir()
            result = subprocess.CompletedProcess([], 0, stdout='')
            with patch.dict(os.environ, {'FLYOVER_XCODE_VERSION_OVERRIDE': 'Tests'}), \
                 patch('Tools.flyover_export.subprocess.run', return_value=result) as run:
                environment = build_environment(root, output)
            self.assertEqual(environment['FLYOVER_EXPORT_DIRTY'], 'false')
            self.assertIn(':(exclude,top,literal)generated', run.call_args_list[0].args[0])
