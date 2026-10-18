from contextlib import redirect_stderr
from dataclasses import replace
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

from Tools.InstallerKit.circleci_archive import main, prepare
from Fixtures.circleci_distribution_fixtures import archive_request, pull_request, write_archive


class CircleCIArchiveTests(unittest.TestCase):
    def test_invalid_request_values_fail_before_processes(self):
        for change in ({"sha": "main"}, {"repository": "../other"}, {"app_id": "missing"},
                       {"channel": "pr-1; touch /tmp/file"}, {"run": "0"}, {"attempt": "bad"},
                       {"feed_url": "http://example.org/updates.json"}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                replace(archive_request(), **change)

    def test_checkout_uses_the_exact_current_commit_and_separate_arguments(self):
        request = archive_request()
        fetch = Mock(side_effect=[{"private": False, "full_name": request.repository}, pull_request()])
        run = Mock(return_value=subprocess.CompletedProcess([], 0, stdout=request.sha + "\n"))
        with tempfile.TemporaryDirectory(prefix="archive ü ") as temporary:
            source = Path(temporary) / "source with spaces"
            prepare(request, source, fetch, run)
            commands = [call.args[0] for call in run.call_args_list]
            self.assertEqual(commands[0][-2:], ["https://github.com/fixture/Stuff.git", str(source)])
            self.assertEqual(commands[1][-2:], ["origin", request.sha])
            self.assertEqual(commands[2][-3:], ["checkout", "--detach", request.sha])
            self.assertIn("core.hooksPath=/dev/null", commands[2])

    def test_stale_unlabeled_forked_or_conflicted_requests_never_checkout_code(self):
        request = archive_request()
        original = pull_request()
        for value in ({**original, "labels": []}, {**original, "state": "closed"},
                      {**original, "mergeable": False},
                      {**original, "head": {"sha": "b" * 40, "repo": {"full_name": request.repository}}},
                      {**original, "head": {"sha": request.sha, "repo": {"full_name": "fork/Stuff"}}}):
            with self.subTest(value=value), tempfile.TemporaryDirectory() as temporary:
                run = Mock()
                fetch = Mock(side_effect=[{"private": False, "full_name": request.repository}, value])
                with self.assertRaises(ValueError):
                    prepare(request, Path(temporary) / "source", fetch, run)
                run.assert_not_called()

    def test_wrong_or_private_repository_never_checks_out_code(self):
        for repository in ({"private": True, "full_name": "fixture/Stuff"},
                           {"private": False, "full_name": "other/Stuff"}):
            with self.subTest(repository=repository), tempfile.TemporaryDirectory() as temporary:
                run = Mock()
                with self.assertRaises(ValueError):
                    prepare(archive_request(), Path(temporary) / "source", Mock(return_value=repository), run)
                run.assert_not_called()

    def test_wrong_checkout_revision_and_process_failure_remain_failures(self):
        for failure in (subprocess.CompletedProcess([], 0, stdout="b" * 40),
                        subprocess.CalledProcessError(47, ["git", "clone"])):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                fetch = Mock(side_effect=[{"private": False, "full_name": "fixture/Stuff"}, pull_request()])
                run = Mock(side_effect=failure) if isinstance(failure, Exception) else Mock(return_value=failure)
                with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                    prepare(archive_request(), Path(temporary) / "source", fetch, run)

    def test_archive_must_match_every_requested_identity_field(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "Where.ipa"
            write_archive(path)
            archive_request().validate_ipa(path)
            for key in ("InstallerAppID", "InstallerGitSHA", "InstallerRepositoryURL", "InstallerChannel",
                        "InstallerRun", "InstallerAttempt", "InstallerFeedURL"):
                with self.subTest(key=key):
                    write_archive(path, {key: "wrong"})
                    with self.assertRaisesRegex(ValueError, key):
                        archive_request().validate_ipa(path)

    def test_command_reports_missing_parameters_without_starting_processes(self):
        with patch.dict("os.environ", {}, clear=True), redirect_stderr(io.StringIO()) as stderr, \
                patch("Tools.InstallerKit.circleci_archive.prepare") as run:
            self.assertEqual(main(["prepare", "/unused"]), 1)
            self.assertIn("INSTALLER_REPOSITORY", stderr.getvalue())
            run.assert_not_called()
