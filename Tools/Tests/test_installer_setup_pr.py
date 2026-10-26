"""PR validation and real local Git checkout ownership without GitHub or signing."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock

from Tools.InstallerKit.installer_setup_pr import PullRequest, checkout, read_pull_request, recheck_pull_request, request_publication


REPOSITORY = 'owner/repository'
SHA = 'a' * 40


def metadata(**changes):
    return {'state': 'open', 'mergeable': True, 'labels': [{'name': 'installable'}],
            'head': {'sha': SHA, 'repo': {'full_name': REPOSITORY}},
            'base': {'repo': {'full_name': REPOSITORY}}, **changes}


class InstallerSetupPRTests(unittest.TestCase):
    def test_identity_eligibility_and_mergeability_are_required(self):
        for changes in ({'state': 'closed'}, {'mergeable': None}, {'mergeable': False},
                        {'head': {'repo': None}}, {'base': {'repo': {'full_name': 'other/repo'}}},
                        {'head': {'sha': 'main', 'repo': {'full_name': REPOSITORY}}}, {'labels': None}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                read_pull_request(REPOSITORY, 295, Mock(return_value=json.dumps(metadata(**changes))))
        for number in (0, -1, True, '295; command'):
            with self.subTest(number=number), self.assertRaises(ValueError):
                read_pull_request(REPOSITORY, number, Mock(side_effect=AssertionError('No command expected')))

    def test_recheck_preserves_label_removal_and_head_changes(self):
        pr = PullRequest(REPOSITORY, 295, SHA, True)
        for changes in ({'labels': []}, {'head': {'sha': 'b' * 40, 'repo': {'full_name': REPOSITORY}}}):
            command = Mock(return_value=json.dumps(metadata(**changes)))
            with self.subTest(changes=changes), self.assertRaisesRegex(ValueError, 'changed'):
                request_publication(pr, command)
            self.assertEqual(command.call_count, 1)  # Only the read; never label or dispatch.
        unlabelled = PullRequest(REPOSITORY, 295, SHA, False)
        self.assertTrue(recheck_pull_request(unlabelled, Mock(return_value=json.dumps(metadata()))).installable)

    def test_real_checkout_preserves_controller_and_cleans_up_on_failure(self):
        with tempfile.TemporaryDirectory(prefix='git source ü ') as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.run(['git', '-C', str(root), *args], check=True, capture_output=True, text=True).stdout.strip()
            git('init')
            (root / 'ide').write_text('fixture project entry point')
            (root / '.mise.toml').write_text('')
            git('add', 'ide', '.mise.toml')
            git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.test',
                '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '-m', 'Fixture')
            sha = git('rev-parse', 'HEAD')
            (root / 'user-untracked').write_text('preserve')
            pr = PullRequest(REPOSITORY, 295, sha, True)
            paths = []
            def command(args, cwd=None):
                if args[0] == 'mise':
                    return ''
                args = list(args)
                if 'fetch' in args:
                    args[-2] = str(root)  # Local transport for the same exact-SHA fetch.
                return subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()
            for fail in (False, True):
                try:
                    with checkout(root, pr, command) as source:
                        paths.append(source)
                        self.assertEqual((source / 'ide').read_text(), 'fixture project entry point')
                        self.assertFalse((source / 'user-untracked').exists())
                        if fail:
                            raise RuntimeError('simulated refresh failure')
                except RuntimeError:
                    self.assertTrue(fail)
                self.assertFalse(paths[-1].parent.exists())
                self.assertEqual(git('rev-parse', 'HEAD'), sha)
                self.assertEqual((root / 'user-untracked').read_text(), 'preserve')
