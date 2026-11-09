import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

from Tools import ci_pages

SHA = "a" * 40
NEW = "b" * 40


class CIPagesTests(unittest.TestCase):
    def test_only_exact_successful_deployment_confirms_site(self):
        feed = Mock()
        feed.request.return_value = {
            "sha": SHA,
            "statuses": [{"context": "unrelated", "state": "success"}],
        }
        with patch("Tools.ci_pages.branch_head", return_value=SHA):
            with self.assertRaises(TimeoutError):
                ci_pages.wait_for_deployment(
                    feed, SHA, clock=Mock(side_effect=[0, 0, 601]), sleep=Mock()
                )
            feed.request.return_value = {
                "sha": SHA,
                "statuses": [{"context": "pages-publication", "state": "success"}],
            }
            self.assertTrue(
                ci_pages.wait_for_deployment(
                    feed, SHA, clock=Mock(side_effect=[0, 0]), sleep=Mock()
                )
            )
            feed.request.return_value["sha"] = NEW
            with self.assertRaises(ValueError):
                ci_pages.wait_for_deployment(
                    feed, SHA, clock=Mock(side_effect=[0, 0]), sleep=Mock()
                )

    def test_failed_or_superseded_deployment_does_not_wait_for_timeout(self):
        feed = Mock()
        sleep = Mock()
        with patch("Tools.ci_pages.branch_head", return_value=SHA):
            for state in ("failure", "error"):
                feed.request.return_value = {
                    "sha": SHA,
                    "statuses": [{"context": "pages-publication", "state": state}],
                }
                with self.assertRaisesRegex(ValueError, "deployment failed"):
                    ci_pages.wait_for_deployment(
                        feed, SHA, clock=Mock(side_effect=[0, 0]), sleep=sleep
                    )
        with patch("Tools.ci_pages.branch_head", return_value=NEW):
            self.assertFalse(
                ci_pages.wait_for_deployment(
                    feed, SHA, clock=Mock(side_effect=[0, 0]), sleep=sleep
                )
            )
        sleep.assert_not_called()

    def test_site_push_uses_lease_and_no_history_or_persisted_credential(self):
        with tempfile.TemporaryDirectory(prefix="Pages test ü ") as temporary:
            root = Path(temporary)
            remote = root / "remote.git"
            subprocess.run(
                ["git", "init", "--bare", str(remote)], check=True, capture_output=True
            )
            calls = []

            def run(argv, **kwargs):
                calls.append(argv)
                if argv[1] == "push":
                    argv = [
                        str(remote)
                        if arg == "https://github.com/fixture/Stuff.git"
                        else arg
                        for arg in argv
                    ]
                return subprocess.run(argv, **kwargs)

            def site(name):
                output = root / name
                output.mkdir()
                (output / "index.html").write_text(name)
                return output

            first = ci_pages.push_site(
                site("first"), "fixture/Stuff", "", "secret", run
            )
            second = ci_pages.push_site(
                site("second"), "fixture/Stuff", first, "secret", run
            )
            with self.assertRaises(subprocess.CalledProcessError):
                ci_pages.push_site(site("stale"), "fixture/Stuff", first, "secret", run)
            actual = subprocess.check_output(
                ["git", "--git-dir", str(remote), "rev-parse", "gh-pages"], text=True
            ).strip()
            self.assertEqual(actual, second)
            self.assertNotEqual(first, second)
            self.assertEqual(
                subprocess.check_output(
                    [
                        "git",
                        "--git-dir",
                        str(remote),
                        "rev-list",
                        "--count",
                        "gh-pages",
                    ],
                    text=True,
                ).strip(),
                "1",
            )
            self.assertTrue((root / "second/.nojekyll").is_file())
            self.assertNotIn("secret", repr(calls))
            self.assertNotIn("secret", (root / "second/.git/config").read_text())
            self.assertIn(
                f"--force-with-lease=refs/heads/gh-pages:{first}",
                [c for c in calls if c[1] == "push"][1],
            )

    def test_concurrent_site_push_rebuilds_latest_inputs_before_retry(self):
        feed = Mock(repository="fixture/Stuff")
        feed.request.return_value = {"build_type": "workflow"}
        push = Mock(side_effect=[subprocess.CalledProcessError(1, "git"), NEW])
        wait = Mock(return_value=True)
        with (
            patch("Tools.ci_pages.branch_head", side_effect=["", SHA, SHA]),
            patch(
                "Tools.ci_pages.render_site", return_value={"index.html": b"ok"}
            ) as render,
            patch("Tools.ci_pages.compose", return_value="flyover-atlas-2-1"),
            patch("Tools.ci_pages.prune") as prune,
        ):
            self.assertTrue(
                ci_pages.deploy(
                    feed,
                    "https://example.test/updates.json",
                    "secret",
                    Mock(return_value=True),
                    push=push,
                    wait=wait,
                )
            )
        self.assertEqual(render.call_count, 2)
        self.assertEqual(feed.load_for_deployment.call_count, 2)
        self.assertEqual(push.call_args.args[2], SHA)
        self.assertEqual(
            feed.request.call_args.args,
            (
                "POST",
                "dispatches",
                {"event_type": "pages-publication"},
            ),
        )
        wait.assert_called_once_with(feed, NEW)
        self.assertEqual(
            prune.call_args.args[:2], ("fixture/Stuff", "flyover-atlas-2-1")
        )

    def test_failed_superseded_or_stale_source_never_runs_retention(self):
        for result in (
            False,
            ValueError("deployment failed"),
            "stale-before",
            "stale-after",
        ):
            feed = Mock(repository="fixture/Stuff")
            feed.request.return_value = {"build_type": "workflow"}
            current = Mock(
                side_effect=[False]
                if result == "stale-before"
                else [True, False]
                if result == "stale-after"
                else [True, True]
            )
            push = Mock(return_value=NEW)
            wait = Mock(
                side_effect=result if isinstance(result, Exception) else None,
                return_value=result,
            )
            with (
                patch("Tools.ci_pages.branch_head", return_value=SHA),
                patch("Tools.ci_pages.render_site", return_value={"index.html": b"ok"}),
                patch("Tools.ci_pages.compose", return_value="flyover-atlas-2-1"),
                patch("Tools.ci_pages.prune") as prune,
            ):
                if isinstance(result, Exception):
                    with self.assertRaises(ValueError):
                        ci_pages.deploy(
                            feed,
                            "https://example.test/updates.json",
                            "secret",
                            current,
                            push=push,
                            wait=wait,
                        )
                else:
                    self.assertFalse(
                        ci_pages.deploy(
                            feed,
                            "https://example.test/updates.json",
                            "secret",
                            current,
                            push=push,
                            wait=wait,
                        )
                    )
                prune.assert_not_called()
                if isinstance(result, str):
                    push.assert_not_called()

    def test_command_hides_process_and_transport_errors(self):
        with (
            patch.dict(
                "os.environ",
                {
                    "GITHUB_REPOSITORY": "fixture/Stuff",
                    "GH_TOKEN": "secret",
                    "INSTALLER_FEED_URL": "https://example.test/updates.json",
                },
            ),
            patch("Tools.ci_pages.deploy", side_effect=OSError("secret")),
            patch("Tools.ci_pages.subprocess.check_output", return_value=SHA),
            patch("sys.stderr", new_callable=io.StringIO) as stderr,
        ):
            self.assertEqual(ci_pages.main(), 1)
        self.assertNotIn("secret", stderr.getvalue())
