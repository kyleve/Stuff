import io
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

from Tools.flyover_distribution import main, publish
from Tools.Tests.flyover_bundle_support import SHA


class FlyoverDistributionTests(unittest.TestCase):
    def test_release_is_published_only_after_validation_and_upload(self):
        events = []
        with (
            patch(
                "Tools.flyover_distribution.unpack_bundle",
                side_effect=lambda *a: events.append("validate"),
            ),
            patch(
                "Tools.flyover_distribution.subprocess.run",
                side_effect=lambda argv, **k: events.append(argv),
            ),
        ):
            publish(Path("/tmp/atlases.zip"), "owner/repo", SHA, "1793980000000", "1")
        self.assertEqual(events[0], "validate")
        self.assertIn("--draft", events[1])
        self.assertEqual(events[2][-1], "--draft=false")
        self.assertEqual(len(events), 3)

    def test_failed_validation_or_upload_never_publishes(self):
        for validation in (True, False):
            with (
                self.subTest(validation=validation),
                patch(
                    "Tools.flyover_distribution.unpack_bundle",
                    side_effect=ValueError("invalid") if validation else None,
                ),
                patch(
                    "Tools.flyover_distribution.subprocess.run",
                    side_effect=subprocess.CalledProcessError(1, "gh"),
                ) as run,
            ):
                with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                    publish(Path("/tmp/atlases.zip"), "owner/repo", SHA, "1", "1")
                self.assertEqual(run.call_count, 0 if validation else 1)

    def test_invalid_identity_fails_before_reading_or_publishing(self):
        with patch("Tools.flyover_distribution.unpack_bundle") as unpack:
            for sha, run, attempt in [
                ("main", "1", "1"),
                (SHA, "0", "1"),
                (SHA, "1", "-2"),
            ]:
                with self.assertRaises(ValueError):
                    publish(Path("/tmp/atlases.zip"), "owner/repo", sha, run, attempt)
            unpack.assert_not_called()

    def test_command_uses_workspace_archive_and_redacts_failures(self):
        for error in (None, ValueError("Authorization: secret"), OSError("secret")):
            with (
                self.subTest(error=error),
                patch.dict("os.environ", {"GITHUB_REPOSITORY": "owner/repo"}),
                patch(
                    "Tools.flyover_distribution.publish", side_effect=error
                ) as publish_archive,
                patch("sys.stderr", new_callable=io.StringIO) as output,
            ):
                self.assertEqual(
                    main(
                        [
                            "--archive",
                            "/tmp/atlases.zip",
                            "--sha",
                            SHA,
                            "--run",
                            "1",
                            "--attempt",
                            "1",
                        ]
                    ),
                    0 if error is None else 1,
                )
                publish_archive.assert_called_once_with(
                    Path("/tmp/atlases.zip"), "owner/repo", SHA, "1", "1"
                )
                self.assertNotIn("secret", output.getvalue())
                if error:
                    self.assertIn(type(error).__name__, output.getvalue())
