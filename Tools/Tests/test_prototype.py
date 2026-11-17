"""Policy regressions for prototype ownership, lifecycle, and current URLs."""

import contextlib
import io
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from Tools import prototype


class PrototypeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="prototype ü ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        (self.root / ".git").mkdir()
        self.project = self.root / "A prototype"
        self.project.mkdir()
        (self.project / "astro.config.mjs").touch()
        (self.project / ".astro").mkdir()
        self.record = {
            "pid": 123456,
            "port": 4321,
            "url": "http://localhost:4321/",
            "background": True,
            "startedAt": "2026-11-15T12:00:00Z",
            "urls": {"network": ["http://192.0.2.1:4321/"]},
        }
        self.path = self.project / ".astro/dev.json"
        self.write_record()
        self.server = prototype.read_server(self.project)

    def write_record(self):
        self.path.write_text(json.dumps(self.record))

    def test_explicit_path_handles_astro_metadata_that_omits_base(self):
        self.record["url"] = "http://localhost:4321"
        self.record["urls"]["local"] = ["http://localhost:4321/"]
        self.write_record()
        server = prototype.read_server(self.project)
        with (
            patch.object(
                prototype, "current_addresses", return_value=[("en0", "192.0.2.2")]
            ),
            patch.object(prototype, "responds", return_value=True) as responds,
            contextlib.redirect_stdout(io.StringIO()) as output,
        ):
            prototype.report(self.project, server, path="/demo/")
        self.assertIn("http://localhost:4321/demo/", output.getvalue())
        self.assertIn("http://192.0.2.2:4321/demo/", output.getvalue())
        self.assertTrue(
            all(call.args[1].path == "/demo/" for call in responds.call_args_list)
        )

    def test_missing_and_dead_records_do_not_mutate_status(self):
        before = self.path.read_bytes()
        with patch.object(os, "kill", side_effect=ProcessLookupError):
            self.assertIsNone(prototype.live_server(self.project))
        self.assertEqual(self.path.read_bytes(), before)
        self.path.unlink()
        self.assertIsNone(prototype.read_server(self.project))

    def test_uninspectable_process_is_not_absent(self):
        before = self.path.read_bytes()
        with patch.object(os, "kill", side_effect=PermissionError("denied")):
            with self.assertRaisesRegex(PermissionError, "denied"):
                prototype.live_server(self.project)
        self.assertEqual(self.path.read_bytes(), before)

    def test_exit_during_inspection_is_absence_but_other_errors_propagate(self):
        for later, expected in ((ProcessLookupError(), False), (None, None)):
            with (
                patch.object(os, "kill", side_effect=[None, later]),
                patch.object(
                    prototype, "process_identity", side_effect=FileNotFoundError("gone")
                ),
            ):
                if expected is False:
                    self.assertFalse(prototype.owns_process(self.project, self.server))
                else:
                    with self.assertRaisesRegex(FileNotFoundError, "gone"):
                        prototype.owns_process(self.project, self.server)

    def test_invalid_records_fail_without_removal(self):
        for bad in (
            [],
            {**self.record, "pid": True},
            {**self.record, "port": 0},
            {**self.record, "url": {}},
            {**self.record, "url": "http://example.com:4321/"},
        ):
            with self.subTest(record=bad):
                self.path.write_text(json.dumps(bad))
                with self.assertRaises(ValueError):
                    prototype.read_server(self.project)
                self.assertEqual(json.loads(self.path.read_text()), bad)
        self.path.write_text("not json")
        with self.assertRaises(ValueError):
            prototype.read_server(self.project)
        self.assertEqual(self.path.read_text(), "not json")

    def identity(self, platform, project=None):
        project = project or self.project
        argv = [
            "/tool chain/node",
            str(self.root / "node_modules/astro/bin/astro.mjs"),
            "dev",
            "--port",
            "4321",
            "--host",
            "0.0.0.0",
            "--config",
            "astro.config.mjs",
            "--root",
            str(project),
            "--json",
        ]
        identity = argv if platform == "linux" else (argv[0], " ".join(argv[1:]))
        return identity, project

    def test_owned_absolute_root_with_spaces_and_unicode_on_both_platforms(self):
        for platform in ("darwin", "linux"):
            with (
                self.subTest(platform=platform),
                patch.object(prototype.sys, "platform", platform),
                patch.object(os, "kill"),
                patch.object(
                    prototype, "process_identity", return_value=self.identity(platform)
                ),
            ):
                self.assertTrue(prototype.owns_process(self.project, self.server))

    def test_another_astro_project_or_mismatched_cwd_is_not_owned(self):
        other = self.root / "A prototype other"
        for platform in ("darwin", "linux"):
            for identity in (
                self.identity(platform, other),
                (self.identity(platform)[0], other),
            ):
                with (
                    self.subTest(platform=platform, identity=identity),
                    patch.object(prototype.sys, "platform", platform),
                    patch.object(os, "kill"),
                    patch.object(prototype, "process_identity", return_value=identity),
                ):
                    with self.assertRaisesRegex(ValueError, "not an owned"):
                        prototype.owns_process(self.project, self.server)

    def test_arbitrary_process_and_foreground_server_are_not_owned(self):
        for identity in (
            (["python3", "other.py"], self.project),
            self.identity("linux"),
        ):
            with (
                patch.object(prototype.sys, "platform", "linux"),
                patch.object(os, "kill"),
                patch.object(prototype, "process_identity", return_value=identity),
            ):
                server = prototype.Server(
                    self.server.pid, 4321, "/", False, self.record
                )
                with self.assertRaisesRegex(ValueError, "not an owned"):
                    prototype.owns_process(self.project, server)

    def test_report_uses_current_reachable_addresses_and_ignores_cached_urls(self):
        calls = []

        def responds(host, server):
            calls.append(host)
            return host != "192.0.2.3"

        with (
            patch.object(
                prototype,
                "current_addresses",
                return_value=[("en0", "192.0.2.2"), ("vpn", "192.0.2.3")],
            ),
            patch.object(prototype, "responds", side_effect=responds),
            contextlib.redirect_stdout(io.StringIO()) as output,
        ):
            prototype.report(self.project, self.server, lan_required=True)
        self.assertIn("http://192.0.2.2:4321/", output.getvalue())
        self.assertNotIn("192.0.2.1", output.getvalue())
        self.assertNotIn("http://192.0.2.3", output.getvalue())
        self.assertEqual(calls, ["127.0.0.1", "192.0.2.2", "192.0.2.3"])

    def test_lan_request_cannot_succeed_for_loopback_only_server(self):
        with (
            patch.object(prototype, "current_addresses", return_value=[]),
            patch.object(prototype, "responds", return_value=True),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            with self.assertRaisesRegex(ValueError, "LAN preview is unavailable"):
                prototype.report(self.project, self.server, lan_required=True)

    def test_http_failure_is_bounded_and_diagnostic(self):
        with patch.object(prototype, "responds", return_value=False):
            with self.assertRaisesRegex(ValueError, "no successful HTTP response"):
                prototype.report(self.project, self.server)

    def test_probes_do_not_follow_redirects_or_use_proxy_environment(self):
        with patch.object(prototype.http.client, "HTTPConnection") as connection:
            connection.return_value.getresponse.return_value.status = 302
            self.assertFalse(prototype.responds("192.0.2.2", self.server))
            connection.assert_called_once_with("192.0.2.2", 4321, timeout=2)
            connection.return_value.request.assert_called_once_with("GET", "/")
            connection.return_value.close.assert_called_once()

    def test_current_addresses_use_pinned_node_and_filter_loopback_ipv6(self):
        interfaces = {
            "lo": [{"family": "IPv4", "internal": True, "address": "127.0.0.1"}],
            "en0": [
                {"family": "IPv4", "internal": False, "address": "192.0.2.2"},
                {"family": "IPv6", "internal": False, "address": "fe80::1"},
            ],
        }
        with (
            patch.object(prototype, "resolve_mise", return_value="/pinned/mise"),
            patch.object(
                prototype.subprocess,
                "run",
                return_value=subprocess.CompletedProcess(
                    [], 0, json.dumps(interfaces), ""
                ),
            ) as run,
        ):
            self.assertEqual(prototype.current_addresses(), [("en0", "192.0.2.2")])
            self.assertEqual(
                run.call_args.args[0][:5],
                ["/pinned/mise", "exec", "node", "--", "node"],
            )
            self.assertEqual(run.call_args.kwargs["cwd"], prototype.SOURCE_ROOT)

    def test_repeated_start_reuses_server_without_launching(self):
        with (
            patch.object(prototype, "astro_command"),
            patch.object(prototype, "live_server", return_value=self.server),
            patch.object(prototype, "run_astro") as run,
            patch.object(prototype, "report") as report,
            contextlib.redirect_stdout(io.StringIO()),
        ):
            self.assertEqual(
                prototype.start(self.project, None, True, path="/demo/"), 0
            )
            run.assert_not_called()
            report.assert_called_once_with(
                self.project,
                self.server,
                path="/demo/",
                lan_required=True,
                wait_seconds=10,
            )

    def test_existing_port_mismatch_preserves_server(self):
        with (
            patch.object(prototype, "astro_command"),
            patch.object(prototype, "live_server", return_value=self.server),
            patch.object(prototype, "run_astro") as run,
        ):
            with self.assertRaisesRegex(ValueError, "Already running on port 4321"):
                prototype.start(self.project, 4322, False)
            run.assert_not_called()

    def test_start_refuses_a_busy_port_before_astro(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            with (
                patch.object(prototype, "astro_command"),
                patch.object(prototype, "live_server", return_value=None),
                patch.object(prototype, "run_astro") as run,
            ):
                with self.assertRaisesRegex(ValueError, "Port .* is unavailable"):
                    prototype.start(self.project, listener.getsockname()[1], False)
                run.assert_not_called()

    def test_start_passes_host_and_port_to_native_background_lifecycle(self):
        with (
            patch.object(prototype, "astro_command"),
            patch.object(
                prototype, "live_server", side_effect=[None, None, self.server]
            ),
            patch.object(prototype, "run_astro", return_value=0) as run,
            patch.object(prototype, "report"),
            patch.object(prototype.socket, "socket"),
        ):
            self.assertEqual(prototype.start(self.project, 4321, True), 0)
            run.assert_called_once_with(
                self.project,
                "dev",
                "--host",
                "0.0.0.0",
                "--port",
                "4321",
                "--background",
            )

    def test_competing_start_is_rejected_without_launch(self):
        with (
            prototype.lifecycle_lock(self.project),
            patch.object(prototype, "astro_command"),
            patch.object(prototype, "live_server", return_value=None),
            patch.object(prototype, "run_astro") as run,
        ):
            with self.assertRaisesRegex(ValueError, "Another prototype start/stop"):
                prototype.start(self.project, None, False)
            run.assert_not_called()

    def test_stop_rechecks_record_before_delegating(self):
        changed = prototype.Server(654321, 4321, "/", True, {})
        with (
            patch.object(prototype, "live_server", side_effect=[self.server, changed]),
            patch.object(prototype, "astro_command"),
            patch.object(prototype, "run_astro") as run,
        ):
            with self.assertRaisesRegex(ValueError, "Server changed"):
                prototype.stop(self.project)
            run.assert_not_called()

    def test_stop_checks_native_result_and_process_exit(self):
        with (
            patch.object(prototype, "live_server", return_value=self.server),
            patch.object(prototype, "astro_command"),
            patch.object(prototype, "run_astro", return_value=0) as run,
            patch.object(prototype, "owns_process", return_value=False),
        ):
            self.assertEqual(prototype.stop(self.project), 0)
            run.assert_called_once_with(self.project, "dev", "stop")

    def test_native_failure_and_signal_status_are_preserved(self):
        for code, expected in ((17, 17), (-15, 143)):
            with (
                patch.object(prototype, "astro_command", return_value=["fake"]),
                patch.object(
                    prototype.subprocess,
                    "run",
                    return_value=subprocess.CompletedProcess([], code),
                ),
            ):
                self.assertEqual(prototype.run_astro(self.project, "check"), expected)


if __name__ == "__main__":
    unittest.main()
