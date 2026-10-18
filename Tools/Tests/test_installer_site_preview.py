from contextlib import redirect_stderr, redirect_stdout
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from Tools.InstallerKit.installer_site_preview import main
from Tools.repository import repository_root


class InstallerSitePreviewTests(unittest.TestCase):
    def test_help_and_invalid_fixture_do_not_require_node_or_mise(self):
        command = [sys.executable, "-m", "Tools.InstallerKit.installer_site_preview"]
        for arguments, expected in ((["--help"], 0), (["dev", "--fixture", "unknown"], 2)):
            with tempfile.TemporaryDirectory() as temporary:
                result = subprocess.run([*command, *arguments], cwd=temporary,
                                        env={"PATH": "/usr/bin:/bin", "PYTHONPATH": str(repository_root(__file__))}, capture_output=True, text=True)
            self.assertEqual(result.returncode, expected)
            self.assertNotIn("Traceback", result.stderr)

    def test_public_preview_command_finds_mise_with_minimal_path_and_propagates_server_exit(self):
        command = [sys.executable, "-m", "Tools.InstallerKit.installer_site_preview"]
        with tempfile.TemporaryDirectory(prefix="preview ü ") as temporary:
            root = Path(temporary)
            fake = root / "mise data/bin/mise"
            fake.parent.mkdir(parents=True)
            fake.write_text(f'#!{sys.executable}\n' + '''import json, os, sys
from pathlib import Path
source = Path(os.environ["INSTALLER_SITE_DATA"])
data = json.loads(source.read_text())
Path(os.environ["PREVIEW_TEST_LOG"]).write_text(json.dumps({
    "data": data, "arguments": sys.argv[1:], "workspace": str(source.parent),
    "public": (Path(os.environ["INSTALLER_SITE_PUBLIC"]) / "updates.json").is_file()
}))
sys.exit(17)
''')
            fake.chmod(0o755)
            log = root / "preview.json"
            result = subprocess.run([*command, "dev", "--fixture", "empty", "--port", "4444"],
                                    cwd=root, env={**os.environ, "PATH": "/usr/bin:/bin", "MISE_DATA_DIR": str(fake.parent.parent),
                                                   "PREVIEW_TEST_LOG": str(log), "PYTHONPATH": str(repository_root(__file__))}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 17, result.stderr)
            value = json.loads(log.read_text())
            self.assertEqual(value["arguments"][:4], ["exec", "node", "--", "node"])
            self.assertEqual(value["data"]["apps"], [])
            self.assertTrue(value["public"])
            self.assertIn("dev", value["arguments"])
            self.assertIn("--ignore-lock", value["arguments"])
            self.assertIn("4444", value["arguments"])
            self.assertIn("http://localhost:4444/Stuff/", result.stdout)
            self.assertFalse(Path(value["workspace"]).exists())

    def test_production_preview_builds_before_serving_and_stops_on_build_failure(self):
        with patch("Tools.InstallerKit.installer_site_preview.build_astro", side_effect=ValueError("template failed")) as build, \
                patch("Tools.InstallerKit.installer_site_preview.subprocess.run") as serve, \
                redirect_stderr(io.StringIO()) as stderr:
            self.assertEqual(main(["preview"]), 1)
        build.assert_called_once()
        serve.assert_not_called()
        self.assertIn("template failed", stderr.getvalue())

    def test_interrupt_returns_130_and_removes_temporary_inputs(self):
        workspaces = []
        def interrupt(*args, **kwargs):
            workspaces.append(Path(kwargs["env"]["INSTALLER_SITE_WORKSPACE"]))
            raise KeyboardInterrupt
        with patch("Tools.InstallerKit.installer_site_preview.subprocess.run", side_effect=interrupt), redirect_stdout(io.StringIO()):
            self.assertEqual(main(["dev"]), 130)
        self.assertEqual(len(workspaces), 1)
        self.assertFalse(workspaces[0].exists())
