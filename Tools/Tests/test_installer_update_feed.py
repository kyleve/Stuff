import base64
from dataclasses import replace
import io
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import Mock, patch
from urllib.error import HTTPError

from Tools.InstallerKit.installer_apps import load_app
from Tools.InstallerKit.installer_update_feed import (
    BuildStatus,
    GitHubUpdateFeed,
    apply_change,
    changes_since,
    main,
    publish_receipt,
    publish_status,
)
from Fixtures.where_distribution_fixtures import SHA
from Fixtures.installer_update_fixtures import catalog as app_catalog
from Tools.InstallerKit.installer_installation import manifest_url
from Tools.InstallerKit.github_releases import asset_url
from Tools.InstallerKit.installer_update_site import render_site

APP = load_app("where")
REPO = "fixture/Stuff"
FEED_URL = "https://fixture.github.io/Stuff/updates.json"


def release(run, sha=SHA, attempt=1, channel="pr-42"):
    return {
        "id": {"run": run, "attempt": attempt},
        "sha": sha,
        "publishedAt": "2026-10-18T00:00:00Z",
        "manifestURL": manifest_url(
            FEED_URL, "where", channel, {"run": run, "attempt": attempt}
        ),
        "ipaURL": asset_url(REPO, "where", channel, {"run": run, "attempt": attempt}),
        "bundleVersion": "1",
        "baseSHA": None,
        "historyChanged": False,
        "commits": [],
    }


def empty():
    return {"schemaVersion": 3, "apps": []}


