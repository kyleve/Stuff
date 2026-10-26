import contextlib
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from Tools import flyover_cli


class FlyoverCLITests(unittest.TestCase):
    def test_defaults_and_additive_profiles(self):
        for arguments, profiles in (([], ('phone-light', 'phone-dark')),
                                    (['--profile', 'phone-dark', '--profile', 'phone-light',
                                      '--profile', 'phone-dark'], ('phone-dark', 'phone-light'))):
            with patch.object(flyover_cli, 'export_atlas') as export:
                self.assertEqual(flyover_cli.main(['export', '--output', '/tmp/flyover-cli-test', *arguments]), 0)
                self.assertEqual(export.call_args.args[0].profiles, profiles)

    def test_invalid_options_do_not_start_export(self):
        for arguments in (['--profile', 'system'], ['--output'], ['--profile'], ['--unknown']):
            with self.subTest(arguments=arguments), patch.object(flyover_cli, 'export_atlas') as export:
                with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                    flyover_cli.main(['export', *arguments])
                export.assert_not_called()

    def test_unknown_app_does_not_start_export(self):
        with patch.object(flyover_cli, 'export_atlas') as export, contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(flyover_cli.main(['export', '--app', 'unknown']), 1)
            export.assert_not_called()

    def test_propagates_child_failure_and_signals(self):
        for failure, status in ((subprocess.CalledProcessError(19, ['capture']), 19),
                                (subprocess.CalledProcessError(-15, ['capture']), 143),
                                (flyover_cli.Interrupted(2), 130)):
            with patch.object(flyover_cli, 'export_atlas', side_effect=failure):
                self.assertEqual(flyover_cli.main(['export', '--output', '/tmp/flyover-cli-test']), status)

    def test_help_from_unrelated_directory_with_minimal_path(self):
        command = Path(__file__).resolve().parents[2] / 'flyover'
        with tempfile.TemporaryDirectory(prefix='Flyover space-é-') as directory:
            result = subprocess.run([str(command), '--help'], cwd=directory,
                                    env={'PATH': '/usr/bin:/bin', 'HOME': os.environ['HOME']},
                                    text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('./flyover export', result.stdout)
