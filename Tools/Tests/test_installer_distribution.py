from contextlib import redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from Tools.InstallerKit.installer_apps import load_app
from Tools.InstallerKit.installer_distribution import (
    Publication,
    Retirement,
    finish as finish_distribution,
    is_current,
    main,
    select_plan,
    validate_ipa,
)
from Fixtures.where_distribution_fixtures import SHA, write_ipa


APP = load_app("where")
REPO = "fixture/Stuff"
FEED_URL = "https://fixture.github.io/Stuff/updates.json"
IPA_URL = "https://github.com/fixture/Stuff/releases/download/installer-where-pr-42-2-1/app.ipa"


def finish(plan, repository, ipa, fetch, service):
    return finish_distribution(
        plan, repository, ipa, fetch, service, {"run": 2, "attempt": 1}, FEED_URL, APP
    )


def pr_event(
    action="synchronize", labeled=True, state="open", fork=False, mergeable=True
):
    return {
        "repository": {"full_name": REPO},
        "number": 42,
        "action": action,
        "label": {"name": "installable"},
        "pull_request": {
            "state": state,
            "mergeable": mergeable,
            "labels": [{"name": "installable"}] if labeled else [],
            "head": {
                "sha": SHA,
                "repo": {"full_name": "other/Stuff" if fork else REPO},
            },
            "base": {"ref": "stack-parent", "repo": {"full_name": REPO}},
        },
    }


def plan(event):
    return select_plan("pull_request_target", event, REPO, "refs/heads/main", "b" * 40)


