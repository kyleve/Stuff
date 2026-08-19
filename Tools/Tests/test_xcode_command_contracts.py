import json
import os
from pathlib import Path
import shutil
import signal
import stat
import subprocess
import tempfile
import time
import unittest


REPOSITORY = Path(__file__).resolve().parents[2]


class XcodeCommandFixture:
    def __init__(self, temporary: str):
        self.root = Path(temporary) / "repository with spaces ü"
        self.bin = self.root / "fake bin"
        self.outside = self.root / "outside cwd"
        self.home = self.root / "home"
        self.log = self.root / "commands.log"
        self.test_work = self.root / "test work"
        self.profile_work = self.root / "profile work"
        for directory in (self.bin, self.outside, self.home):
            directory.mkdir(parents=True, exist_ok=True)

        for command in ("test", "profile", "flaky"):
            self._copy(command)
        for module in (
            "flaky_results.py",
            "profile_results.py",
            "snapshot_reports.py",
            "test_runner.py",
            "xcode_results.py",
        ):
            self._copy(f"Tools/{module}")
        (self.root / "Project.swift").write_text('name: "ExampleSnapshotTests"\n')
        self._write_executable(
            self.root / "simulator",
            "#!/bin/bash\nprintf 'fixture-udid\\n'\n",
        )
        (self.root / "signal_child.py").write_text(
            """import os
from pathlib import Path
import signal
import sys
import time

Path(sys.argv[1]).write_text(str(os.getpid()))

def finish(received, _frame):
    Path(sys.argv[2]).write_text(str(received))
    raise SystemExit(128 + received)

signal.signal(signal.SIGINT, finish)
signal.signal(signal.SIGTERM, finish)
while True:
    time.sleep(1)
"""
        )
        self._write_fake_tools()

    def run(self, command: str, *arguments: str, **overrides: str):
        environment = self.environment(overrides)
        return subprocess.run(
            [str(self.root / command), *arguments],
            cwd=self.outside,
            env=environment,
            capture_output=True,
            text=True,
        )

    def environment(self, overrides=None):
        environment = {
            "HOME": str(self.home),
            "LC_ALL": "C",
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "PROFILE_WORKDIR": str(self.profile_work),
            "TEST_WORKDIR": str(self.test_work),
            "TMPDIR": str(self.root / "temporary files"),
            "TOOL_LOG": str(self.log),
            "BUILD_STATUS": "0",
            "MISE_STATUS": "0",
            "TEST_STATUS": "0",
            "XCODE_OUTPUT": "passing",
            "XCRUN_OUTPUT": "valid",
        }
        environment.update(overrides or {})
        Path(environment["TMPDIR"]).mkdir(exist_ok=True)
        return environment

    def command_log(self) -> str:
        return self.log.read_text() if self.log.exists() else ""

    def _copy(self, relative: str) -> None:
        destination = self.root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(REPOSITORY / relative, destination)

    def _write_executable(self, path: Path, contents: str) -> None:
        path.write_text(contents)
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def _write_fake_tools(self) -> None:
        self._write_executable(
            self.bin / "mise",
            """#!/bin/bash
printf 'mise %s\\n' "$*" >>"$TOOL_LOG"
exit "${MISE_STATUS:-0}"
""",
        )
        self._write_executable(
            self.bin / "xcodebuild",
            """#!/bin/bash
printf 'xcodebuild %s\\n' "$*" >>"$TOOL_LOG"
case " $* " in
  *" -showBuildSettings "*)
    printf '    BUILT_PRODUCTS_DIR = /tmp/fixture-products\\n'
    exit "${SHOW_SETTINGS_STATUS:-0}"
    ;;
esac
case " $* " in
  *" build-for-testing "*) exit "${BUILD_STATUS:-0}" ;;
esac
result=""
previous=""
for argument in "$@"; do
  if [ "$previous" = "-resultBundlePath" ]; then
    result="$argument"
    mkdir -p "$result"
  fi
  previous="$argument"
done
case "${XCODE_OUTPUT:-passing}" in
  passing)
    printf '◇ Suite ValueTests started\\n'
    printf '◇ Test works() started\\n'
    printf '✔ Test works() passed after 0.001 seconds\\n'
    ;;
  failed)
    printf '◇ Suite ValueTests started\\n'
    printf '◇ Test fails() started\\n'
    printf '✘ Test fails() failed after 0.001 seconds\\n'
    ;;
  zero) printf '** TEST SUCCEEDED **\\n' ;;
  invalid-bytes)
    /usr/bin/printf '\\377split output\\n'
    printf '◇ Test works() started\\n'
    printf '✔ Test works() passed after 0.001 seconds\\n'
    ;;
  hang)
    printf '%s\\n' "$$" >"$XCODE_PID_FILE"
    trap 'printf INT >"$XCODE_EXIT_MARKER"; exit 130' INT
    trap 'printf TERM >"$XCODE_EXIT_MARKER"; exit 143' TERM
    if [ "${SPAWN_GRANDCHILD:-0}" = 1 ]; then
      /usr/bin/python3 "$SIGNAL_CHILD_SCRIPT" \
        "$XCODE_GRANDCHILD_PID_FILE" "$XCODE_GRANDCHILD_EXIT_MARKER" &
    fi
    while :; do
      printf 'xcodebuild still running\\n'
      /bin/sleep 0.02
    done
    ;;
esac
exit "${TEST_STATUS:-0}"
""",
        )
        self._write_executable(
            self.bin / "xcrun",
            """#!/bin/bash
printf 'xcrun %s\\n' "$*" >>"$TOOL_LOG"
if [ "${XCRUN_OUTPUT:-valid}" = malformed ]; then
  printf '{'
  exit 0
fi
path=""
previous=""
for argument in "$@"; do
  if [ "$previous" = "--path" ]; then path="$argument"; fi
  previous="$argument"
done
if [[ "$path" == *tight* ]]; then
  results='["Passed", "Failed"]'
elif [[ "$path" == *suite* ]]; then
  results='["Failed"]'
elif [ "${XCRUN_RESULT:-passed}" = failed ]; then
  results='["Failed"]'
else
  results='["Passed"]'
fi
/usr/bin/python3 -c '
import json, sys
results = json.loads(sys.argv[1])
children = [
    {"nodeType": "Test Case", "name": "works()", "nodeIdentifier": "ValueTests/works()", "result": result, "durationInSeconds": 0.01}
    for result in results
]
print(json.dumps({"testNodes": [{"nodeType": "Unit test bundle", "name": "CoreTests", "children": [{"nodeType": "Test Suite", "name": "ValueTests", "children": children}]}]}))
' "$results"
""",
        )


