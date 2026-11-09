"""Exercise IDE bootstrap without installing tools or changing Git config."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from Tools.repository import repository_root


class IdeCommandTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="ide command ü ")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name).resolve()
        self.checkout = root / "Stuff with spaces"
        self.bin = root / "bin"
        self.brew_bin = root / "brew bin"
        self.checkout.mkdir()
        self.bin.mkdir()
        self.brew_bin.mkdir()
        (self.bin / "cat").symlink_to("/bin/cat")
        (self.bin / "dirname").symlink_to("/usr/bin/dirname")
        shutil.copy2(repository_root(__file__) / "ide", self.checkout)
        self.log = root / "commands.log"
        self.env = {
            "HOME": str(root),
            "PATH": str(self.bin),
            "COMMAND_LOG": str(self.log),
            "BREW_BIN": str(self.brew_bin),
        }
        self.stub("git", 'printf "git %s\n" "$*" >> "$COMMAND_LOG"\n')
        self.stub("mise", 'printf "mise %s\n" "$*" >> "$COMMAND_LOG"\n')
        self.stub("xcode-select", 'echo "/Applications/Xcode.app/Contents/Developer"\n')
        self.stub("xcodebuild", "exit 0\n")
        self.stub("curl", "exit 99\n")
        self.stub(
            "brew",
            'printf "brew %s\n" "$*" >> "$COMMAND_LOG"\n'
            'case "$1" in\n'
            '  shellenv) printf "export PATH=%q:\\$PATH\n" "$BREW_BIN" ;;\n'
            "  install)\n"
            '    [ "$2" != "${FAIL_FORMULA:-}" ] || exit 42\n'
            '    /bin/ln -s /usr/bin/true "$BREW_BIN/${2##*/}" ;;\n'
            "  *) exit 99 ;;\n"
            "esac\n",
        )

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\n" + body)
        path.chmod(0o755)

    def run_ide(self, *arguments):
        return subprocess.run(
            [str(self.checkout / "ide"), *arguments],
            cwd=self.checkout.parent,
            env=self.env,
            capture_output=True,
            text=True,
            timeout=20,
        )

    def test_bootstrap_installs_missing_tools_before_enabling_hooks(self):
        result = self.run_ide("--bootstrap", "--no-open")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("==> brew install schpet/tap/linear", result.stdout)
        self.assertEqual(
            self.log.read_text().splitlines(),
            [
                "brew shellenv bash",
                "brew install git-lfs",
                "brew install gh",
                "brew install circleci",
                "brew install cloc",
                "brew install schpet/tap/linear",
                "git lfs install --local --skip-repo",
                "git config core.hooksPath .githooks",
                "mise trust",
                "mise install",
                "git lfs pull",
                "mise exec -- bundle install",
                "mise exec -- npm ci",
                "mise exec -- ./sync-agents --install",
                "mise exec -- tuist generate --no-open",
            ],
        )

        self.log.unlink()
        result = self.run_ide("--bootstrap", "--no-open")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("brew install", self.log.read_text())

    def test_install_failure_stops_bootstrap_before_enabling_hooks(self):
        self.env["FAIL_FORMULA"] = "git-lfs"

        result = self.run_ide("--bootstrap", "--no-open")

        self.assertEqual(result.returncode, 42)
        self.assertEqual(
            self.log.read_text(), "brew shellenv bash\nbrew install git-lfs\n"
        )

    def test_plain_ide_with_missing_git_lfs_points_to_bootstrap(self):
        result = self.run_ide("--no-open")

        self.assertEqual(result.returncode, 1)
        self.assertIn("Run ./ide --bootstrap", result.stderr)
        self.assertFalse(self.log.exists())

    def test_help_runs_without_tools(self):
        (self.brew_bin / "cat").symlink_to("/bin/cat")
        self.env["PATH"] = str(self.brew_bin)

        result = self.run_ide("--help")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Usage: ./ide", result.stdout)
        self.assertFalse(self.log.exists())

    def test_bootstrap_checks_xcode_before_installing_tools(self):
        self.stub("xcodebuild", "exit 1\n")

        result = self.run_ide("--bootstrap", "--no-open")

        self.assertEqual(result.returncode, 1)
        self.assertIn("a full Xcode installation is required", result.stderr)
        self.assertFalse(self.log.exists())
