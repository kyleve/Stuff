from contextlib import redirect_stderr
from dataclasses import replace
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

from Tools.InstallerKit.circleci_archive import main, prepare
from Fixtures.circleci_distribution_fixtures import (
    archive_request,
    pull_request,
    write_archive,
)


class CircleCIArchiveTests(unittest.TestCase):
    def test_invalid_request_values_fail_before_processes(self):
        for change in (
            {"sha": "main"},
            {"repository": "../other"},
            {"app_id": "missing"},
            {"channel": "pr-1; touch /tmp/file"},
            {"run": "0"},
            {"attempt": "bad"},
            {"feed_url": "http://example.org/updates.json"},
        ):
            with self.subTest(change=change), self.assertRaises(ValueError):
                replace(archive_request(), **change)

    def test_checkout_uses_the_exact_current_commit_and_separate_arguments(self):
        request = archive_request()
        fetch = Mock(
            side_effect=[
                {"private": False, "full_name": request.repository},
                pull_request(),
            ]
        )
        run = Mock(
            return_value=subprocess.CompletedProcess([], 0, stdout=request.sha + "\n")
        )
        with tempfile.TemporaryDirectory(prefix="archive ü ") as temporary:
            source = Path(temporary) / "source with spaces"
            prepare(request, source, fetch, run)
            commands = [call.args[0] for call in run.call_args_list]
            self.assertEqual(
                commands[0][-2:], ["https://github.com/fixture/Stuff.git", str(source)]
            )
            self.assertEqual(commands[1][-2:], ["origin", request.sha])
            self.assertEqual(commands[2][-3:], ["checkout", "--detach", request.sha])
            self.assertIn("core.hooksPath=/dev/null", commands[2])

    def test_stale_unlabeled_forked_or_conflicted_requests_never_checkout_code(self):
        request = archive_request()
        original = pull_request()
        for value in (
            {**original, "labels": []},
            {**original, "state": "closed"},
            {**original, "mergeable": False},
            {
                **original,
                "head": {"sha": "b" * 40, "repo": {"full_name": request.repository}},
            },
            {
                **original,
                "head": {"sha": request.sha, "repo": {"full_name": "fork/Stuff"}},
            },
        ):
            with self.subTest(value=value), tempfile.TemporaryDirectory() as temporary:
                run = Mock()
                fetch = Mock(
                    side_effect=[
                        {"private": False, "full_name": request.repository},
                        value,
                    ]
                )
                with self.assertRaises(ValueError):
                    prepare(request, Path(temporary) / "source", fetch, run)
                run.assert_not_called()

    def test_wrong_or_private_repository_never_checks_out_code(self):
        for repository in (
            {"private": True, "full_name": "fixture/Stuff"},
            {"private": False, "full_name": "other/Stuff"},
        ):
            with (
                self.subTest(repository=repository),
                tempfile.TemporaryDirectory() as temporary,
            ):
                run = Mock()
                with self.assertRaises(ValueError):
                    prepare(
                        archive_request(),
                        Path(temporary) / "source",
                        Mock(return_value=repository),
                        run,
                    )
                run.assert_not_called()

    def test_wrong_checkout_revision_and_process_failure_remain_failures(self):
        for failure in (
            subprocess.CompletedProcess([], 0, stdout="b" * 40),
            subprocess.CalledProcessError(47, ["git", "clone"]),
        ):
            with (
                self.subTest(failure=failure),
                tempfile.TemporaryDirectory() as temporary,
            ):
                fetch = Mock(
                    side_effect=[
                        {"private": False, "full_name": "fixture/Stuff"},
                        pull_request(),
                    ]
                )
                run = (
                    Mock(side_effect=failure)
                    if isinstance(failure, Exception)
                    else Mock(return_value=failure)
                )
                with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                    prepare(archive_request(), Path(temporary) / "source", fetch, run)

    def test_archive_must_match_every_requested_identity_field(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "Where.ipa"
            write_archive(path)
            archive_request().validate_ipa(path)
            for key in (
                "InstallerAppID",
                "InstallerGitSHA",
                "InstallerRepositoryURL",
                "InstallerChannel",
                "InstallerRun",
                "InstallerAttempt",
                "InstallerFeedURL",
            ):
                with self.subTest(key=key):
                    write_archive(path, {key: "wrong"})
                    with self.assertRaisesRegex(ValueError, key):
                        archive_request().validate_ipa(path)

    def test_command_reports_missing_parameters_without_starting_processes(self):
        with (
            patch.dict("os.environ", {}, clear=True),
            redirect_stderr(io.StringIO()) as stderr,
            patch("Tools.InstallerKit.circleci_archive.prepare") as run,
        ):
            self.assertEqual(main(["prepare", "/unused"]), 1)
            self.assertIn("INSTALLER_REPOSITORY", stderr.getvalue())
            run.assert_not_called()

    def test_another_app_is_propagated_and_wrong_app_archive_is_rejected(self):
        request = replace(archive_request(), app_id="throw")
        self.assertEqual(request.parameters["installer_app"], "throw")
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            (output / "export").mkdir()
            source = output / "export/Throw.ipa"
            write_archive(source)
            from Tools.InstallerKit.circleci_archive import stage

            with self.assertRaises((KeyError, ValueError)):
                stage(request, output)
            self.assertFalse((output / "app.ipa").exists())

    def test_selected_product_is_validated_before_staging_and_never_overwritten(self):
        import plistlib
        import zipfile
        from Tools.InstallerKit.circleci_archive import stage

        request = replace(archive_request(), app_id="throw")
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            (output / "export").mkdir()
            source = output / "export/Throw.ipa"
            info = {
                "CFBundleIdentifier": "com.stuff.throw",
                "InstallerAppID": "throw",
                "InstallerGitSHA": request.sha,
                "InstallerGitStatus": "clean",
                "InstallerRepositoryURL": f"https://github.com/{request.repository}",
                "InstallerChannel": request.channel,
                "InstallerRun": request.run,
                "InstallerAttempt": request.attempt,
                "InstallerFeedURL": request.feed_url,
            }
            with zipfile.ZipFile(source, "w") as archive:
                archive.writestr("Payload/Throw.app/Info.plist", plistlib.dumps(info))
                for name in (
                    "embedded.mobileprovision",
                    "_CodeSignature/CodeResources",
                ):
                    archive.writestr(f"Payload/Throw.app/{name}", b"signed fixture")
            environment = dict(
                zip(
                    (
                        "INSTALLER_REPOSITORY",
                        "INSTALLER_APP_ID",
                        "INSTALLER_BUILD_SHA",
                        "INSTALLER_CHANNEL",
                        "INSTALLER_RUN",
                        "INSTALLER_ATTEMPT",
                        "INSTALLER_FEED_URL",
                    ),
                    (
                        request.repository,
                        request.app_id,
                        request.sha,
                        request.channel,
                        request.run,
                        request.attempt,
                        request.feed_url,
                    ),
                )
            )
            with (
                patch.dict("os.environ", environment, clear=True),
                redirect_stderr(io.StringIO()) as stderr,
            ):
                self.assertEqual(main(["stage", str(output)]), 0, stderr.getvalue())
                self.assertEqual(stderr.getvalue(), "")
            self.assertEqual((output / "app.ipa").read_bytes(), source.read_bytes())
            with self.assertRaises(FileExistsError):
                stage(request, output)
