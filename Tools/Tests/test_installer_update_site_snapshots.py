from contextlib import redirect_stderr
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from Tools.Tests.Fixtures.installer_update_site_snapshots import main, offline_html, pages
from Tools.Tests.Fixtures.installer_update_fixtures import catalog, REPO, FEED_URL
from Tools.InstallerKit.installer_update_site import render_site
from Tools.repository import repository_root


class InstallerUpdateSiteSnapshotsTests(unittest.TestCase):
    def test_command_generates_current_production_html_and_replaces_old_fixtures(self):
        command = [sys.executable, "-m", "Tools.Tests.Fixtures.installer_update_site_snapshots"]
        with tempfile.TemporaryDirectory(prefix="site snapshots ü ") as temporary:
            output = Path(temporary) / "bundle resources" / "pages.json"
            args = [*command, "--output", str(output)]
            environment = {"PATH": "/usr/bin:/bin", "PYTHONDONTWRITEBYTECODE": "1", "PYTHONPATH": str(repository_root(__file__))}
            result = subprocess.run(args, cwd=temporary, env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
            self.assertIn("Generated", result.stdout)
            self.assertEqual(json.loads(output.read_text()), pages())
            output.write_text("outdated")
            self.assertEqual(subprocess.run(args, cwd=temporary, env=environment,
                                            capture_output=True).returncode, 0)
            self.assertEqual(json.loads(output.read_text()), pages())
            help_result = subprocess.run([*command, "--help"], cwd=temporary,
                                         env=environment, capture_output=True, text=True)
            self.assertEqual(help_result.returncode, 0)
            self.assertIn("--output", help_result.stdout)

    def test_failed_replacement_preserves_previous_fixtures_and_removes_staging(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "pages.json"
            output.write_text("previous fixtures")
            with patch("Tools.Tests.Fixtures.installer_update_site_snapshots.os.replace", side_effect=OSError("disk full")), \
                    redirect_stderr(io.StringIO()) as stderr:
                self.assertEqual(main(["--output", str(output)]), 1)
            self.assertIn("disk full", stderr.getvalue())
            self.assertEqual(output.read_text(), "previous fixtures")
            self.assertEqual(list(Path(temporary).iterdir()), [output])

    def test_state_matrix_contains_real_installs_retirement_and_empty_states(self):
        fixtures = {page["name"]: page["html"] for page in pages()}
        self.assertEqual(set(fixtures), {"Index", "App", "Channel", "Retired", "Empty", "UnavailableHistory", "MissingDetails"})
        self.assertIn("itms-services:", fixtures["Channel"])
        self.assertIn("Retain complete release notes", fixtures["Channel"])
        self.assertNotIn("itms-services:", fixtures["Retired"])
        self.assertNotIn("itms-services:", fixtures["Empty"])
        self.assertIn("Complete commit history is unavailable", fixtures["UnavailableHistory"])
        self.assertIn("Not recorded", fixtures["MissingDetails"])
        self.assertIn('class="app-icon placeholder"', fixtures["MissingDetails"])

    def test_offline_fixtures_inline_exact_production_artwork_for_both_appearances(self):
        import base64
        files = render_site(catalog(), REPO, FEED_URL)
        html = offline_html(files, "index.html")
        assets = {path: data for path, data in files.items() if path.startswith("assets/")}
        self.assertEqual(len(assets), 2)
        for path, data in assets.items():
            self.assertNotIn(FEED_URL[:-len("updates.json")] + path, html)
            self.assertIn("data:image/png;base64," + base64.b64encode(data).decode(), html)
