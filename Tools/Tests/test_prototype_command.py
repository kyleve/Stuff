"""Exercise the public prototype command without a real Node server or daemon."""

import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import unittest

from Tools.repository import repository_root

REPOSITORY = repository_root(__file__)


class PrototypeCommandTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="prototype command ü ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.checkout = self.root / "Stuff with spaces"
        self.outside = self.root / "outside"
        self.project = self.outside / "Example ü"
        self.bin = self.root / "bin"
        for directory in (self.checkout / "Tools", self.bin, self.project):
            directory.mkdir(parents=True)
        (self.checkout / ".git").touch()
        for source in (
            "prototype",
            "Tools/prototype.py",
            "Tools/astro_site.py",
            "Tools/repository.py",
        ):
            shutil.copy2(REPOSITORY / source, self.checkout / source)
        (self.project / "astro.config.mjs").touch()
        (self.bin / "python3").symlink_to(sys.executable)
        self.trace = self.root / "trace.json"
        self.environment = {
            **os.environ,
            "PATH": str(self.bin),
            "PROTOTYPE_TEST_TRACE": str(self.trace),
        }
        self.environment.pop("PYTHONPATH", None)

    def fake_tools(self):
        entry = self.checkout / "node_modules/.bin/astro"
        entry.parent.mkdir(parents=True)
        entry.touch()
        mise = self.bin / "mise"
        mise.write_text("""#!/usr/bin/env python3
import json
import os
from pathlib import Path
import signal
import sys
Path(os.environ['PROTOTYPE_TEST_TRACE']).write_text(json.dumps({
    'argv': sys.argv[1:], 'cwd': os.getcwd(),
    'telemetry': os.environ.get('ASTRO_TELEMETRY_DISABLED'),
}))
print('child stdout')
print('child stderr', file=sys.stderr)
if os.environ.get('PROTOTYPE_TEST_SIGNAL'):
    os.kill(os.getpid(), signal.SIGTERM)
sys.exit(int(os.environ.get('PROTOTYPE_TEST_EXIT', '0')))
""")
        mise.chmod(0o755)

    def run_command(self, *arguments):
        return subprocess.run(
            [str(self.checkout / "prototype"), *arguments],
            cwd=self.outside,
            env=self.environment,
            text=True,
            capture_output=True,
            timeout=15,
        )

    def record(self, pid):
        (self.project / ".astro").mkdir(exist_ok=True)
        path = self.project / ".astro/dev.json"
        path.write_text(
            json.dumps(
                {
                    "pid": pid,
                    "port": 4321,
                    "url": "http://localhost:4321/",
                    "background": True,
                    "startedAt": "2026-11-15T12:00:00Z",
                }
            )
        )
        return path

    def test_help_and_usage_errors_need_no_tooling_from_unrelated_cwd(self):
        result = self.run_command("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("start,status,stop,logs,check,build", result.stdout)
        self.assertEqual(result.stderr, "")
        for arguments in (
            ("start", "Example ü", "--port", "0"),
            ("unknown",),
            ("status", "Example ü", "--lan"),
            ("start", "Example ü", "--path", "https://example.com/"),
            ("start", "Example ü", "--path", "//example.com/"),
            ("start", "Example ü", "--path", "/demo/?q=x"),
        ):
            with self.subTest(arguments=arguments):
                result = self.run_command(*arguments)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("error:", result.stderr)
                self.assertNotIn("mise", result.stderr)
        self.assertFalse((self.project / ".astro").exists())

    def test_check_and_build_preserve_streams_status_and_absolute_project(self):
        self.fake_tools()
        self.environment["PROTOTYPE_TEST_EXIT"] = "17"
        for command in ("check", "build"):
            with self.subTest(command=command):
                result = self.run_command(command, "Example ü")
                self.assertEqual(result.returncode, 17)
                self.assertEqual(result.stdout, "child stdout\n")
                self.assertEqual(result.stderr, "child stderr\n")
                trace = json.loads(self.trace.read_text())
                self.assertEqual(trace["cwd"], str(self.checkout))
                self.assertEqual(trace["telemetry"], "1")
                self.assertEqual(
                    trace["argv"],
                    [
                        "exec",
                        "node",
                        "--",
                        "node",
                        str(self.checkout / "node_modules/.bin/astro"),
                        command,
                        "--root",
                        str(self.project),
                        "--config",
                        "astro.config.mjs",
                    ],
                )

    def test_signal_exit_propagates(self):
        self.fake_tools()
        self.environment["PROTOTYPE_TEST_SIGNAL"] = "1"
        result = self.run_command("check", str(self.project))
        self.assertEqual(result.returncode, 143, result.stderr)

    def test_invalid_project_is_rejected_before_tooling_or_state(self):
        result = self.run_command("start", str(self.outside))
        self.assertEqual(result.returncode, 1)
        self.assertIn("Expected astro.config.mjs", result.stderr)
        self.assertFalse((self.outside / ".astro").exists())
        self.assertFalse(self.trace.exists())

    def test_missing_dependencies_are_actionable_before_state(self):
        result = self.run_command("start", "Example ü")
        self.assertEqual(result.returncode, 1)
        self.assertIn("mise exec -- npm ci", result.stderr)
        self.assertFalse((self.project / ".astro").exists())

    def test_status_of_stale_record_is_read_only_and_needs_no_tooling(self):
        child = subprocess.Popen([sys.executable, "-c", "pass"])
        child.wait(timeout=5)
        path = self.record(child.pid)
        before = path.read_bytes()
        result = self.run_command("status", "Example ü")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("No prototype server is running", result.stdout)
        self.assertEqual(result.stderr, "")
        self.assertEqual(path.read_bytes(), before)

    def test_zombie_is_stale_without_erasing_its_record(self):
        child = subprocess.Popen([sys.executable, "-c", "pass"])
        self.addCleanup(child.wait, timeout=5)
        deadline = time.monotonic() + 5
        while True:
            state = subprocess.run(
                ["/bin/ps", "-p", str(child.pid), "-o", "stat="],
                text=True,
                capture_output=True,
                check=True,
            ).stdout.strip()
            if state.startswith("Z"):
                break
            if time.monotonic() >= deadline:
                self.fail("Child did not enter zombie state before deadline")
            time.sleep(0.01)
        path = self.record(child.pid)
        before = path.read_bytes()
        for command, code in (("status", 1), ("stop", 0)):
            result = self.run_command(command, "Example ü")
            self.assertEqual(result.returncode, code, result.stderr)
            self.assertIn("No prototype server is running", result.stdout)
            self.assertEqual(result.stderr, "")
            self.assertEqual(path.read_bytes(), before)

    def test_stop_refuses_an_unrelated_live_process(self):
        path = self.record(os.getpid())
        before = path.read_bytes()
        result = self.run_command("stop", "Example ü")
        self.assertEqual(result.returncode, 1)
        self.assertIn("not an owned background Astro server", result.stderr)
        self.assertEqual(path.read_bytes(), before)
        self.assertFalse(self.trace.exists())
        os.kill(os.getpid(), 0)

    def test_logs_are_available_after_failed_start_without_tooling(self):
        path = self.record(123456)
        (path.parent / "dev.log").write_text("Astro could not start\n")
        result = self.run_command("logs", "Example ü")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "Astro could not start\n")
        self.assertEqual(result.stderr, "")
        self.assertTrue(path.exists())

    def test_malformed_status_is_an_error_and_keeps_evidence(self):
        path = self.record(123456)
        path.write_text("corrupt")
        result = self.run_command("status", "Example ü")
        self.assertEqual(result.returncode, 1)
        self.assertIn("prototype:", result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(path.read_text(), "corrupt")

    def test_stopping_absent_server_is_idempotent(self):
        result = self.run_command("stop", "Example ü")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "No prototype server is running.\n")
        self.assertFalse((self.project / ".astro").exists())

    def test_start_preserves_native_failure(self):
        self.fake_tools()
        self.environment["PROTOTYPE_TEST_EXIT"] = "23"
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        result = self.run_command("start", "Example ü", "--port", str(port), "--lan")
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertEqual(result.stderr, "child stderr\n")
        self.assertEqual(result.stdout, "child stdout\n")
        argv = json.loads(self.trace.read_text())["argv"]
        self.assertIn("--background", argv)
        self.assertEqual(argv[argv.index("--root") + 1], str(self.project))
        self.assertEqual(argv[argv.index("--host") + 1], "0.0.0.0")


if __name__ == "__main__":
    unittest.main()