class InstallerDistributionTests(unittest.TestCase):
    def test_main_and_manual_main_publish_only_exact_branch_revision(self):
        event = {"repository": {"full_name": REPO}, "after": SHA}
        for kind in ("push", "workflow_dispatch"):
            self.assertEqual(
                select_plan(kind, event, REPO, "refs/heads/main", SHA),
                Publication(SHA, None),
            )
            self.assertIsNone(select_plan(kind, event, REPO, "refs/heads/feature", SHA))
        self.assertIsNone(
            select_plan(
                "push", {**event, "deleted": True}, REPO, "refs/heads/main", SHA
            )
        )

    def test_opted_in_prs_use_head_not_controller_sha_including_stacked_prs(self):
        for action in ("opened", "reopened", "synchronize", "labeled"):
            with self.subTest(action=action):
                self.assertEqual(plan(pr_event(action)), Publication(SHA, 42))
        for event in (pr_event(fork=True), pr_event("edited")):
            self.assertIsNone(plan(event))
        self.assertIsNone(
            select_plan(
                "pull_request", pr_event(), REPO, "refs/pull/42/merge", "b" * 40
            )
        )

    def test_unrelated_label_event_preserves_displaced_pending_channel_update(self):
        event = pr_event("labeled")
        event["label"]["name"] = "unrelated"
        self.assertEqual(plan(event), Publication(SHA, 42))
        event["pull_request"]["labels"] = [{"name": "unrelated"}]
        self.assertEqual(plan(event), Retirement(42))

    def test_label_removal_and_close_retire_pages(self):
        self.assertEqual(plan(pr_event("unlabeled", labeled=False)), Retirement(42))
        self.assertEqual(plan(pr_event("closed", state="closed")), Retirement(42))
        self.assertEqual(plan(pr_event(labeled=False)), Retirement(42))

    def test_late_publish_and_retirement_are_rechecked_against_live_state(self):
        publication = Publication(SHA, 42)
        current = pr_event()["pull_request"]
        self.assertTrue(is_current(publication, REPO, lambda _: current))
        for live in (
            pr_event(labeled=False)["pull_request"],
            pr_event(state="closed")["pull_request"],
            {**current, "head": {**current["head"], "sha": "c" * 40}},
        ):
            self.assertFalse(is_current(publication, REPO, lambda _: live))
        self.assertFalse(is_current(Retirement(42), REPO, lambda _: current))
        self.assertFalse(
            is_current(
                Publication(SHA, None), REPO, lambda _: {"object": {"sha": "c" * 40}}
            )
        )

    def test_pending_mergeability_resolves_without_requiring_other_checks_to_pass(self):
        pending = pr_event(mergeable=None)["pull_request"]
        ready = {**pr_event()["pull_request"], "mergeable_state": "blocked"}
        fetch = Mock(side_effect=[pending, ready])
        with patch("Tools.InstallerKit.installer_distribution.time.sleep") as sleep:
            self.assertTrue(is_current(Publication(SHA, 42), REPO, fetch))
        self.assertEqual(fetch.call_count, 2)
        sleep.assert_called_once()

    def test_mergeability_wait_rechecks_changed_head_label_state_and_repository(self):
        current = pr_event()["pull_request"]
        pending = {**current, "mergeable": None}
        for live in (
            pr_event(labeled=False)["pull_request"],
            pr_event(state="closed")["pull_request"],
            pr_event(fork=True)["pull_request"],
            {**current, "head": {**current["head"], "sha": "c" * 40}},
        ):
            with (
                self.subTest(live=live),
                patch("Tools.InstallerKit.installer_distribution.time.sleep"),
            ):
                fetch = Mock(side_effect=[pending, live])
                self.assertFalse(is_current(Publication(SHA, 42), REPO, fetch))
                self.assertEqual(fetch.call_count, 2)

    def test_pending_mergeability_can_resolve_to_a_conflict(self):
        fetch = Mock(
            side_effect=[
                pr_event(mergeable=None)["pull_request"],
                pr_event(mergeable=False)["pull_request"],
            ]
        )
        with (
            patch("Tools.InstallerKit.installer_distribution.time.sleep"),
            self.assertRaisesRegex(ValueError, "has merge conflicts"),
        ):
            is_current(Publication(SHA, 42), REPO, fetch)

    def test_retirement_ignores_conflicts_and_pending_mergeability(self):
        for mergeable in (False, None):
            for event in (
                pr_event("unlabeled", labeled=False, mergeable=mergeable),
                pr_event("closed", state="closed", mergeable=mergeable),
            ):
                with (
                    self.subTest(event=event),
                    patch(
                        "Tools.InstallerKit.installer_distribution.time.sleep"
                    ) as sleep,
                ):
                    service = Mock()
                    self.assertIn(
                        "retirement",
                        finish(
                            plan(event),
                            REPO,
                            None,
                            lambda _: event["pull_request"],
                            service,
                        ).summary,
                    )
                    self.assertEqual(service.method_calls, [])
                    service.publish.assert_not_called()
                    sleep.assert_not_called()

    def test_publishing_requires_clean_optimized_development_identity_and_matching_commit(
        self,
    ):
        with tempfile.TemporaryDirectory() as temporary:
            ipa = Path(temporary) / "Where.ipa"
            write_ipa(ipa)
            validate_ipa(ipa, Publication(SHA, 42), APP)
            for changes in (
                {"CFBundleIdentifier": "com.stuff.where"},
                {"WhereAudience": "beta"},
                {"InstallerGitStatus": "dirty"},
                {"WhereSwiftOptimizationLevel": "-Onone"},
                {"WhereConfiguration": "Release"},
                {"InstallerGitSHA": "b" * 40},
            ):
                with self.subTest(changes=changes):
                    write_ipa(ipa, changes)
                    with self.assertRaises(ValueError):
                        validate_ipa(ipa, Publication(SHA, 42), APP)
            write_ipa(
                ipa,
                omit="Payload/Where.app/PlugIns/WhereWidgets.appex/embedded.mobileprovision",
            )
            with self.assertRaises(KeyError):
                validate_ipa(ipa, Publication(SHA, 42), APP)

    def test_finish_mutates_only_current_channels_and_records_install_link(self):
        with tempfile.TemporaryDirectory() as temporary:
            ipa = Path(temporary) / "Where.ipa"
            write_ipa(ipa)
            service = Mock()
            service.publish.return_value = IPA_URL
            current = Mock(return_value=pr_event()["pull_request"])
            summary = finish(Publication(SHA, 42), REPO, ipa, current, service).summary
            self.assertIn("[pr-42: install Where Dev]", summary)
            self.assertIn(SHA, summary)
            service.publish.assert_called_once()
            service.reset_mock()
            current.return_value = pr_event(labeled=False)["pull_request"]
            self.assertIn(
                "Skipped",
                finish(Publication(SHA, 42), REPO, ipa, current, service).summary,
            )
            service.publish.assert_not_called()
            finish(Retirement(42), REPO, None, current, service)
            self.assertEqual(service.method_calls, [])
            service.reset_mock()
            current.return_value = pr_event()["pull_request"]
            self.assertIn(
                "Skipped", finish(Retirement(42), REPO, None, current, service).summary
            )
            self.assertEqual(service.method_calls, [])

    def test_conflict_that_develops_during_archive_blocks_publication(self):
        with tempfile.TemporaryDirectory() as temporary:
            ipa = Path(temporary) / "Where.ipa"
            write_ipa(ipa)
            service = Mock()
            with self.assertRaisesRegex(ValueError, "has merge conflicts"):
                finish(
                    Publication(SHA, 42),
                    REPO,
                    ipa,
                    lambda _: pr_event(mergeable=False)["pull_request"],
                    service,
                )
            service.publish.assert_not_called()
            self.assertEqual(service.method_calls, [])

    def test_cli_writes_action_outputs_and_fails_closed_on_api_errors(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            event_path = root / "event.json"
            output = root / "output"
            event_path.write_text(json.dumps(pr_event()))
            arguments = [
                "plan",
                "--app",
                "where",
                "--event",
                str(event_path),
                "--event-name",
                "pull_request_target",
                "--repository",
                REPO,
                "--ref",
                "refs/heads/main",
                "--sha",
                "b" * 40,
                "--output",
                str(output),
            ]
            with (
                patch(
                    "Tools.InstallerKit.installer_distribution.github_fetch",
                    return_value=pr_event()["pull_request"],
                ),
                redirect_stdout(io.StringIO()),
            ):
                self.assertEqual(main(arguments), 0)
            self.assertEqual(
                output.read_text(), f"action=publish\nsha={SHA}\nchannel=pr-42\n"
            )
            output.unlink()
            with (
                patch(
                    "Tools.InstallerKit.installer_distribution.github_fetch",
                    side_effect=ValueError("HTTP 403"),
                ),
                redirect_stderr(io.StringIO()) as stderr,
            ):
                self.assertEqual(main(arguments), 1)
            self.assertIn("HTTP 403", stderr.getvalue())
            self.assertFalse(output.exists())

    def test_cli_fails_without_build_outputs_for_conflicting_or_unresolved_prs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            event_path = root / "event.json"
            output = root / "output"
            event_path.write_text(json.dumps(pr_event()))
            arguments = [
                "plan",
                "--app",
                "where",
                "--event",
                str(event_path),
                "--event-name",
                "pull_request_target",
                "--repository",
                REPO,
                "--ref",
                "refs/heads/main",
                "--sha",
                "b" * 40,
                "--output",
                str(output),
            ]
            for mergeable, message in (
                (False, "PR #42 has merge conflicts"),
                (None, "Rerun this workflow"),
                ("true", "invalid mergeability status"),
            ):
                with (
                    self.subTest(mergeable=mergeable),
                    patch(
                        "Tools.InstallerKit.installer_distribution.github_fetch",
                        return_value=pr_event(mergeable=mergeable)["pull_request"],
                    ) as fetch,
                    patch(
                        "Tools.InstallerKit.installer_distribution.time.sleep"
                    ) as sleep,
                    redirect_stdout(io.StringIO()) as stdout,
                    redirect_stderr(io.StringIO()) as stderr,
                ):
                    self.assertEqual(main(arguments), 1)
                    self.assertEqual(stdout.getvalue(), "")
                    self.assertIn(message, stderr.getvalue())
                    self.assertFalse(output.exists())
                    self.assertLessEqual(fetch.call_count, 5)
                    self.assertLessEqual(
                        sum(call.args[0] for call in sleep.call_args_list), 30
                    )

    def test_cli_retires_conflicting_pr_pages_without_an_archive(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            event_path = root / "event.json"
            output = root / "output"
            arguments = [
                "--app",
                "where",
                "--event",
                str(event_path),
                "--event-name",
                "pull_request_target",
                "--repository",
                REPO,
                "--ref",
                "refs/heads/main",
                "--sha",
                "b" * 40,
                "--output",
                str(output),
            ]
            for event in (
                pr_event("unlabeled", labeled=False, mergeable=False),
                pr_event("closed", state="closed", mergeable=None),
            ):
                event_path.write_text(json.dumps(event))
                with (
                    self.subTest(event=event),
                    patch(
                        "Tools.InstallerKit.installer_distribution.github_fetch",
                        return_value=event["pull_request"],
                    ),
                    patch(
                        "Tools.InstallerKit.installer_distribution.GitHubReleases"
                    ) as service,
                    redirect_stdout(io.StringIO()) as stdout,
                    redirect_stderr(io.StringIO()) as stderr,
                ):
                    self.assertEqual(main(["plan"] + arguments), 0)
                    self.assertEqual(
                        output.read_text(), "action=retire\nsha=\nchannel=pr-42\n"
                    )
                    output.unlink()
                    self.assertEqual(
                        main(["finish", "--source-sha", ""] + arguments), 0
                    )
                    self.assertIn("Selected pr-42 for retirement", stdout.getvalue())
                    self.assertIn("Selected pr-42 for retirement", output.read_text())
                    self.assertEqual(stderr.getvalue(), "")
                    service.assert_not_called()
                    output.unlink()

    def test_cli_receipt_requires_successful_upload_and_matching_build_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            event = root / "event.json"
            event.write_text(json.dumps(pr_event()))
            ipa, receipt = root / "Where.ipa", root / "receipt.json"
            feed_url = "https://fixture.github.io/Stuff/updates.json"
            metadata = {
                "InstallerAppID": "where",
                "InstallerRepositoryURL": "https://github.com/fixture/Stuff",
                "InstallerChannel": "pr-42",
                "InstallerRun": "2",
                "InstallerAttempt": "1",
                "InstallerGitSHA": SHA,
                "InstallerFeedURL": feed_url,
            }
            args = [
                "finish",
                "--app",
                "where",
                "--event",
                str(event),
                "--event-name",
                "pull_request_target",
                "--repository",
                REPO,
                "--ref",
                "refs/heads/main",
                "--sha",
                "b" * 40,
                "--ipa",
                str(ipa),
                "--receipt",
                str(receipt),
                "--run",
                "2",
                "--attempt",
                "1",
                "--feed-url",
                feed_url,
            ]
            with (
                patch(
                    "Tools.InstallerKit.installer_distribution.GitHubReleases"
                ) as service,
                patch(
                    "Tools.InstallerKit.installer_distribution.github_fetch",
                    return_value=pr_event()["pull_request"],
                ),
                patch(
                    "Tools.InstallerKit.installer_update_feed.GitHubUpdateFeed"
                ) as feed,
                redirect_stdout(io.StringIO()),
                redirect_stderr(io.StringIO()),
            ):
                feed.return_value.load.return_value = (
                    {"schemaVersion": 3, "apps": []},
                    None,
                )
                write_ipa(ipa, {**metadata, "InstallerChannel": "main"})
                self.assertEqual(main(args), 1)
                service.assert_not_called()
                write_ipa(ipa, metadata)
                service.return_value.publish.side_effect = ValueError("upload rejected")
                self.assertEqual(main(args), 1)
                self.assertFalse(receipt.exists())
                service.return_value.publish.side_effect = None
                service.return_value.publish.return_value = IPA_URL
                self.assertEqual(main(args), 0)
                self.assertEqual(json.loads(receipt.read_text())["run"], "2")
                self.assertEqual(
                    json.loads(receipt.read_text())["buildDetails"],
                    {
                        "version": "0.9.2",
                        "minimumOSVersion": "27.0",
                        "sizeBytes": ipa.stat().st_size,
                    },
                )
                receipt.unlink()
                for key in ("CFBundleShortVersionString", "MinimumOSVersion"):
                    write_ipa(ipa, {**metadata, key: "invalid"})
                    service.reset_mock()
                    with (
                        self.subTest(key=key),
                        redirect_stdout(io.StringIO()) as stdout,
                        redirect_stderr(io.StringIO()) as stderr,
                    ):
                        self.assertEqual(main(args), 1)
                    self.assertEqual(stdout.getvalue(), "")
                    self.assertIn("Build details", stderr.getvalue())
                    self.assertFalse(receipt.exists())
                    service.return_value.publish.assert_not_called()
                write_ipa(ipa, metadata)
                service.reset_mock()
                feed.return_value.load.return_value = (
                    {
                        "apps": [
                            {
                                "id": "where",
                                "channels": [
                                    {
                                        "name": "pr-42",
                                        "releases": [{"id": {"run": 3, "attempt": 1}}],
                                    }
                                ],
                            }
                        ]
                    },
                    "revision",
                )
                self.assertEqual(main(args), 0)
                self.assertFalse(receipt.exists())
                service.assert_not_called()

    def test_missing_app_source_skips_build_but_never_suppresses_retirement(self):
        from Tools.InstallerKit.installer_apps import load_app
        from Tools.InstallerKit.installer_distribution import (
            source_available,
            Retirement,
        )

        app = load_app("throw")
        fetch = Mock(
            return_value={
                "truncated": False,
                "tree": [{"path": "Where", "type": "tree"}],
            }
        )
        self.assertFalse(source_available(app, Publication(SHA, 42), REPO, fetch))
        fetch.return_value["tree"].append({"path": "Throw", "type": "tree"})
        self.assertTrue(source_available(app, Publication(SHA, 42), REPO, fetch))
        fetch.reset_mock()
        self.assertTrue(source_available(app, Retirement(42), REPO, fetch))
        fetch.assert_not_called()
        fetch.return_value = {"truncated": True, "tree": []}
        with self.assertRaises(ValueError):
            source_available(app, Publication(SHA, 42), REPO, fetch)

    def test_cli_skips_absent_app_before_emitting_archive_work(self):
        with tempfile.TemporaryDirectory() as temporary:
            event = Path(temporary) / "event.json"
            event.write_text(json.dumps(pr_event()))
            output = Path(temporary) / "output"
            with (
                patch(
                    "Tools.InstallerKit.installer_distribution.github_fetch",
                    side_effect=[
                        pr_event()["pull_request"],
                        {"truncated": False, "tree": []},
                    ],
                ),
                redirect_stdout(io.StringIO()) as stdout,
                redirect_stderr(io.StringIO()) as stderr,
            ):
                result = main(
                    [
                        "plan",
                        "--app",
                        "throw",
                        "--event",
                        str(event),
                        "--event-name",
                        "pull_request_target",
                        "--repository",
                        REPO,
                        "--ref",
                        "refs/heads/main",
                        "--sha",
                        "b" * 40,
                        "--output",
                        str(output),
                    ]
                )
            self.assertEqual(result, 0)
            self.assertEqual(output.read_text(), "action=skip\nsha=\nchannel=\n")
            self.assertEqual(stdout.getvalue(), output.read_text())
            self.assertIn("Skipping throw", stderr.getvalue())

    def test_manual_pr_dispatch_uses_live_head_and_keeps_opt_in(self):
        from Tools.InstallerKit.installer_distribution import event_plan

        event = {"repository": {"full_name": REPO}, "inputs": {"pull_request": "42"}}
        fetch = Mock(return_value=pr_event()["pull_request"])
        self.assertEqual(
            event_plan(
                "workflow_dispatch", event, REPO, "refs/heads/main", "b" * 40, fetch
            ),
            Publication(SHA, 42),
        )
        fetch.assert_called_once_with(f"repos/{REPO}/pulls/42")
        for pr in (
            pr_event(labeled=False),
            pr_event(fork=True),
            pr_event(state="closed"),
        ):
            with (
                self.subTest(pr=pr),
                self.assertRaisesRegex(ValueError, "labeled installable"),
            ):
                event_plan(
                    "workflow_dispatch",
                    event,
                    REPO,
                    "refs/heads/main",
                    "b" * 40,
                    Mock(return_value=pr["pull_request"]),
                )

    def test_manual_pr_dispatch_rejects_invalid_numbers_and_untrusted_refs(self):
        from Tools.InstallerKit.installer_distribution import event_plan

        for number in ("0", "-1", "01", "1/../../", 0, 42, True, False, None, "42\n"):
            event = {
                "repository": {"full_name": REPO},
                "inputs": {"pull_request": number},
            }
            with self.subTest(number=number), self.assertRaises(ValueError):
                event_plan(
                    "workflow_dispatch",
                    event,
                    REPO,
                    "refs/heads/main",
                    SHA,
                    Mock(side_effect=AssertionError("No API request expected")),
                )
        event = {"repository": {"full_name": REPO}, "inputs": {"pull_request": "42"}}
        fetch = Mock(side_effect=AssertionError("No API request expected"))
        self.assertIsNone(
            event_plan(
                "workflow_dispatch", event, REPO, "refs/heads/feature", SHA, fetch
            )
        )
        event["repository"]["full_name"] = "other/Stuff"
        self.assertIsNone(
            event_plan("workflow_dispatch", event, REPO, "refs/heads/main", SHA, fetch)
        )

    def test_manual_dispatch_without_pr_retains_main_behavior(self):
        from Tools.InstallerKit.installer_distribution import event_plan

        fetch = Mock(side_effect=AssertionError("No PR lookup expected"))
        for inputs in ({}, {"pull_request": ""}):
            event = {"repository": {"full_name": REPO}, "inputs": inputs}
            self.assertEqual(
                event_plan(
                    "workflow_dispatch", event, REPO, "refs/heads/main", SHA, fetch
                ),
                Publication(SHA, None),
            )

    def test_manual_pr_dispatch_command_emits_pr_channel_instead_of_main(self):
        with tempfile.TemporaryDirectory() as temporary:
            event = Path(temporary) / "event.json"
            event.write_text(
                json.dumps(
                    {
                        "repository": {"full_name": REPO},
                        "inputs": {"pull_request": "42"},
                    }
                )
            )
            with (
                patch(
                    "Tools.InstallerKit.installer_distribution.github_fetch",
                    return_value=pr_event()["pull_request"],
                ),
                redirect_stdout(io.StringIO()) as stdout,
                redirect_stderr(io.StringIO()) as stderr,
            ):
                result = main(
                    [
                        "plan",
                        "--app",
                        "where",
                        "--event",
                        str(event),
                        "--event-name",
                        "workflow_dispatch",
                        "--repository",
                        REPO,
                        "--ref",
                        "refs/heads/main",
                        "--sha",
                        "b" * 40,
                    ]
                )
                self.assertEqual(result, 0, stderr.getvalue())
                self.assertIn(
                    f"action=publish\nsha={SHA}\nchannel=pr-42\n", stdout.getvalue()
                )

    def test_manual_pr_plan_to_completion_keeps_archive_identity_when_live_state_changes(
        self,
    ):
        current = pr_event()["pull_request"]
        advanced = {**current, "head": {**current["head"], "sha": "c" * 40}}
        cases = [
            ("unchanged", current),
            ("advanced", advanced),
            ("unlabeled", pr_event(labeled=False)["pull_request"]),
            ("closed", pr_event(state="closed")["pull_request"]),
            ("fork", pr_event(fork=True)["pull_request"]),
        ]
        for name, live in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                event, ipa, receipt = (
                    root / "event.json",
                    root / "app.ipa",
                    root / "receipt.json",
                )
                event.write_text(
                    json.dumps(
                        {
                            "repository": {"full_name": REPO},
                            "inputs": {"pull_request": "42"},
                        }
                    )
                )
                common = [
                    "--app",
                    "where",
                    "--event",
                    str(event),
                    "--event-name",
                    "workflow_dispatch",
                    "--repository",
                    REPO,
                    "--ref",
                    "refs/heads/main",
                    "--sha",
                    "b" * 40,
                ]
                with (
                    patch(
                        "Tools.InstallerKit.installer_distribution.github_fetch",
                        return_value=current,
                    ),
                    redirect_stdout(io.StringIO()) as planned,
                ):
                    self.assertEqual(main(["plan"] + common), 0)
                outputs = dict(
                    line.split("=", 1) for line in planned.getvalue().splitlines()
                )
                write_ipa(
                    ipa,
                    {
                        "InstallerRepositoryURL": f"https://github.com/{REPO}",
                        "InstallerChannel": outputs["channel"],
                        "InstallerGitSHA": outputs["sha"],
                        "InstallerRun": "2",
                        "InstallerAttempt": "1",
                        "InstallerFeedURL": FEED_URL,
                    },
                )
                args = [
                    "finish",
                    *common,
                    "--source-sha",
                    outputs["sha"],
                    "--ipa",
                    str(ipa),
                    "--receipt",
                    str(receipt),
                    "--run",
                    "2",
                    "--attempt",
                    "1",
                    "--feed-url",
                    FEED_URL,
                ]
                with (
                    patch(
                        "Tools.InstallerKit.installer_distribution.github_fetch",
                        return_value=live,
                    ),
                    patch(
                        "Tools.InstallerKit.installer_update_feed.GitHubUpdateFeed"
                    ) as feed,
                    patch(
                        "Tools.InstallerKit.installer_distribution.GitHubReleases"
                    ) as service,
                    redirect_stdout(io.StringIO()) as stdout,
                    redirect_stderr(io.StringIO()) as stderr,
                ):
                    feed.return_value.load.return_value = (
                        {"schemaVersion": 3, "apps": []},
                        None,
                    )
                    service.return_value.publish.return_value = IPA_URL
                    self.assertEqual(main(args), 0, stderr.getvalue())
                    self.assertEqual(stderr.getvalue(), "")
                    if name == "unchanged":
                        service.return_value.publish.assert_called_once()
                        result = json.loads(receipt.read_text())
                        self.assertEqual(
                            (result["sha"], result["channel"]), (SHA, "pr-42")
                        )
                    else:
                        service.return_value.publish.assert_not_called()
                        self.assertIn(
                            "Skipped: the branch, label, or pull request state changed.",
                            stdout.getvalue(),
                        )
                        self.assertFalse(receipt.exists())

    def test_manual_pr_completion_requires_planned_sha_and_rejects_wrong_ipa(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            event, ipa, receipt = (
                root / "event.json",
                root / "app.ipa",
                root / "receipt.json",
            )
            event.write_text(
                json.dumps(
                    {
                        "repository": {"full_name": REPO},
                        "inputs": {"pull_request": "42"},
                    }
                )
            )
            write_ipa(
                ipa,
                {
                    "InstallerRepositoryURL": f"https://github.com/{REPO}",
                    "InstallerChannel": "pr-42",
                    "InstallerGitSHA": "c" * 40,
                    "InstallerRun": "2",
                    "InstallerAttempt": "1",
                    "InstallerFeedURL": FEED_URL,
                },
            )
            args = [
                "finish",
                "--app",
                "where",
                "--event",
                str(event),
                "--event-name",
                "workflow_dispatch",
                "--repository",
                REPO,
                "--ref",
                "refs/heads/main",
                "--sha",
                "b" * 40,
                "--ipa",
                str(ipa),
                "--receipt",
                str(receipt),
                "--run",
                "2",
                "--attempt",
                "1",
                "--feed-url",
                FEED_URL,
            ]
            for source in (
                [],
                ["--source-sha", ""],
                ["--source-sha", "main"],
                ["--source-sha", SHA],
            ):
                with (
                    self.subTest(source=source),
                    patch(
                        "Tools.InstallerKit.installer_distribution.github_fetch"
                    ) as fetch,
                    patch(
                        "Tools.InstallerKit.installer_update_feed.GitHubUpdateFeed"
                    ) as feed,
                    patch(
                        "Tools.InstallerKit.installer_distribution.GitHubReleases"
                    ) as service,
                    redirect_stdout(io.StringIO()) as stdout,
                    redirect_stderr(io.StringIO()) as stderr,
                ):
                    self.assertEqual(main(args + source), 1)
                    self.assertIn(
                        "InstallerGitSHA"
                        if source == ["--source-sha", SHA]
                        else "--source-sha",
                        stderr.getvalue(),
                    )
                    self.assertEqual(stdout.getvalue(), "")
                    self.assertFalse(receipt.exists())
                    fetch.assert_not_called()
                    feed.assert_not_called()
                    service.assert_not_called()

    def test_completion_plan_keeps_event_identity_and_trusted_controller_gate(self):
        from Tools.InstallerKit.installer_distribution import completion_plan

        main_event = {"repository": {"full_name": REPO}, "after": SHA}
        for kind in ("push", "workflow_dispatch"):
            with self.subTest(kind=kind):
                self.assertEqual(
                    completion_plan(
                        kind, main_event, REPO, "refs/heads/main", SHA, SHA
                    ),
                    Publication(SHA, None),
                )
                with self.assertRaisesRegex(ValueError, "does not match the event"):
                    completion_plan(
                        kind, main_event, REPO, "refs/heads/main", SHA, "b" * 40
                    )
        event = {"repository": {"full_name": REPO}, "inputs": {"pull_request": "42"}}
        self.assertIsNone(
            completion_plan(
                "workflow_dispatch", event, REPO, "refs/heads/feature", SHA, SHA
            )
        )
        event["repository"]["full_name"] = "other/Stuff"
        self.assertIsNone(
            completion_plan(
                "workflow_dispatch", event, REPO, "refs/heads/main", SHA, SHA
            )
        )
