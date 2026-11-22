import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(".circleci/installer_snapshot_fixture.py")


class InstallerSnapshotFixtureCacheTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        subprocess.run(["git", "init", "-q", self.root], check=True)
        subprocess.run(
            ["git", "config", "core.excludesFile", os.devnull],
            cwd=self.root,
            check=True,
        )
        for path in (
            SCRIPT,
            Path("Tools/repository.py"),
            Path("Tools/InstallerKit/installer_apps.py"),
        ):
            destination = self.root / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / path, destination)
        registry = json.loads((ROOT / ".github/installer-apps.json").read_text())[:1]
        registry[0]["site"].update(icon="art/main.png", darkIcon="art/dark.png")
        self.write(".github/installer-apps.json", json.dumps(registry))
        self.write("art/main.png", "light")
        self.write("art/dark.png", "dark")
        self.write("Tools/astro_site.py", "# renderer")
        self.write(".gitignore", ".build/\nnode_modules/\n")
        self.write(
            "Tools/Tests/Fixtures/installer_update_site_snapshots.py",
            """import json, os, sys
from pathlib import Path
output = Path(sys.argv[sys.argv.index('--output') + 1])
output.write_text(json.dumps([{'name': 'Example', 'html': Path('art/main.png').read_text()}]))
if os.environ.get('FAIL_GENERATOR'):
    raise SystemExit(13)
""",
        )
        mise = self.write(
            "bin/mise",
            '#!/bin/sh\n[ "$*" = "exec -- npm ci" ] || exit 2\n'
            '[ -z "$FORBID_INSTALL" ] || exit 10\n'
            "echo install >> .build/install.log\n",
        )
        mise.chmod(0o755)
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        self.cache = self.root / ".build/installer-site-fixture"
        self.output = self.cache / "InstallerSiteSnapshots.json"
        self.receipt = self.cache / "receipt.json"

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def command(self, name, *, root=None, check=True, **environment):
        root = root or self.root
        return subprocess.run(
            [sys.executable, str(SCRIPT), name],
            cwd=root,
            env={
                **os.environ,
                "PATH": str(root / "bin") + os.pathsep + os.environ["PATH"],
                **environment,
            },
            capture_output=True,
            text=True,
            check=check,
        )

    def test_key_tracks_registered_artwork_workspace_and_generator_inputs(self):
        before = self.command("key").stdout.strip()
        self.assertRegex(before, r"^[0-9a-f]{64}$")
        self.write("Unrelated.swift", "unrelated")
        self.write(
            "Tools/InstallerKit/Site/.build/render/package.json", "ignored Astro output"
        )
        self.assertEqual(self.command("key").stdout.strip(), before)
        for name in (
            "art/main.png",
            "art/dark.png",
            "Tools/astro_site.py",
        ):
            with self.subTest(name=name):
                self.write(name, "changed")
                after = self.command("key").stdout.strip()
                self.assertNotEqual(after, before)
                before = after
        manifest = self.write("NewApp/Web/package.json", "{}")
        subprocess.run(["git", "add", manifest], cwd=self.root, check=True)
        self.assertNotEqual(self.command("key").stdout.strip(), before)

    def test_hit_across_checkouts_with_different_untracked_bytecode(self):
        bytecode = Path("Tools/InstallerKit/__pycache__/render.pyc")
        key = self.command("key").stdout
        self.write(bytecode, "first checkout")
        self.assertIn("fixture miss", self.command("prepare").stdout)
        with tempfile.TemporaryDirectory() as temporary:
            checkout = Path(temporary) / "relocated"
            shutil.copytree(self.root, checkout)
            (checkout / bytecode).write_bytes(b"second checkout")
            self.assertEqual(self.command("key", root=checkout).stdout, key)
            prepared = self.command("prepare", root=checkout, FORBID_INSTALL="1")
            self.assertIn("fixture hit", prepared.stdout)

    def test_hit_without_node_and_recovery_from_invalid_restores(self):
        self.assertIn("fixture miss", self.command("prepare").stdout)
        content = self.output.read_bytes()
        self.assertEqual(
            json.loads(self.receipt.read_text()),
            {
                "input_sha256": self.command("key").stdout.strip(),
                "output_sha256": hashlib.sha256(content).hexdigest(),
                "bytes": len(content),
            },
        )
        self.assertIn("fixture hit", self.command("prepare", FORBID_INSTALL="1").stdout)
        self.output.write_bytes(b"corrupt")
        self.assertIn("fixture miss", self.command("prepare").stdout)
        self.assertEqual(self.output.read_bytes(), content)
        self.receipt.write_text("[]")
        self.assertIn("fixture miss", self.command("prepare").stdout)
        self.receipt.write_bytes(b"invalid receipt")
        self.assertIn("fixture miss", self.command("prepare").stdout)
        self.output.unlink()
        self.assertIn("fixture miss", self.command("prepare").stdout)
        self.assertEqual(self.output.read_bytes(), content)

    def test_failed_generation_keeps_previous_pair_and_retry_uses_current_source(self):
        self.command("prepare")
        previous = self.receipt.read_bytes(), self.output.read_bytes()
        self.write("art/main.png", "new artwork")
        failed = self.command("prepare", check=False, FAIL_GENERATOR="1")
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn("exit status 13", failed.stderr)
        self.assertEqual(
            (self.receipt.read_bytes(), self.output.read_bytes()), previous
        )
        self.assertIn("fixture miss", self.command("prepare").stdout)
        self.assertEqual(json.loads(self.output.read_text())[0]["html"], "new artwork")
