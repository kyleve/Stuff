"""Public command parsing and trusted dependency selection, without Apple access."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from Tools.repository import repository_root

ROOT = repository_root(Path(__file__))


class WhereArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / 'checkout with spaces ü'
        for name in ('signing', 'Where/archive', 'Tools/InstallerKit/signing_command.rb',
                     'Tools/InstallerKit/signing_apps.json', 'Tools/repository.rb'):
            destination = self.root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, destination)
        (self.root / '.git').mkdir()
        (self.root / 'ide').touch()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.log = self.root / 'calls'
        mise = self.bin / 'mise'
        mise.write_text('#!/bin/bash\nprintf "%s\\n" "$BUNDLE_GEMFILE" "$@" >> "$LOG"\nexit "${FAIL:-0}"\n')
        mise.chmod(0o755)
        self.env = {'PATH': f'{self.bin}:/usr/bin:/bin', 'LOG': str(self.log)}

    def run_command(self, *arguments, command='signing', overrides=None):
        return subprocess.run([str(self.root / command), *arguments], cwd='/tmp',
                              env={**self.env, **(overrides or {})}, capture_output=True, text=True)

    def test_help_without_tools_from_other_directory(self):
        # Bash dirname must be available for wrappers, but no mise/Xcode/Ruby gems.
        result = self.run_command('--help', command='Where/archive', overrides={'PATH': '/usr/bin:/bin'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Usage:', result.stdout)
        self.assertFalse(self.log.exists())

    def test_invalid_input_precedes_dependencies(self):
        cases = [('archive', '--app', 'missing', '--output', '/tmp/out'),
                 ('archive', '--app', 'where'),
                 ('refresh', '--app', 'where', '--output', '/tmp/out'),
                 ('register-device', '--app', 'where', '--name', 'Phone', '--udid', 'bad'),
                 ('archive', '--app', 'where', '--output', str(self.root))]
        for arguments in cases:
            with self.subTest(arguments=arguments):
                self.assertNotEqual(self.run_command(*arguments).returncode, 0)
                self.assertFalse(self.log.exists())

    def test_archive_uses_control_gemfile_and_absolute_source_and_output(self):
        output = self.root / 'new output'
        source = self.root / 'old source'
        source.mkdir()
        (source / 'ide').touch()  # No Fastfile or Gemfile on this old branch.
        result = self.run_command('--output', str(output), '--source', str(source), command='Where/archive')
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.log.read_text()
        self.assertEqual(calls.count(str(self.root / 'Gemfile')), 2)
        for expected in ('bundle\ncheck', 'bundle\nexec\nfastlane\narchive', f'source:{source}', f'output:{output}', 'app:where'):
            self.assertIn(expected, calls)

    def test_missing_dependencies_and_ci_maintenance_fail(self):
        result = self.run_command('refresh', '--app', 'where', overrides={'FAIL': '47'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('./ide --install --no-open', result.stderr)
        self.log.unlink()
        result = self.run_command('refresh', '--app', 'where', overrides={'CI': 'true'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('local only', result.stderr)
        self.assertFalse(self.log.exists())
