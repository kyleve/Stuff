"""Setup policy and public CLI with isolated GitHub and Fastlane processes."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from Tools.InstallerKit.installer_setup import SetupFailure, setup
from Tools.repository import repository_root

ROOT = repository_root(__file__)
SHA = 'a' * 40


class InstallerSetupTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve() / 'checkout with spaces ü'
        for name in ('signing', 'Tools/repository.rb', 'Tools/repository.py',
                     'Tools/InstallerKit/signing_command.rb', 'Tools/InstallerKit/installer_setup.py',
                     'Tools/InstallerKit/installer_apps.py', '.github/installer-apps.json',
                     '.github/installer-signing-apps.json'):
            destination = self.root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, destination)
        (self.root / '.git').mkdir()
        (self.root / 'ide').touch()
        self.source = self.root / 'source checkout ü'
        self.source.mkdir()
        (self.source / 'ide').touch()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        (self.bin / 'python3').symlink_to(sys.executable)
        self.log = self.root / 'calls.jsonl'
        # No inherited credentials, developer tools, or real remote commands.
        self.env = {'PATH': f'{self.bin}:/usr/bin:/bin', 'LOG': str(self.log),
                    'FIXTURE_ROOT': str(self.root), 'GH_REPO': 'wrong/repository'}
        self.write_executable('gh', r'''
import base64, json, os, pathlib, sys
root = pathlib.Path(os.environ['FIXTURE_ROOT'])
args = sys.argv[1:]
with open(os.environ['LOG'], 'a') as log:
    log.write(json.dumps({'tool': 'gh', 'args': args, 'gh_repo': os.environ.get('GH_REPO')}) + '\n')
if args[:2] == ['variable', 'set']:
    if os.environ.get('FAIL_ENABLE'):
        print('sensitive subprocess diagnostic', file=sys.stderr)
        sys.exit(47)
    (root / 'enabled').write_text(json.dumps(args))
elif os.environ.get('FAIL_READ'):
    print('sensitive subprocess diagnostic', file=sys.stderr)
    sys.exit(43)
elif args[:2] == ['repo', 'view']:
    print('owner/repository')
elif args[1].endswith('/commits/main'):
    print('a' * 40)
else:
    name = args[1].split('/contents/.github/')[1].split('?')[0]
    value = json.loads((root / '.github' / name).read_text())
    mismatch = os.environ.get('MISMATCH') == name
    mismatch |= bool(os.environ.get('CHANGE_AFTER_REFRESH') and (root / 'refreshed').exists())
    if os.environ.get('MALFORMED'):
        value = {'invalid': True} if name == 'installer-apps.json' else []
    elif mismatch:
        if isinstance(value, list):
            value = [app for app in value if app['id'] != 'throw']
        else:
            value.pop('throw', None)
    print(base64.b64encode(json.dumps(value).encode()).decode())
''')
        self.write_executable('mise', r'''
import json, os, pathlib, sys
args = sys.argv[1:]
root = pathlib.Path(os.environ['FIXTURE_ROOT'])
with open(os.environ['LOG'], 'a') as log:
    log.write(json.dumps({'tool': 'mise', 'args': args, 'gemfile': os.environ.get('BUNDLE_GEMFILE')}) + '\n')
if 'refresh' in args:
    if os.environ.get('FAIL_REFRESH'):
        sys.exit(42)
    (root / 'refreshed').write_text(json.dumps(args))
''')

    def write_executable(self, name, content):
        path = self.bin / name
        path.write_text(f'#!{sys.executable}\n' + content)
        path.chmod(0o755)

    def command(self, *arguments, overrides=None):
        return subprocess.run([str(self.root / 'signing'), *arguments], cwd='/tmp',
                              env={**self.env, **(overrides or {})}, capture_output=True, text=True)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def assert_no_mutations(self):
        self.assertFalse((self.root / 'refreshed').exists())
        self.assertFalse((self.root / 'enabled').exists())
        self.assertTrue(all(call['tool'] == 'gh' and call['args'][0] != 'variable' for call in self.calls()))

    def test_help_before_tools_from_unrelated_directory(self):
        result = self.command('setup', '--help', overrides={'PATH': '/usr/bin:/bin'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--dry-run', result.stdout)
        self.assertEqual(result.stderr, '')
        self.assertEqual(self.calls(), [])

    def test_invalid_arguments_and_ci_precede_tools(self):
        cases = [('setup', '--app', 'missing'), ('setup', '--app', 'throw', '--source', '/missing'),
                 ('setup', '--app', 'throw', '--output', '/tmp/out'),
                 ('refresh', '--app', 'throw', '--dry-run')]
        for args in cases:
            with self.subTest(args=args):
                result = self.command(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('error:', result.stderr)
                self.assertEqual(result.stdout, '')
                self.assertEqual(self.calls(), [])
        result = self.command('setup', '--app', 'throw', overrides={'CI': 'true'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('local only', result.stderr)
        self.assertEqual(self.calls(), [])

    def test_dry_run_uses_exact_main_and_ignores_gh_repo(self):
        result = self.command('setup', '--app', 'throw', '--source', str(self.source), '--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('THROW_DISTRIBUTION_ENABLED=true', result.stdout)
        self.assertIn(str(self.source), result.stdout)
        self.assertIn('Dry run', result.stdout)
        self.assertEqual(result.stderr, '')
        self.assert_no_mutations()
        self.assertTrue(all(call['gh_repo'] is None for call in self.calls()))
        contents = [call['args'][1] for call in self.calls() if '/contents/' in call['args'][1]]
        self.assertEqual(len(contents), 2)
        self.assertTrue(all(path.endswith(f'?ref={SHA}') for path in contents))

    def test_both_registrations_must_be_merged_before_refresh(self):
        for filename in ('installer-apps.json', 'installer-signing-apps.json'):
            with self.subTest(filename=filename):
                result = self.command('setup', '--app', 'throw', overrides={'MISMATCH': filename})
                self.assertEqual(result.returncode, 1)
                self.assertIn('Merge this app', result.stderr)
                self.assert_no_mutations()

    def test_read_failure_preserves_status_without_raw_diagnostics(self):
        result = self.command('setup', '--app', 'throw', overrides={'FAIL_READ': 'true'})
        self.assertEqual(result.returncode, 43)
        self.assertIn('repository access', result.stderr)
        self.assertNotIn('sensitive', result.stderr)
        self.assert_no_mutations()

    def test_malformed_remote_registration_fails_closed(self):
        result = self.command('setup', '--app', 'throw', overrides={'MALFORMED': 'true'})
        self.assertEqual(result.returncode, 1)
        self.assertIn('invalid app registrations', result.stderr)
        self.assertNotIn('Traceback', result.stderr)
        self.assert_no_mutations()

    def test_refresh_failure_never_enables_distribution(self):
        result = self.command('setup', '--app', 'throw', overrides={'FAIL_REFRESH': 'true'})
        self.assertEqual(result.returncode, 42)
        self.assertIn('enable variable was not changed', result.stderr)
        self.assertFalse((self.root / 'enabled').exists())
        self.assertFalse(any(call['args'][0] == 'variable' for call in self.calls()))

    def test_main_change_after_refresh_prevents_enable(self):
        result = self.command('setup', '--app', 'throw', overrides={'CHANGE_AFTER_REFRESH': 'true'})
        self.assertEqual(result.returncode, 1)
        self.assertIn('Signing refreshed', result.stderr)
        self.assertIn('Merge this app', result.stderr)
        self.assertTrue((self.root / 'refreshed').exists())
        self.assertFalse((self.root / 'enabled').exists())

    def test_enable_failure_reports_partial_success(self):
        result = self.command('setup', '--app', 'throw', overrides={'FAIL_ENABLE': 'true'})
        self.assertEqual(result.returncode, 47)
        self.assertIn('Signing refreshed, but enabling distribution failed', result.stderr)
        self.assertNotIn('sensitive', result.stderr)
        self.assertTrue((self.root / 'refreshed').exists())
        self.assertFalse((self.root / 'enabled').exists())

    def test_success_refreshes_selected_source_then_enables_only_selected_app(self):
        for app in ('throw', 'where'):
            with self.subTest(app=app):
                result = self.command('setup', '--app', app, '--source', str(self.source))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, '')
                self.assertIn('setup does not publish or install', result.stdout)
                refreshed = json.loads((self.root / 'refreshed').read_text())
                self.assertIn(f'app:{app}', refreshed)
                self.assertIn(f'source:{self.source}', refreshed)
                enabled = json.loads((self.root / 'enabled').read_text())
                self.assertEqual(enabled, ['variable', 'set', f'{app.upper()}_DISTRIBUTION_ENABLED',
                                           '--body', 'true', '--repo', 'owner/repository'])
                calls = self.calls()
                self.assertEqual(calls[-1]['args'], enabled)
                refresh_index = next(index for index, call in enumerate(calls) if 'refresh' in call['args'])
                self.assertEqual(sum('/contents/' in call['args'][1] for call in calls[refresh_index + 1:]), 2)
                self.assertTrue(all(call['gemfile'] == str(self.root / 'Gemfile')
                                    for call in calls if call['tool'] == 'mise'))
                self.log.unlink()

    def test_policy_validates_product_before_external_processes(self):
        path = self.root / '.github/installer-signing-apps.json'
        value = json.loads(path.read_text())
        value['throw']['product'] = 'Where'
        path.write_text(json.dumps(value))
        with patch.dict(os.environ, {}, clear=True), self.assertRaisesRegex(ValueError, 'does not match'):
            setup(self.root, 'throw', self.source, False,
                  run=lambda *args, **kwargs: self.fail('Must validate before processes'))

    def test_policy_rejects_ci_before_external_processes(self):
        with patch.dict(os.environ, {'CIRCLECI': 'true'}, clear=True), self.assertRaisesRegex(SetupFailure, 'local only'):
            setup(self.root, 'throw', self.source, False,
                  run=lambda *args, **kwargs: self.fail('Must reject CI before processes'))
