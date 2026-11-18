"""Protect trace accounting before using it to choose settling experiments."""

import contextlib
from copy import deepcopy
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from uuid import uuid4

from Tools import snapshot_settle_profile as profile


def trace(capture_id=None, ordinal=1):
    return {
        "version": 1,
        "captureID": capture_id or str(uuid4()),
        "id": "same-label",
        "ordinal": ordinal,
        "reason": "content",
        "mechanism": "pixel",
        "captureOffset": 0.1,
        "minimumDuration": 0.25,
        "maximumDuration": 2.5,
        "quietDuration": 0.12,
        "elapsed": 0.27,
        "outcome": "settled",
        "interruptedSleep": 0.0,
        "passes": [
            {
                "index": index,
                "sampleAt": at,
                "sleepRequested": 0.016,
                "sleepActual": 0.02,
                "layout": 0.001,
                "render": 0.03,
                "pixelCheck": 0.002,
                "event": "anchor" if index == 1 else "matching",
                "pixelStable": index > 1,
                "stable": index > 1,
                "floorMet": index == 3,
            }
            for index, at in enumerate((0.06, 0.19, 0.26), 1)
        ],
    }


def capture(rows):
    return {
        "captureID": rows[0]["captureID"],
        "id": rows[0]["id"],
        "settleCalls": len(rows),
        "settlePasses": sum(len(row["passes"]) for row in rows),
    }