class InstallerUpdateFeedTests(unittest.TestCase):
    def test_deployment_before_first_publication_reads_an_empty_catalog_without_writing(
        self,
    ):
        transport = Mock(return_value=None)
        feed = GitHubUpdateFeed(REPO, "fixture-token", transport)
        self.assertEqual(feed.load_for_deployment(), empty())
        requests = [call.args[0] for call in transport.call_args_list]
        self.assertEqual([request.method for request in requests], ["GET", "GET"])
        self.assertEqual(
            [request.full_url for request in requests],
            [
                f"https://api.github.com/repos/{REPO}/contents/updates.json?ref=installer-update-feed",
                f"https://api.github.com/repos/{REPO}/git/ref/heads/installer-update-feed",
            ],
        )
        self.assertTrue(
            all(call.kwargs["allow_missing"] for call in transport.call_args_list)
        )

    def test_deployment_preserves_the_published_catalog_without_writing(self):
        published = app_catalog()
        published["apps"] += app_catalog(
            "example", "Example Dev", "com.example.development"
        )["apps"]
        published["apps"][0]["channels"][1]["active"] = False
        published["apps"][1]["channels"].append(
            {
                "name": "pr-43",
                "active": False,
                "releases": [],
                "buildStatus": {
                    "state": "failed",
                    "id": {"run": 3, "attempt": 1},
                    "sha": SHA,
                },
            }
        )
        transport = Mock(
            return_value={
                "sha": "revision",
                "encoding": "base64",
                "content": base64.b64encode(json.dumps(published).encode()).decode(),
            }
        )
        feed = GitHubUpdateFeed(REPO, "fixture-token", transport)
        self.assertEqual(feed.load_for_deployment(), published)
        transport.assert_called_once()
        self.assertEqual(transport.call_args.args[0].method, "GET")

    def test_deployment_does_not_replace_a_missing_file_on_an_existing_branch_with_empty_catalog(
        self,
    ):
        transport = Mock(side_effect=[None, {"object": {"sha": SHA}}])
        feed = GitHubUpdateFeed(REPO, "fixture-token", transport)
        with self.assertRaisesRegex(
            ValueError, "updates.json is missing from installer-update-feed"
        ):
            feed.load_for_deployment()
        self.assertTrue(
            all(call.args[0].method == "GET" for call in transport.call_args_list)
        )

    def test_deployment_propagates_catalog_and_branch_read_failures(self):
        for code in (401, 403, 429, 500):
            for missing_catalog in (False, True):
                with self.subTest(code=code, missing_catalog=missing_catalog):
                    failure = ValueError(f"api.github.com: HTTP {code}")
                    transport = Mock(
                        side_effect=([None] if missing_catalog else []) + [failure]
                    )
                    feed = GitHubUpdateFeed(REPO, "fixture-token", transport)
                    with self.assertRaisesRegex(ValueError, f"HTTP {code}"):
                        feed.load_for_deployment()
                    self.assertTrue(
                        all(
                            call.args[0].method == "GET"
                            for call in transport.call_args_list
                        )
                    )

    def test_deployment_rejects_malformed_or_unsupported_catalogs(self):
        for content in (b"not json", b'{"schemaVersion":2,"apps":[]}'):
            with self.subTest(content=content):
                transport = Mock(
                    return_value={
                        "sha": "revision",
                        "encoding": "base64",
                        "content": base64.b64encode(content).decode(),
                    }
                )
                feed = GitHubUpdateFeed(REPO, "fixture-token", transport)
                with self.assertRaises(ValueError):
                    feed.load_for_deployment()
                transport.assert_called_once()

    def test_progress_preserves_releases_and_cannot_regress_a_newer_attempt(self):
        previous = apply_change(empty(), APP, "main", release(1, channel="main"))
        preparing = BuildStatus("preparing", {"run": 2, "attempt": 1}, SHA)
        catalog = apply_change(previous, APP, "pr-42", preparing)
        channel = catalog["apps"][0]["channels"][1]
        self.assertFalse(channel["active"])
        self.assertEqual(channel["releases"], [])
        self.assertEqual(channel["buildStatus"], preparing.metadata())
        self.assertEqual(
            catalog["apps"][0]["channels"][0], previous["apps"][0]["channels"][0]
        )
        failed = apply_change(
            catalog, APP, "pr-42", BuildStatus("failed", preparing.identifier, SHA)
        )
        self.assertEqual(apply_change(failed, APP, "pr-42", preparing), failed)
        retry = BuildStatus("preparing", {"run": 2, "attempt": 2}, SHA)
        retrying = apply_change(failed, APP, "pr-42", retry)
        self.assertEqual(
            apply_change(
                retrying, APP, "pr-42", BuildStatus("failed", preparing.identifier, SHA)
            ),
            retrying,
        )
        published = apply_change(retrying, APP, "pr-42", release(2, attempt=2))
        self.assertNotIn("buildStatus", published["apps"][0]["channels"][1])
        self.assertEqual(
            apply_change(
                published, APP, "pr-42", BuildStatus("failed", retry.identifier, SHA)
            ),
            published,
        )
        rebuilding = apply_change(
            published,
            APP,
            "pr-42",
            BuildStatus("preparing", {"run": 3, "attempt": 1}, SHA),
        )
        self.assertTrue(rebuilding["apps"][0]["channels"][1]["active"])
        self.assertEqual(
            rebuilding["apps"][0]["channels"][1]["releases"], [release(2, attempt=2)]
        )
        retired = apply_change(rebuilding, APP, "pr-42", None)
        self.assertFalse(retired["apps"][0]["channels"][1]["active"])
        self.assertNotIn("buildStatus", retired["apps"][0]["channels"][1])
        self.assertEqual(
            catalog["apps"][0]["channels"][1]["buildStatus"], preparing.metadata()
        )

    def test_publishing_an_older_success_preserves_newer_build_progress(self):
        preparing = BuildStatus("preparing", {"run": 3, "attempt": 1}, SHA)
        catalog = apply_change(empty(), APP, "pr-42", preparing)
        published = apply_change(catalog, APP, "pr-42", release(2))
        self.assertTrue(published["apps"][0]["channels"][0]["active"])
        self.assertEqual(
            published["apps"][0]["channels"][0]["buildStatus"], preparing.metadata()
        )

    def test_stale_progress_cannot_revive_closed_unlabeled_or_changed_prs(self):
        pr = {
            "state": "open",
            "labels": [{"name": "installable"}],
            "head": {"sha": SHA, "repo": {"full_name": REPO}},
            "base": {"repo": {"full_name": REPO}},
        }
        invalid = [
            {**pr, "state": "closed"},
            {**pr, "labels": []},
            {**pr, "head": {**pr["head"], "sha": "b" * 40}},
            {**pr, "head": {**pr["head"], "repo": {"full_name": "other/Stuff"}}},
        ]
        for value in invalid:
            feed = Mock(repository=REPO)
            feed.save.side_effect = lambda app, channel, change, current: current()
            publish_status(
                "where",
                "pr-42",
                BuildStatus("preparing", {"run": 2, "attempt": 1}, SHA),
                feed,
                lambda _: value,
            )
            feed.deploy.assert_not_called()

    def test_status_command_publishes_progress_without_advertising_an_install(self):
        saved = []
        requests = []

        def transport(request, allow_missing=False):
            requests.append(request)
            if "/git/ref/" in request.full_url:
                return {"object": {"sha": SHA}}
            if request.method == "GET":
                return (
                    {
                        "sha": str(len(saved)),
                        "encoding": "base64",
                        "content": base64.b64encode(
                            json.dumps(saved[-1]).encode()
                        ).decode(),
                    }
                    if saved
                    else None
                )
            if request.method == "PUT":
                saved.append(
                    json.loads(base64.b64decode(json.loads(request.data)["content"]))
                )
            return {}

        feed = GitHubUpdateFeed(REPO, "fixture-token", transport)
        for state in ("preparing", "failed"):
            args = [
                "--status",
                state,
                "--app",
                "where",
                "--channel",
                "main",
                "--sha",
                SHA,
                "--run",
                "2",
                "--attempt",
                "1",
                "--repository",
                REPO,
                "--feed-url",
                FEED_URL,
            ]
            with (
                patch(
                    "Tools.InstallerKit.installer_update_feed.GitHubUpdateFeed",
                    return_value=feed,
                ),
                patch(
                    "Tools.InstallerKit.installer_distribution.github_fetch",
                    return_value={"object": {"sha": SHA}},
                ),
                redirect_stdout(io.StringIO()) as stdout,
                redirect_stderr(io.StringIO()) as stderr,
            ):
                self.assertEqual(main(args), 0)
            self.assertEqual(stdout.getvalue(), "")
            self.assertEqual(stderr.getvalue(), "")
            channel = saved[-1]["apps"][0]["channels"][0]
            self.assertEqual(channel["buildStatus"]["state"], state)
            self.assertFalse(channel["active"])
            self.assertEqual(channel["releases"], [])
            self.assertTrue(
                requests[-1].full_url.endswith("installer-pages.yml/dispatches")
            )

    def test_invalid_progress_fails_before_feed_mutation(self):
        for state, identifier, sha in (
            ("ready", {"run": 1, "attempt": 1}, SHA),
            ("preparing", {"run": True, "attempt": 1}, SHA),
            ("preparing", {"run": 1, "attempt": 0}, SHA),
            ("preparing", {"run": 1, "attempt": 1}, "not-a-sha"),
        ):
            feed = Mock(repository=REPO)
            with self.assertRaises(ValueError):
                publish_status(
                    "where", "pr-42", BuildStatus(state, identifier, sha), feed, Mock()
                )
            feed.save.assert_not_called()
            feed.deploy.assert_not_called()

    def test_publication_preserves_other_channels_and_bounds_history(self):
        catalog = apply_change(empty(), APP, "main", release(1, channel="main"))
        for run in range(1, 105):
            catalog = apply_change(catalog, APP, "pr-42", release(run))
        self.assertEqual(
            catalog["apps"][0]["channels"][0]["releases"], [release(1, channel="main")]
        )
        self.assertEqual(len(catalog["apps"][0]["channels"][1]["releases"]), 100)
        self.assertEqual(catalog["apps"][0]["channels"][1]["releases"][0], release(104))

    def test_older_reruns_cannot_replace_newer_builds_and_retirement_keeps_history(
        self,
    ):
        catalog = apply_change(empty(), APP, "pr-42", release(10))
        self.assertEqual(
            apply_change(catalog, APP, "pr-42", release(9, attempt=20)), catalog
        )
        rerun = apply_change(catalog, APP, "pr-42", release(10, attempt=2))
        self.assertEqual(
            rerun["apps"][0]["channels"][0]["releases"][0]["id"]["attempt"], 2
        )
        retired = apply_change(rerun, APP, "pr-42", None)
        self.assertFalse(retired["apps"][0]["channels"][0]["active"])
        self.assertEqual(
            retired["apps"][0]["channels"][0]["releases"],
            rerun["apps"][0]["channels"][0]["releases"],
        )

    def test_commit_history_keeps_skipped_commits_and_identifies_rewrites(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)

            def git(*args):
                return subprocess.run(
                    ["git", *args], cwd=root, check=True, text=True, capture_output=True
                ).stdout.strip()

            git("init", "-q")
            git("config", "user.email", "fixture@example.invalid")
            git("config", "user.name", "Fixture")
            git("config", "commit.gpgsign", "false")
            git("config", "core.hooksPath", "/dev/null")
            git("commit", "--allow-empty", "-qm", "First")
            first = git("rev-parse", "HEAD")
            git("commit", "--allow-empty", "-qm", "Second")
            second = git("rev-parse", "HEAD")
            git("commit", "--allow-empty", "-qm", "Third")
            third = git("rev-parse", "HEAD")

            def run(args, **kwargs):
                return subprocess.run(args, cwd=root, **kwargs)

            changes = changes_since(release(1, first), third, run)
            self.assertEqual(
                [commit["sha"] for commit in changes["commits"]], [third, second]
            )
            self.assertFalse(changes["historyChanged"])
            git("checkout", "--detach", first)
            git("commit", "--allow-empty", "-qm", "Rewritten")
            changes = changes_since(release(2, third), git("rev-parse", "HEAD"), run)
            self.assertTrue(changes["historyChanged"])
            self.assertEqual(
                [commit["subject"] for commit in changes["commits"]], ["Rewritten"]
            )

    def test_unavailable_ancestry_is_explicit(self):
        run = Mock(return_value=Mock(returncode=1))
        changes = changes_since(release(1), "b" * 40, run)
        self.assertTrue(changes["historyChanged"])
        self.assertIsNone(changes["baseSHA"])
        self.assertEqual(changes["commits"], [])

    def test_cas_conflict_reloads_and_preserves_concurrent_app(self):
        catalogs = [
            empty(),
            app_catalog("example", "Example Dev", "com.example.development"),
        ]
        writes = []

        def transport(request, allow_missing=False):
            if "/git/ref/" in request.full_url:
                return {"object": {"sha": SHA}}
            if request.method == "GET":
                catalog = catalogs[min(len(writes), 1)]
                return {
                    "sha": str(len(writes)),
                    "encoding": "base64",
                    "content": base64.b64encode(json.dumps(catalog).encode()).decode(),
                }
            body = json.loads(request.data)
            writes.append(json.loads(base64.b64decode(body["content"])))
            if len(writes) == 1:
                raise ValueError("conflict") from HTTPError(
                    request.full_url, 409, "conflict", {}, None
                )
            return {}

        feed = GitHubUpdateFeed("fixture/Stuff", "fixture-token", transport)
        current = Mock(return_value=True)
        progress = BuildStatus("preparing", {"run": 2, "attempt": 1}, SHA)
        self.assertTrue(feed.save(APP, "pr-42", lambda _: progress, current))
        self.assertEqual(
            [app["id"] for app in writes[-1]["apps"]], ["example", "where"]
        )
        self.assertEqual(writes[-1]["apps"][0], catalogs[1]["apps"][0])
        self.assertEqual(writes[-1]["apps"][1]["channels"][0]["name"], "pr-42")
        self.assertEqual(
            writes[-1]["apps"][1]["channels"][0]["buildStatus"], progress.metadata()
        )
        self.assertEqual(current.call_count, 2)

    def test_stale_receipt_never_changes_catalog_or_deploys(self):
        feed = Mock(repository="fixture/Stuff")
        feed.save.side_effect = lambda app, channel, make_release, current: current()
        receipt = {
            "action": "publish",
            "appID": "where",
            "channel": "main",
            "sha": SHA,
            "run": "2",
            "attempt": "1",
            "manifestURL": manifest_url(
                FEED_URL, "where", "main", {"run": 2, "attempt": 1}
            ),
            "ipaURL": asset_url(REPO, "where", "main", {"run": 2, "attempt": 1}),
            "bundleVersion": "1",
        }
        publish_receipt(
            receipt, feed, lambda _: {"object": {"sha": "b" * 40}}, FEED_URL
        )
        feed.deploy.assert_not_called()

    def test_pr_publication_uses_live_title_and_preserves_it_through_retirement(self):
        catalog = empty()
        title = "Fix **refresh** & keep <older builds> working — 更新"
        pr = {
            "title": title,
            "state": "open",
            "mergeable": True,
            "labels": [{"name": "installable"}],
            "head": {"sha": SHA, "repo": {"full_name": REPO}},
            "base": {"repo": {"full_name": REPO}},
        }
        fetch = Mock(return_value=pr)
        feed = Mock(repository=REPO)

        def save(app, channel, make_release, current):
            nonlocal catalog
            if not current():
                return False
            catalog = apply_change(catalog, app, channel, make_release(None))
            return True

        feed.save.side_effect = save
        receipt = {
            **release(2),
            "action": "publish",
            "appID": "where",
            "channel": "pr-42",
            "run": "2",
            "attempt": "1",
            "pullRequestTitle": "Stale receipt title",
        }
        publish_receipt(
            receipt, feed, fetch, FEED_URL, run=Mock(return_value=Mock(returncode=1))
        )
        published = catalog["apps"][0]["channels"][0]["releases"][0]
        self.assertEqual(published["pullRequestTitle"], title)
        self.assertTrue(
            all(
                call.args == (f"repos/{REPO}/pulls/42",)
                for call in fetch.call_args_list
            )
        )
        feed.deploy.assert_called_once()
        pr["state"] = "closed"
        publish_receipt(
            {"action": "retire", "appID": "where", "channel": "pr-42"},
            feed,
            fetch,
            FEED_URL,
        )
        self.assertFalse(catalog["apps"][0]["channels"][0]["active"])
        self.assertEqual(catalog["apps"][0]["channels"][0]["releases"][0], published)

    def test_app_cannot_reuse_a_retained_bundle_identifier(self):
        catalog = apply_change(empty(), APP, "main", release(1, channel="main"))
        requests = []

        def transport(request, allow_missing=False):
            requests.append(request)
            if "/git/ref/" in request.full_url:
                return {"object": {"sha": SHA}}
            return {
                "sha": "revision",
                "encoding": "base64",
                "content": base64.b64encode(json.dumps(catalog).encode()).decode(),
            }

        feed = GitHubUpdateFeed(REPO, "fixture-token", transport)
        renamed = replace(APP, id="renamed")
        with self.assertRaisesRegex(
            ValueError, "Duplicate installer app or bundle identifier"
        ):
            feed.save(renamed, "pr-42", lambda _: None, lambda: True)
        self.assertTrue(all(request.method == "GET" for request in requests))

    def test_publication_command_saves_a_catalog_that_renders_the_exact_ipa_manifest(
        self,
    ):
        requests = []
        saved = []

        def transport(request, allow_missing=False):
            requests.append(request)
            if "/git/ref/" in request.full_url:
                return {"object": {"sha": SHA}}
            if request.method == "GET":
                return None
            if request.method == "PUT":
                saved.append(
                    json.loads(base64.b64decode(json.loads(request.data)["content"]))
                )
            return {}

        published = release(2, channel="main")
        published["buildDetails"] = {
            "version": "0.9.2",
            "minimumOSVersion": "27.0",
            "sizeBytes": 48300000,
        }
        receipt = {
            **published,
            "action": "publish",
            "appID": "where",
            "channel": "main",
            "run": "2",
            "attempt": "1",
        }
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "receipt.json"
            path.write_text(json.dumps(receipt))
            feed = GitHubUpdateFeed(REPO, "fixture-token", transport)
            with (
                patch(
                    "Tools.InstallerKit.installer_update_feed.GitHubUpdateFeed",
                    return_value=feed,
                ),
                patch(
                    "Tools.InstallerKit.installer_distribution.github_fetch",
                    return_value={"object": {"sha": SHA}},
                ),
                redirect_stdout(io.StringIO()) as stdout,
                redirect_stderr(io.StringIO()) as stderr,
            ):
                self.assertEqual(
                    main(
                        [
                            "--receipt",
                            str(path),
                            "--repository",
                            REPO,
                            "--feed-url",
                            FEED_URL,
                        ]
                    ),
                    0,
                )
            self.assertEqual(stdout.getvalue(), "")
            self.assertEqual(stderr.getvalue(), "")
        self.assertEqual(len(saved), 1)
        self.assertEqual(
            requests[-1].full_url,
            f"https://api.github.com/repos/{REPO}/actions/workflows/installer-pages.yml/dispatches",
        )
        files = render_site(saved[0], REPO, FEED_URL)
        self.assertEqual(json.loads(files["updates.json"]), saved[0])
        self.assertEqual(
            saved[0]["apps"][0]["channels"][0]["releases"][0]["buildDetails"],
            published["buildDetails"],
        )
        self.assertNotIn(
            "pullRequestTitle", saved[0]["apps"][0]["channels"][0]["releases"][0]
        )
        item = plistlib.loads(files["manifests/where/main/2-1.plist"])["items"][0]
        self.assertEqual(item["assets"][0]["url"], published["ipaURL"])
        self.assertEqual(item["metadata"]["bundle-version"], published["bundleVersion"])

    def test_wrong_build_manifest_fails_before_catalog_or_deployment_mutation(self):
        receipt = {
            **release(2, channel="main"),
            "action": "publish",
            "appID": "where",
            "channel": "main",
            "run": "2",
            "attempt": "1",
        }
        receipt["manifestURL"] = manifest_url(
            FEED_URL, "where", "main", {"run": 1, "attempt": 1}
        )
        feed = Mock(repository=REPO)
        fetch = Mock()
        with self.assertRaisesRegex(ValueError, "Manifest URL"):
            publish_receipt(receipt, feed, fetch, FEED_URL)
        feed.save.assert_not_called()
        feed.deploy.assert_not_called()
        fetch.assert_not_called()

    def test_invalid_build_details_fail_before_catalog_or_deployment_mutation(self):
        valid = {"version": "0.9.2", "minimumOSVersion": "27.0", "sizeBytes": 48300000}
        invalid = [
            None,
            {},
            {**valid, "version": "<script>"},
            {**valid, "minimumOSVersion": 27},
            {**valid, "sizeBytes": True},
            {**valid, "sizeBytes": -1},
            {**valid, "sizeBytes": 1.5},
        ]
        for details in invalid:
            receipt = {
                **release(2, channel="main"),
                "action": "publish",
                "appID": "where",
                "channel": "main",
                "run": "2",
                "attempt": "1",
                "buildDetails": details,
            }
            feed = Mock(repository=REPO)
            fetch = Mock()
            with self.subTest(details=details), self.assertRaises(ValueError):
                publish_receipt(receipt, feed, fetch, FEED_URL)
            feed.save.assert_not_called()
            feed.deploy.assert_not_called()
            fetch.assert_not_called()

    def test_cli_missing_receipt_is_noop_and_failure_reports_nonzero(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "receipt.json"
            args = [
                "--receipt",
                str(path),
                "--repository",
                "fixture/Stuff",
                "--feed-url",
                FEED_URL,
            ]
            with (
                redirect_stdout(io.StringIO()) as stdout,
                patch(
                    "Tools.InstallerKit.installer_update_feed.GitHubUpdateFeed"
                ) as feed,
            ):
                self.assertEqual(main(args), 0)
                feed.assert_not_called()
                self.assertIn("unchanged", stdout.getvalue())
            path.write_text(
                json.dumps({"action": "retire", "appID": "where", "channel": "pr-42"})
            )
            with (
                patch(
                    "Tools.InstallerKit.installer_update_feed.GitHubUpdateFeed"
                ) as feed,
                redirect_stderr(io.StringIO()) as stderr,
            ):
                feed.return_value.save.side_effect = ValueError("write rejected")
                self.assertEqual(main(args), 1)
                self.assertIn("write rejected", stderr.getvalue())
                feed.return_value.deploy.assert_not_called()

    def test_same_channel_and_run_are_isolated_between_apps(self):
        other = replace(
            APP,
            id="example",
            name="Example Dev",
            bundle_identifier="com.example.development",
        )
        catalog = apply_change(empty(), APP, "pr-42", release(2))
        other_release = app_catalog(
            "example", "Example Dev", "com.example.development"
        )["apps"][0]["channels"][1]["releases"][0]
        catalog = apply_change(catalog, other, "pr-42", other_release)
        retired = apply_change(catalog, APP, "pr-42", None)
        by_id = {app["id"]: app for app in retired["apps"]}
        self.assertFalse(by_id["where"]["channels"][0]["active"])
        self.assertTrue(by_id["example"]["channels"][0]["active"])
        self.assertEqual(by_id["example"]["channels"][0]["releases"], [other_release])
        with self.assertRaisesRegex(ValueError, "cannot change"):
            apply_change(
                catalog,
                replace(APP, bundle_identifier="com.other.app"),
                "main",
                release(3),
            )
