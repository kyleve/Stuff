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
                     'Tools/InstallerKit/installer_apps.py', 'Tools/InstallerKit/installer_setup_credentials.py',
                     'Tools/InstallerKit/installer_setup_pr.py', '.github/installer-apps.json',
                     '.github/installer-signing-apps.json'):
            destination = self.root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, destination)
        for module in (ROOT / 'Tools/InstallerKit').glob('*.py'):
            shutil.copy2(module, self.root / 'Tools/InstallerKit' / module.name)
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
        key = self.root / 'fixture-api-key.json'
        key.write_text(json.dumps({'key_id': 'test-key', 'issuer_id': 'test-issuer', 'key': 'test-private-key'}))
        self.env = {'INSTALLER_API_KEY_PATH': str(key), 'MATCH_PASSWORD': 'test-password',
                    'HOME': str(self.root), 'PATH': f'{self.bin}:/usr/bin:/bin', 'LOG': str(self.log),
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
elif args[:2] == ['workflow', 'run'] or args[:2] == ['pr', 'edit']:
    if os.environ.get('FAIL_PUBLICATION'):
        print('sensitive subprocess diagnostic', file=sys.stderr)
        sys.exit(49)
    (root / 'publication').write_text(json.dumps(args))
elif '/pulls/' in args[1]:
    sha = 'b' * 40
    if os.environ.get('CHANGE_PR_AFTER_REFRESH') and (root / 'refreshed').exists():
        sha = 'c' * 40
    if os.environ.get('CHANGE_PR_AFTER_CHECKOUT') and (root / 'checkout-created').exists():
        sha = 'c' * 40
    labels = [] if os.environ.get('UNLABELED') else [{'name': 'installable'}]
    value = {'state': 'closed' if os.environ.get('CLOSED') else 'open',
             'mergeable': False if os.environ.get('CONFLICT') else True,
             'head': {'sha': sha, 'repo': {'full_name': 'fork/repo' if os.environ.get('FORK') else 'owner/repository'}},
             'base': {'repo': {'full_name': 'owner/repository'}}, 'labels': labels}
    print(json.dumps(value))
elif '/git/trees/' in args[1]:
    print(json.dumps({'truncated': False, 'tree': [] if os.environ.get('NO_SOURCE') else [{'path': 'Throw', 'type': 'tree'}]}))
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
        self.write_executable('git', r'''
import json, os, pathlib, sys
root = pathlib.Path(os.environ['FIXTURE_ROOT'])
args = sys.argv[1:]
with open(os.environ['LOG'], 'a') as log:
    log.write(json.dumps({'tool': 'git', 'args': args}) + '\n')
if os.environ.get('FAIL_GIT'):
    sys.exit(46)
if args[0] == 'clone':
    source = pathlib.Path(args[-1])
    source.mkdir()
    (source / 'ide').touch()
    (root / 'checkout-created').write_text(str(source))
if 'rev-parse' in args:
    print(('c' if os.environ.get('WRONG_SHA') else 'b') * 40)
''')
        self.write_executable('mise', r'''
import json, os, pathlib, sys
args = sys.argv[1:]
root = pathlib.Path(os.environ['FIXTURE_ROOT'])
with open(os.environ['LOG'], 'a') as log:
    log.write(json.dumps({'tool': 'mise', 'args': args, 'gemfile': os.environ.get('BUNDLE_GEMFILE')}) + '\n')
if args == ['install'] and os.environ.get('FAIL_INSTALL'):
    sys.exit(45)
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
                 ('refresh', '--app', 'throw', '--dry-run'),
                 ('setup', '--app', 'throw', '--pr', '0'),
                 ('setup', '--app', 'throw', '--pr', '295', '--source', str(self.source)),
                 ('refresh', '--app', 'throw', '--pr', '295')]
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

    def test_pr_dry_run_needs_no_credentials_and_only_reads(self):
        result = self.command('setup', '--app', 'throw', '--pr', '295', '--dry-run',
                              overrides={'MATCH_PASSWORD': '', 'INSTALLER_API_KEY_PATH': '/missing'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('PR #295', result.stdout)
        self.assertIn('all enabled apps', result.stdout)
        self.assert_no_mutations()
        self.assertFalse((self.root / 'checkout-created').exists())

    def test_ineligible_prs_never_prepare_or_enable(self):
        for flag in ('FORK', 'CLOSED', 'CONFLICT', 'NO_SOURCE'):
            with self.subTest(flag=flag):
                result = self.command('setup', '--app', 'throw', '--pr', '295', overrides={flag: 'true'})
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assert_no_mutations()
                self.assertFalse((self.root / 'checkout-created').exists())

    def test_pr_success_cleans_checkout_and_dispatches_without_removing_label(self):
        result = self.command('setup', '--app', 'throw', '--pr', '295')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Requested PR #295 publication', result.stdout)
        source = Path((self.root / 'checkout-created').read_text())
        self.assertFalse(source.parent.exists())
        refreshed = json.loads((self.root / 'refreshed').read_text())
        self.assertIn(f'source:{source}', refreshed)
        publication = json.loads((self.root / 'publication').read_text())
        self.assertEqual(publication, ['workflow', 'run', 'installer-distribution.yml', '--repo',
                                      'owner/repository', '--ref', 'main', '-f', 'pull_request=295'])
        self.assertFalse(any('--remove-label' in call['args'] for call in self.calls()))
        self.assertNotIn('test-password', result.stdout + result.stderr + self.log.read_text())

    def test_unlabeled_pr_gets_one_label_event_and_no_dispatch(self):
        result = self.command('setup', '--app', 'throw', '--pr', '295', overrides={'UNLABELED': 'true'})
        self.assertEqual(result.returncode, 0, result.stderr)
        publication = json.loads((self.root / 'publication').read_text())
        self.assertEqual(publication, ['pr', 'edit', '295', '--repo', 'owner/repository', '--add-label', 'installable'])

    def test_pr_preparation_failures_clean_up_without_enabling(self):
        for flag, status in (('FAIL_GIT', 46), ('WRONG_SHA', 1), ('FAIL_INSTALL', 45),
                             ('CHANGE_PR_AFTER_CHECKOUT', 1), ('FAIL_REFRESH', 42)):
            with self.subTest(flag=flag):
                result = self.command('setup', '--app', 'throw', '--pr', '295', overrides={flag: 'true'})
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertFalse((self.root / 'enabled').exists())
                self.assertFalse((self.root / 'publication').exists())
                marker = self.root / 'checkout-created'
                if marker.exists():
                    self.assertFalse(Path(marker.read_text()).parent.exists())
                    marker.unlink()

    def test_changed_pr_after_refresh_never_enables_or_dispatches(self):
        result = self.command('setup', '--app', 'throw', '--pr', '295', overrides={'CHANGE_PR_AFTER_REFRESH': 'true'})
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('enable variable was not changed', result.stderr)
        self.assertTrue((self.root / 'refreshed').exists())
        self.assertFalse((self.root / 'enabled').exists())
        self.assertFalse((self.root / 'publication').exists())

    def test_dispatch_failure_reports_enablement_and_preserves_status(self):
        result = self.command('setup', '--app', 'throw', '--pr', '295', overrides={'FAIL_PUBLICATION': 'true'})
        self.assertEqual(result.returncode, 49, result.stderr)
        self.assertIn('distribution is enabled, but publication was not confirmed', result.stderr)
        self.assertTrue((self.root / 'enabled').exists())
        self.assertNotIn('sensitive', result.stderr)
        self.assertFalse(Path((self.root / 'checkout-created').read_text()).parent.exists())

    def test_missing_noninteractive_password_stops_before_mutations(self):
        result = self.command('setup', '--app', 'throw', '--pr', '295', overrides={'MATCH_PASSWORD': ''})
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('hidden prompt', result.stderr)
        self.assert_no_mutations()
        self.assertFalse((self.root / 'checkout-created').exists())
