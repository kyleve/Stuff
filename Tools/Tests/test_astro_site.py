import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from Tools.astro_site import astro_command, resolve_mise, stage_workspace


class AstroMiseResolutionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="mise installations ü ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.home = self.root / "home"
        self.system_paths = (self.root / "opt/homebrew/bin/mise", self.root / "usr/local/bin/mise")
        for replacement in (
            patch.dict(os.environ, {"PATH": "/usr/bin:/bin"}, clear=True),
            patch("Tools.astro_site.Path.home", return_value=self.home),
            patch("Tools.astro_site.SYSTEM_MISE_PATHS", self.system_paths),
        ):
            replacement.start()
            self.addCleanup(replacement.stop)

    def install(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/bin/sh\nexit 0\n")
        path.chmod(0o755)
        return path

    def test_path_installation_takes_precedence_over_fallbacks(self):
        preferred = self.install(self.root / "path/bin/mise")
        self.install(self.home / ".local/share/mise/bin/mise")
        self.install(self.root / "configured/bin/mise")
        os.environ.update({"PATH": str(preferred.parent), "MISE_DATA_DIR": str(self.root / "configured")})
        self.assertEqual(resolve_mise(), str(preferred))

    def test_mise_action_installation_is_found_with_minimal_path(self):
        installed = self.install(self.home / ".local/share/mise/bin/mise")
        self.assertEqual(resolve_mise(), str(installed))

    def test_local_installer_and_both_homebrew_layouts_are_supported(self):
        for path in (self.home / ".local/bin/mise", *self.system_paths):
            with self.subTest(path=path):
                installed = self.install(path)
                self.assertEqual(resolve_mise(), str(installed))
                installed.unlink()

    def test_configured_data_directory_takes_precedence_over_xdg_and_default(self):
        default = self.install(self.home / ".local/share/mise/bin/mise")
        xdg = self.install(self.root / "xdg data/mise/bin/mise")
        configured = self.install(self.root / "mise data/bin/mise")
        os.environ.update({"XDG_DATA_HOME": str(self.root / "xdg data"),
                           "MISE_DATA_DIR": str(self.root / "mise data")})
        self.assertEqual(resolve_mise(), str(configured))
        del os.environ["MISE_DATA_DIR"]
        self.assertEqual(resolve_mise(), str(xdg))
        del os.environ["XDG_DATA_HOME"]
        self.assertEqual(resolve_mise(), str(default))

    def test_empty_data_directory_overrides_use_the_default(self):
        installed = self.install(self.home / ".local/share/mise/bin/mise")
        os.environ.update({"MISE_DATA_DIR": "", "XDG_DATA_HOME": ""})
        self.assertEqual(resolve_mise(), str(installed))

    def test_non_executable_files_and_directories_do_not_hide_a_usable_installation(self):
        unusable = self.install(self.home / ".local/share/mise/bin/mise")
        unusable.chmod(0o644)
        (self.home / ".local/bin/mise").mkdir(parents=True)
        installed = self.install(self.system_paths[0])
        self.assertEqual(resolve_mise(), str(installed))

    def test_missing_or_non_executable_mise_reports_setup_instructions(self):
        for present in (False, True):
            with self.subTest(present=present):
                if present:
                    self.install(self.home / ".local/share/mise/bin/mise").chmod(0o644)
                with self.assertRaisesRegex(ValueError, r"mise is required.*\./ide --bootstrap --no-open"):
                    resolve_mise()


class AstroWorkspaceTests(unittest.TestCase):
    def test_sites_share_dependencies_without_sharing_generated_state(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'node_modules/.bin').mkdir(parents=True)
            (root / 'node_modules/.bin/astro').write_text('fixture')
            site = root / 'site ü'
            site.mkdir()
            for name in ('package.json', 'tsconfig.json', 'astro.config.mjs'):
                (site / name).write_text('{}')
            with patch('Tools.astro_site.SOURCE_ROOT', root), patch('Tools.astro_site.resolve_mise', return_value='/pinned/mise'):
                for name in ('first', 'second'):
                    workspace = root / name
                    workspace.mkdir()
                    stage_workspace(site, workspace)
                    self.assertEqual((workspace / 'node_modules').resolve(), (root / 'node_modules').resolve())
                    self.assertEqual((workspace / 'package.json').resolve(), (site / 'package.json').resolve())
                    command = astro_command(site, workspace, 'build')
                    self.assertEqual(command[:4], ['/pinned/mise', 'exec', 'node', '--'])
                    self.assertIn(str(workspace), command)

    def test_missing_dependencies_report_the_shared_install_command(self):
        with tempfile.TemporaryDirectory() as temporary, patch('Tools.astro_site.SOURCE_ROOT', Path(temporary)):
            with self.assertRaisesRegex(ValueError, 'mise exec -- npm ci'):
                astro_command(Path(temporary), Path(temporary), 'build')