class SnapshotSettleProfileTests(unittest.TestCase):
    def test_duplicate_labels_and_retry_calls_reconcile_by_owner_and_ordinal(self):
        first = trace()
        first["outcome"] = "timedOut"
        first["passes"][-1].update(event="changed", stable=False, pixelStable=False)
        retried = trace(first["captureID"], 2)
        other = trace()
        report = profile.summarize(
            [first, retried, other], [capture([first, retried]), capture([other])]
        )
        self.assertTrue(report["reconciled"])
        self.assertEqual(report["captures"], 2)
        self.assertEqual(report["total"]["calls"], 3)
        self.assertEqual(report["total"]["passes"], 9)
        self.assertEqual(report["total"]["outcomes"], {"timedOut": 1, "settled": 2})
        self.assertEqual(report["total"]["callsWithoutObservedChanges"], 2)
        self.assertEqual(report["total"]["samplesBlockedOnlyByFloor"], 3)
        self.assertEqual(report["total"]["samplesBlockedOnlyByProof"], 1)
        self.assertEqual(report["total"]["samplesBlockedByBoth"], 3)
        self.assertAlmostEqual(report["total"]["operations"]["render"], 0.27)
        self.assertAlmostEqual(report["total"]["unattributed"], 0.333)

    def test_nonpixel_calls_are_not_reported_as_unchanging_pixels(self):
        row = trace()
        row["mechanism"] = "quiescence"
        for sample in row["passes"]:
            sample.pop("event")
            sample.pop("pixelStable")
        report = profile.summarize([row], [capture([row])])
        self.assertEqual(report["total"]["callsWithoutObservedChanges"], 0)
        self.assertEqual(report["total"]["quiescenceCalls"], 1)

    def test_missing_calls_pass_mismatches_and_orphans_are_explicit(self):
        first, second, orphan = trace(), trace(), trace()
        missing = capture([first])
        missing["settleCalls"] = 2
        wrong_passes = capture([second])
        wrong_passes["settlePasses"] += 1
        report = profile.summarize([first, second, orphan], [missing, wrong_passes])
        self.assertFalse(report["complete"])
        self.assertEqual(len(report["incompleteCaptures"]), 2)
        self.assertEqual(report["orphanedOwners"], [orphan["captureID"]])
        self.assertEqual(report["total"]["calls"], 3)

    def test_invalid_records_and_duplicate_identities_fail(self):
        original = trace()
        mutations = [
            ("captureID", "not-a-uuid"),
            ("version", 2),
            ("version", True),
            ("reason", "unknown"),
            ("elapsed", float("nan")),
            ("ordinal", 0),
            ("elapsed", 0.01),
            ("outcome", "skipped"),
        ]
        for key, value in mutations:
            with self.subTest(key=key, value=value):
                row = {**original, key: value}
                with self.assertRaises(ValueError):
                    profile.validate_trace(row)
        for key, value in (
            ("index", 9),
            ("event", None),
            ("pixelStable", None),
            ("render", -1),
            ("render", 5),
            ("sampleAt", 1),
            ("floorMet", False),
        ):
            with self.subTest(pass_key=key, value=value):
                row = deepcopy(original)
                row["passes"][-1][key] = value
                with self.assertRaises(ValueError):
                    profile.validate_trace(row)
        with self.assertRaisesRegex(ValueError, "duplicate trace"):
            profile.summarize([original, original], [capture([original])])
        with self.assertRaisesRegex(ValueError, "duplicate capture"):
            profile.summarize([original], [capture([original]), capture([original])])

    def test_command_retains_partial_work_and_rejects_false_completion(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            log, output = root / "test.log", root / "output"
            row = trace()
            row.update(outcome="cancelled", passes=[], interruptedSleep=0.01)
            log.write_text(
                "◇ Suite Example started.\n" + profile.TRACE + json.dumps(row) + "\n"
            )
            with contextlib.redirect_stdout(io.StringIO()):
                status = profile.main(
                    [str(log), "--output-dir", str(output), "--require-complete"]
                )
            self.assertEqual(status, 1)
            retained = json.loads((output / "traces.jsonl").read_text())
            self.assertEqual(retained["outcome"], "cancelled")
            self.assertEqual(retained["suite"], "Example")
            self.assertEqual(retained["interruptedSleep"], 0.01)
            self.assertFalse(
                json.loads((output / "summary.json").read_text())["complete"]
            )

    def test_every_log_requires_terminal_success_even_at_a_capture_boundary(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            logs = [root / "first.log", root / "second.log"]
            for log in logs:
                row = trace()
                log.write_text(
                    profile.TRACE
                    + json.dumps(row)
                    + "\n"
                    + profile.TIMING
                    + json.dumps(capture([row]))
                    + "\n"
                )
            for markers, expected in (
                (["", ""], 1),
                (["** TEST SUCCEEDED **", ""], 1),
                (["** TEST SUCCEEDED **", "** TEST EXECUTE SUCCEEDED **"], 0),
            ):
                for log, marker in zip(logs, markers):
                    if marker:
                        with log.open("a") as stream:
                            stream.write(marker + "\nTesting started\n")
                with contextlib.redirect_stdout(io.StringIO()):
                    status = profile.main(
                        [
                            *(str(log) for log in logs),
                            "--output-dir",
                            str(root / "output"),
                            "--require-complete",
                        ]
                    )
                self.assertEqual(status, expected)
                report = json.loads((root / "output/summary.json").read_text())
                self.assertTrue(report["reconciled"])
            # A completed earlier run cannot bless subsequently appended work.
            row = trace()
            with logs[1].open("a") as stream:
                stream.write(
                    profile.TRACE
                    + json.dumps(row)
                    + "\n"
                    + profile.TIMING
                    + json.dumps(capture([row]))
                    + "\n"
                )
            traces, captures, runs = profile.parse_logs(logs)
            report = profile.summarize(traces, captures, runs)
            self.assertTrue(report["reconciled"])
            self.assertFalse(report["complete"])

    def test_native_log_suffix_preserves_the_complete_command_report(self):
        native = (
            "2026-11-17 18:19:49.998850-0800 StuffTestHost[6147:23346] "
            "[Where] [reporting/PresenceCalendar] ◀ layoutYear succeeded (0:00:00)"
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "trace results ü"
            root.mkdir()
            log, output = root / "test.log", root / "output"
            row = trace()
            for appended_to in (profile.TRACE, profile.TIMING):
                with self.subTest(appended_to=appended_to):
                    lines = ["◇ Suite Example started."]
                    for prefix, value in (
                        (profile.TRACE, row),
                        (profile.TIMING, capture([row])),
                    ):
                        lines.append(
                            prefix
                            + json.dumps(value)
                            + (native if prefix == appended_to else "")
                        )
                    lines.append("** TEST EXECUTE SUCCEEDED **")
                    log.write_text("\n".join(lines) + "\n")
                    result = subprocess.run(
                        [
                            sys.executable,
                            str(Path(profile.__file__).resolve()),
                            str(log),
                            "--output-dir",
                            str(output),
                            "--require-complete",
                        ],
                        cwd=root,
                        capture_output=True,
                        text=True,
                        check=False,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stderr, "")
                    self.assertTrue(result.stdout)
                    report = json.loads((output / "summary.json").read_text())
                    self.assertTrue(report["complete"])
                    self.assertEqual(report["captures"], 1)
                    self.assertEqual(report["total"]["calls"], 1)
                    self.assertEqual(report["total"]["passes"], 3)

    def test_native_message_inside_json_still_fails_the_command(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            log, output = root / "split.log", root / "output"
            row = json.dumps(trace())
            split_at = row.index('"pixelStable"')
            log.write_text(
                "2026-11-17 18:38:33.178611-0800 "
                + profile.TRACE
                + row[:split_at]
                + "StuffTestHost[6230:23893] [Where] [SwiftDataStore] fetchSamples succeeded\n"
                + row[split_at:]
                + "\n** TEST EXECUTE SUCCEEDED **\n"
            )
            result = subprocess.run(
                [
                    sys.executable,
                    str(Path(profile.__file__).resolve()),
                    str(log),
                    "--output-dir",
                    str(output),
                    "--require-complete",
                ],
                cwd=root,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, "")
            self.assertIn("split.log:1:", result.stderr)
            self.assertFalse((output / "summary.json").exists())

    def test_trailing_corruption_or_another_record_is_not_discarded(self):
        native = "2026-11-17 18:19:49.998850-0800 StuffTestHost[6147:23346] "
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary) / "broken.log"
            row = trace()
            for prefix, value in (
                (profile.TRACE, row),
                (profile.TIMING, capture([row])),
            ):
                for suffix in (
                    "garbage",
                    "{}",
                    "42",
                    profile.TIMING + json.dumps(capture([row])),
                    native + profile.TRACE + json.dumps(row),
                    native + profile.TIMING + json.dumps(capture([row])),
                ):
                    with self.subTest(prefix=prefix, suffix=suffix):
                        log.write_text(prefix + json.dumps(value) + suffix + "\n")
                        with self.assertRaisesRegex(ValueError, "broken.log:1:"):
                            profile.parse_logs([log])

    def test_malformed_logs_report_source_and_line_instead_of_silently_skipping(self):
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary) / "broken.log"
            for text in (
                profile.TRACE + "{",
                "SNAPSHOT_SETTLE_TRACE_ERROR encoding failed",
                profile.TIMING + '{"id":"old-log"}',
            ):
                with self.subTest(text=text):
                    log.write_text("unrelated log\n" + text + "\n")
                    with self.assertRaisesRegex(ValueError, "broken.log:2:"):
                        profile.parse_logs([log])


if __name__ == "__main__":
    unittest.main()
