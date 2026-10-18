"""Exercise the real post-build stamp in an isolated checkout and product plist."""

from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

from Tools.repository import repository_root


SCRIPT = repository_root(__file__) / "Tools/InstallerKit/stamp-installer-info.sh"


@unittest.skipUnless(sys.platform == "darwin", "Requires the Xcode host's PlistBuddy")
class StampInstallerInfoTests(unittest.TestCase):
    def test_signed_fields_are_generic_and_local_rebuild_clears_ci_identity(self):
        with tempfile.TemporaryDirectory(prefix="installer stamp ü ") as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            def git(*args):
                return subprocess.run(["git", *args], cwd=source, text=True, capture_output=True, check=True).stdout.strip()
            git("init", "-q")
            git("config", "user.email", "fixture@example.invalid")
            git("config", "user.name", "Fixture")
            git("-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false", "commit", "--allow-empty", "-qm", "Fixture")
            sha = git("rev-parse", "HEAD")
            plist = root / "Info.plist"
            plist.write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.example.development"}))
            environment = {"PATH": "/usr/bin:/bin", "SRCROOT": str(source), "TARGET_BUILD_DIR": str(root),
                           "INFOPLIST_PATH": "Info.plist"}
            fields = {"INSTALLER_APP_ID": "example", "INSTALLER_CHANNEL": "pr-7", "INSTALLER_RUN": "12",
                      "INSTALLER_ATTEMPT": "2", "INSTALLER_FEED_URL": "https://example.org/updates.json",
                      "INSTALLER_REPOSITORY_URL": "https://github.com/fixture/Apps"}
            def stamp(extra):
                result = subprocess.run(["/bin/bash", str(SCRIPT)], cwd=root, env={**environment, **extra},
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, "")
                return plistlib.loads(plist.read_bytes())
            value = stamp(fields)
            self.assertEqual(value["InstallerAppID"], "example")
            self.assertEqual(value["InstallerGitSHA"], sha)
            self.assertEqual(value["InstallerGitStatus"], "clean")
            self.assertEqual(value["InstallerFeedURL"], fields["INSTALLER_FEED_URL"])
            self.assertEqual(value["CFBundleIdentifier"], "com.example.development")
            local = {key: fields[key] for key in ("INSTALLER_APP_ID", "INSTALLER_FEED_URL",
                                                   "INSTALLER_REPOSITORY_URL")}
            local["INSTALLER_CHANNEL"] = "local"
            value = stamp(local)
            self.assertEqual(value["InstallerChannel"], "local")
            self.assertEqual(value["InstallerRun"], "unknown")
            self.assertEqual(value["InstallerAttempt"], "unknown")
            self.assertEqual(value["InstallerAppID"], "example")
            self.assertEqual(value["InstallerFeedURL"], fields["INSTALLER_FEED_URL"])
            self.assertEqual(value["InstallerGitSHA"], sha)
            self.assertEqual(value["InstallerGitStatus"], "clean")
            value = stamp(fields)
            self.assertEqual(value["InstallerChannel"], "pr-7")
            self.assertEqual(value["InstallerRun"], "12")
            self.assertEqual(value["InstallerAttempt"], "2")
            value = stamp({})
            for key in ("InstallerAppID", "InstallerChannel", "InstallerRun", "InstallerAttempt",
                        "InstallerFeedURL", "InstallerRepositoryURL"):
                self.assertEqual(value[key], "unknown")
            (source / "untracked").write_text("dirty")
            self.assertEqual(stamp(fields)["InstallerGitStatus"], "dirty")
            self.assertEqual(stamp(local)["InstallerGitStatus"], "dirty")
