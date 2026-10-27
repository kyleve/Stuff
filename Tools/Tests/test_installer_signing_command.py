"""The CI lifecycle wrapper selects the locked bundle and pinned Ruby after dependency-free guards."""

from pathlib import Path
import subprocess
import tempfile
import unittest
from Tools.repository import repository_root


class InstallerSigningCommandTests(unittest.TestCase):
    def test_invalid_command_and_local_use_do_not_access_credentials(self):
        command = repository_root(Path(__file__)) / ".github/installer-signing.sh"
        for arguments, message in (([], "Usage:"), (["prepare"], "CircleCI")):
            result = subprocess.run(
                ["/bin/bash", str(command), *arguments],
                cwd="/tmp",
                env={"PATH": "/usr/bin:/bin"},
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(message, result.stderr)

    def test_locked_bundle_runs_from_control_checkout_and_preserves_status(self):
        root = repository_root(Path(__file__))
        with tempfile.TemporaryDirectory(prefix="signing wrapper ü ") as temporary:
            directory = Path(temporary)
            mise = directory / "mise"
            mise.write_text(
                '#!/bin/bash\nprintf "%s\\n" "$PWD" "$BUNDLE_GEMFILE" "$BUNDLE_PATH" "$BUNDLE_FROZEN" "$@" > "$LOG"\nexit 47\n'
            )
            mise.chmod(0o755)
            log = directory / "log"
            result = subprocess.run(
                ["/bin/bash", str(root / ".github/installer-signing.sh"), "prepare"],
                cwd="/tmp",
                env={
                    "PATH": f"{directory}:/usr/bin:/bin",
                    "CIRCLECI": "true",
                    "LOG": str(log),
                    "BUNDLE_GEMFILE": "/wrong/Gemfile",
                    "BUNDLE_PATH": "/wrong/bundle",
                    "BUNDLE_FROZEN": "false",
                },
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 47)
            self.assertEqual(
                log.read_text().splitlines(),
                [
                    str(root),
                    str(root / "Gemfile"),
                    str(root / "vendor/bundle"),
                    "true",
                    "exec",
                    "--",
                    "bundle",
                    "exec",
                    "ruby",
                    str(root / "Tools/InstallerKit/signing_state.rb"),
                    "prepare",
                ],
            )

    def test_cleanup_before_prepare_needs_no_runtime(self):
        root = repository_root(Path(__file__))
        with tempfile.TemporaryDirectory() as temporary:
            result = subprocess.run(
                ["/bin/bash", str(root / ".github/installer-signing.sh"), "cleanup"],
                cwd="/tmp",
                env={
                    "PATH": "/usr/bin:/bin",
                    "CIRCLECI": "true",
                    "INSTALLER_SIGNING_DIR": str(Path(temporary) / "absent"),
                },
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