class XcodeCommandContractTests(unittest.TestCase):
    def fixture(self):
        temporary = tempfile.TemporaryDirectory(prefix="stuff-xcode-contract-")
        self.addCleanup(temporary.cleanup)
        return XcodeCommandFixture(temporary.name)

    def test_test_preserves_xcode_failure_through_the_progress_pipeline(self):
        fixture = self.fixture()

        result = fixture.run(
            "test",
            "--skip-architecture",
            "--no-generate",
            "--no-build",
            "CoreTests",
            TEST_STATUS="41",
            XCODE_OUTPUT="failed",
            XCRUN_RESULT="failed",
        )

        self.assertEqual(41, result.returncode, result.stdout + result.stderr)
        self.assertIn("1 tests", result.stdout)
        self.assertIn("1 failed", result.stdout)
        self.assertIn("Failed (exit 41)", result.stdout)

    def test_test_rejects_a_successful_xcode_run_that_matched_zero_tests(self):
        fixture = self.fixture()

        result = fixture.run(
            "test",
            "--skip-architecture",
            "--no-generate",
            "--no-build",
            "CoreTests",
            XCODE_OUTPUT="zero",
        )

        self.assertEqual(1, result.returncode, result.stdout + result.stderr)
        self.assertIn("this run matched no tests", result.stdout)

    def test_test_tolerates_unexpected_output_bytes_without_losing_test_counts(self):
        fixture = self.fixture()

        result = fixture.run(
            "test",
            "--skip-architecture",
            "--no-generate",
            "--no-build",
            "CoreTests",
            XCODE_OUTPUT="invalid-bytes",
        )

        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("1 tests", result.stdout)

    def test_test_surfaces_a_progress_process_failure_after_xcode_succeeds(self):
        fixture = self.fixture()
        fixture._write_executable(
            fixture.bin / "python3",
            """#!/bin/bash
if [[ " $* " == *" Tools/test_runner.py progress "* ]]; then
  /bin/cat >/dev/null
  exit 52
fi
exec /usr/bin/python3 "$@"
""",
        )

        result = fixture.run(
            "test",
            "--skip-architecture",
            "--no-generate",
            "--no-build",
            "CoreTests",
        )

        self.assertEqual(52, result.returncode, result.stdout + result.stderr)
        self.assertIn("Failed (exit 52)", result.stdout)

    def test_test_keeps_legacy_last_scope_selector_precedence(self):
        bundles_last = self.fixture()
        result = bundles_last.run(
            "test",
            "--skip-architecture",
            "--no-generate",
            "--no-build",
            "--all",
            "CoreTests",
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("-only-testing:CoreTests", bundles_last.command_log())

        all_last = self.fixture()
        result = all_last.run(
            "test",
            "--skip-architecture",
            "--no-generate",
            "--no-build",
            "CoreTests",
            "--all",
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertNotIn("-only-testing:CoreTests", all_last.command_log())
        self.assertIn("-scheme Stuff-iOS-Tests", all_last.command_log())

        snapshots_last = self.fixture()
        result = snapshots_last.run(
            "test",
            "--skip-architecture",
            "--no-generate",
            "--no-build",
            "--all",
            "--snapshots",
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("-scheme StuffSnapshotTests", snapshots_last.command_log())

    def test_public_usage_errors_do_not_reach_xcode_dependencies(self):
        scenarios = [
            ("test", ("--unknown",)),
            ("test", ("--device",)),
            ("profile", ("--unknown",)),
            ("profile", ("--top",)),
            ("flaky", ("--unknown",)),
            ("flaky", ("--iterations",)),
        ]
        for command, arguments in scenarios:
            with self.subTest(command=command, arguments=arguments):
                fixture = self.fixture()
                result = fixture.run(command, *arguments)

                self.assertNotEqual(0, result.returncode)
                self.assertEqual("", fixture.command_log())

    def test_unlaunchable_xcodebuild_surfaces_shell_compatible_status(self):
        fixture = self.fixture()
        fixture._write_executable(
            fixture.bin / "xcodebuild",
            "#!/missing/interpreter\n",
        )

        result = fixture.run(
            "test",
            "--skip-architecture",
            "--no-generate",
            "--no-build",
            "CoreTests",
        )

        self.assertEqual(126, result.returncode, result.stdout + result.stderr)

    def test_ctrl_c_and_a_closed_output_pipe_leave_no_xcode_processes(self):
        for interruption in ("interrupt", "closed-pipe"):
            with self.subTest(interruption=interruption):
                fixture = self.fixture()
                child_pid = fixture.root / f"{interruption}-xcode.pid"
                grandchild_pid = fixture.root / f"{interruption}-grandchild.pid"
                xcode_exit = fixture.root / f"{interruption}-xcode-exit"
                grandchild_exit = fixture.root / f"{interruption}-grandchild-exit"
                environment = fixture.environment(
                    {
                        "XCODE_OUTPUT": "hang",
                        "XCODE_PID_FILE": str(child_pid),
                        "XCODE_GRANDCHILD_PID_FILE": str(grandchild_pid),
                        "XCODE_EXIT_MARKER": str(xcode_exit),
                        "XCODE_GRANDCHILD_EXIT_MARKER": str(grandchild_exit),
                        "SIGNAL_CHILD_SCRIPT": str(fixture.root / "signal_child.py"),
                        "SPAWN_GRANDCHILD": "1" if interruption == "interrupt" else "0",
                    }
                )
                process = subprocess.Popen(
                    [
                        str(fixture.root / "test"),
                        "--skip-architecture",
                        "--no-generate",
                        "--no-build",
                        "--heartbeat",
                        "0.05",
                        "CoreTests",
                    ],
                    cwd=fixture.outside,
                    env=environment,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    start_new_session=True,
                )
                try:
                    expected_pids = [child_pid]
                    if interruption == "interrupt":
                        expected_pids.append(grandchild_pid)
                    self._wait_until(lambda: all(path.exists() for path in expected_pids))
                    pids = [int(path.read_text()) for path in expected_pids]
                    if interruption == "interrupt":
                        os.killpg(process.pid, signal.SIGINT)
                    else:
                        process.stdout.close()

                    process.wait(timeout=8)
                    normalized_status = (
                        128 - process.returncode
                        if process.returncode < 0
                        else process.returncode
                    )
                    if interruption == "interrupt":
                        self.assertEqual(130, normalized_status)
                        self._wait_until(lambda: grandchild_exit.exists())
                        self.assertEqual(str(signal.SIGINT.value), grandchild_exit.read_text())
                    else:
                        self.assertNotEqual(0, normalized_status)
                        self._wait_until(lambda: not self._pid_exists(pids[0]))
                finally:
                    if process.poll() is None:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=5)
                    if process.stdout and not process.stdout.closed:
                        process.stdout.close()
                    if process.stderr and not process.stderr.closed:
                        process.stderr.close()

    def _wait_until(self, predicate, timeout=8):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.01)
        self.fail("condition did not become true before the deadline")

    def _pid_exists(self, pid):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return False
        return True

    def test_profile_preserves_test_failure_but_tolerates_report_failure(self):
        fixture = self.fixture()
        failed = fixture.run(
            "profile",
            "--tests-only",
            "--no-snapshots",
            TEST_STATUS="37",
            XCODE_OUTPUT="failed",
        )

        self.assertEqual(37, failed.returncode, failed.stdout + failed.stderr)
        self.assertIn("unit-test leg", failed.stderr)

        malformed = fixture.run(
            "profile",
            "--tests-only",
            "--no-snapshots",
            XCRUN_OUTPUT="malformed",
        )

        self.assertEqual(0, malformed.returncode, malformed.stdout + malformed.stderr)
        self.assertIn("warning: couldn't parse test results", malformed.stderr)
        self.assertIn("PROFILE WALLS", malformed.stdout)

    def test_flaky_treats_test_failures_as_data_and_build_failures_as_fatal(self):
        fixture = self.fixture()
        observations = fixture.run(
            "flaky",
            "--suite-runs",
            "1",
            "--iterations",
            "2",
            "--no-update",
            TEST_STATUS="65",
            XCODE_OUTPUT="failed",
        )

        self.assertEqual(0, observations.returncode, observations.stdout + observations.stderr)
        self.assertIn("1 flaky test(s) detected", observations.stdout)
        self.assertIn("CoreTests/ValueTests/works()", observations.stdout)

        build_failure = fixture.run(
            "flaky",
            "--suite-runs",
            "1",
            "--iterations",
            "2",
            "--no-update",
            BUILD_STATUS="29",
        )

        self.assertEqual(29, build_failure.returncode, build_failure.stdout + build_failure.stderr)
        self.assertIn("build failed", build_failure.stderr)


if __name__ == "__main__":
    unittest.main()
