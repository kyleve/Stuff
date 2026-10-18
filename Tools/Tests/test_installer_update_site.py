from contextlib import redirect_stderr, redirect_stdout
from dataclasses import replace
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from Tools.InstallerKit.github_releases import asset_url
from Tools.InstallerKit.installer_installation import manifest_url
from Tools.InstallerKit.installer_apps import AppPresentation, load_app
from Tools.InstallerKit.installer_update_site import BUILD_ROOT, build_astro, main, render_site, resolve_mise, stage_input, write_site
from Tools.repository import repository_root
from Fixtures.installer_update_fixtures import catalog, multiple_apps, FEED_URL, REPO


class InstallerMiseResolutionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="mise installations ü ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.home = self.root / "home"
        self.system_paths = (self.root / "opt/homebrew/bin/mise", self.root / "usr/local/bin/mise")
        for replacement in (
            patch.dict(os.environ, {"PATH": "/usr/bin:/bin"}, clear=True),
            patch("installer_update_site.Path.home", return_value=self.home),
            patch("installer_update_site.SYSTEM_MISE_PATHS", self.system_paths),
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


class InstallerUpdateSiteTests(unittest.TestCase):
    def test_site_feed_and_manifests_share_exact_releases_and_escape_commit_subjects(self):
        value = catalog()
        files = render_site(value, REPO, FEED_URL)
        self.assertEqual(json.loads(files["updates.json"]), value)
        self.assertIn(b"Install Where Dev", files["index.html"])
        detail = files["apps/where/pr-42/index.html"].decode()
        self.assertNotIn("<script>", detail)
        self.assertIn("&lt;script&gt;", detail)
        self.assertIn("itms-services://?action=download-manifest", detail)
        self.assertIn("manifests%2Fwhere%2Fpr-42%2F2-1.plist", detail)
        for run in (1, 2):
            item = plistlib.loads(files[f"manifests/where/pr-42/{run}-1.plist"])["items"][0]
            self.assertEqual(item["assets"][0]["url"], asset_url(REPO, "where", "pr-42", {"run": run, "attempt": 1}))

    def test_retired_channel_keeps_history_and_page_but_has_no_install_manifest(self):
        value = catalog()
        value["apps"][0]["channels"][1]["active"] = False
        files = render_site(value, REPO, FEED_URL)
        self.assertEqual(json.loads(files["updates.json"]), value)
        self.assertIn(b"Channel retired", files["apps/where/pr-42/index.html"])
        self.assertNotIn(b"itms-services", files["apps/where/pr-42/index.html"])
        self.assertFalse(any(path.startswith("manifests/where/pr-42/") for path in files))
        self.assertIn("manifests/where/main/2-1.plist", files)

    def test_untrusted_destinations_and_invalid_metadata_fail_before_output(self):
        bad_releases = ({"ipaURL": "https://evil.example/Where.ipa"},
                        {"manifestURL": "https://evil.example/manifest.plist"},
                        {"manifestURL": manifest_url(FEED_URL, "where", "main", {"run": 1, "attempt": 1})},
                        {"bundleVersion": "not-a-version"}, {"sha": "<script>"},
                        {"buildDetails": {"version": "0.9.2", "minimumOSVersion": "27", "sizeBytes": -1}},
                        {"publishedAt": '2026-10-18T00:00:00Z" onmouseover="bad'})
        for changes in bad_releases:
            with self.subTest(changes=changes), tempfile.TemporaryDirectory() as temporary:
                value = catalog()
                value["apps"][0]["channels"][0]["releases"][0].update(changes)
                path = Path(temporary) / "updates.json"
                path.write_text(json.dumps(value))
                output = Path(temporary) / "site"
                with redirect_stderr(io.StringIO()) as stderr, redirect_stdout(io.StringIO()) as stdout:
                    self.assertEqual(main(["--catalog", str(path), "--repository", REPO,
                                           "--feed-url", FEED_URL, "--output", str(output)]), 1)
                self.assertTrue(stderr.getvalue().startswith("error:"))
                self.assertEqual(stdout.getvalue(), "")
                self.assertFalse(output.exists())

    def test_failed_file_write_leaves_no_partial_deployment_and_preserves_existing_site(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "site"
            with patch.object(Path, "write_bytes", side_effect=OSError("disk full")), self.assertRaises(OSError):
                write_site({"updates.json": b"{}"}, output)
            self.assertEqual(list(Path(temporary).iterdir()), [])
            output.mkdir()
            (output / "index.html").write_text("existing")
            with self.assertRaisesRegex(ValueError, "must not exist"):
                write_site({"index.html": b"replacement"}, output)
            self.assertEqual((output / "index.html").read_text(), "existing")

    def test_public_command_handles_paths_with_spaces_and_help_outside_the_repository(self):
        command = [sys.executable, "-m", "Tools.InstallerKit.installer_update_site"]
        environment = {"PATH": "/usr/bin:/bin", "PYTHONDONTWRITEBYTECODE": "1",
                       "PYTHONPATH": str(repository_root(__file__))}
        with tempfile.TemporaryDirectory(prefix="site fixture ü ") as temporary:
            root = Path(temporary)
            help_result = subprocess.run([*command, "--help"], cwd=root,
                                         env=environment, capture_output=True, text=True)
            self.assertEqual(help_result.returncode, 0, help_result.stderr)
            self.assertIn("--catalog", help_result.stdout)
            source = root / "updates.json"
            source.write_text(json.dumps(catalog()))
            result = subprocess.run([*command, "--catalog", str(source),
                                     "--repository", REPO, "--feed-url", FEED_URL, "--output", str(root / "site")],
                                    cwd=root, env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
            self.assertIn("Prepared", result.stdout)
            self.assertTrue((root / "site/apps/where/main/index.html").is_file())
            self.assertEqual(len(list((root / "site/assets/where").glob("*.png"))), 2)

    def test_trusted_artwork_is_packaged_once_with_content_addresses_and_dark_appearance(self):
        app = load_app("where")
        files = render_site(catalog(), REPO, FEED_URL)
        source_root = repository_root(__file__)
        assets = [path for path in files if path.startswith("assets/")]
        self.assertEqual(len(assets), 2)
        for path in (app.presentation.icon, app.presentation.dark_icon):
            contents = (source_root / path).read_bytes()
            relative = f'assets/where/{hashlib.sha256(contents).hexdigest()[:16]}.png'
            self.assertEqual(files[relative], contents)
            for page in ("index.html", "apps/where/index.html", "apps/where/main/index.html"):
                self.assertIn(relative.encode(), files[page])
        self.assertIn(b'media="(prefers-color-scheme: dark)"', files["index.html"])

    def test_missing_artwork_and_older_build_details_have_explicit_fallbacks(self):
        value = catalog("example", 'Example <Dev> & "App"', "com.example.development")
        for channel in value["apps"][0]["channels"]:
            for release in channel["releases"]:
                del release["buildDetails"]
        files = render_site(value, REPO, FEED_URL)
        self.assertFalse(any(path.startswith("assets/") for path in files))
        detail = files["apps/example/main/index.html"].decode()
        self.assertIn('class="app-icon placeholder"', detail)
        self.assertIn("Not recorded", detail)
        self.assertIn("Example &lt;Dev&gt; &amp; &quot;App&quot;", detail)
        self.assertNotIn("0.9.2", detail)
        self.assertIn("itms-services:", detail)

    def test_build_information_uses_published_metadata_and_links_to_the_exact_run(self):
        detail = render_site(catalog(), REPO, FEED_URL)["apps/where/pr-42/index.html"].decode()
        for content in ("48.3 MB", "0.9.2", "27.0+", "Oct 18, 2026", "00:00 UTC",
                        "com.stuff.where.development", "actions/runs/2/attempts/1", "pull/42"):
            self.assertIn(content, detail)

    def test_missing_registered_artwork_fails_command_before_any_site_is_written(self):
        app = load_app("where")
        broken = replace(app, presentation=AppPresentation("An app", "missing-icon.png", None))
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "updates.json"
            source.write_text(json.dumps(catalog()))
            with patch("Tools.installer_site_data.load_apps", return_value={"where": broken}), \
                    redirect_stdout(io.StringIO()) as stdout, redirect_stderr(io.StringIO()) as stderr:
                self.assertEqual(main(["--catalog", str(source), "--repository", REPO,
                                       "--feed-url", FEED_URL, "--output", str(root / "site")]), 1)
            self.assertEqual(stdout.getvalue(), "")
            self.assertIn("missing-icon.png", stderr.getvalue())
            self.assertFalse((root / "site").exists())

    def test_homepage_only_installs_main_and_app_pages_keep_prs_separate(self):
        value = multiple_apps()
        files = render_site(value, REPO, FEED_URL)
        home = files["index.html"].decode()
        self.assertIn("Where Dev", home)
        self.assertIn("Example Dev", home)
        self.assertNotIn("pr-42", home)
        self.assertIn("apps/where/", home)
        self.assertIn("apps/example/", home)
        for app in value["apps"]:
            app_id = app["id"]
            page = files[f"apps/{app_id}/index.html"].decode()
            self.assertIn(f"apps/{app_id}/pr-42/", page)
            other = "example" if app_id == "where" else "where"
            self.assertNotIn(f"apps/{other}/pr-42/", page)
            item = plistlib.loads(files[f"manifests/{app_id}/pr-42/2-1.plist"])["items"][0]
            self.assertEqual(item["metadata"]["bundle-identifier"], app["bundleIdentifier"])
            self.assertEqual(item["metadata"]["title"], app["name"])
            self.assertIn(f"installer-{app_id}-pr-42-2-1", item["assets"][0]["url"])

    def test_retiring_one_app_does_not_retire_another_apps_same_channel(self):
        value = multiple_apps()
        value["apps"][0]["channels"][1]["active"] = False
        files = render_site(value, REPO, FEED_URL)
        self.assertNotIn("manifests/where/pr-42/2-1.plist", files)
        self.assertIn("manifests/example/pr-42/2-1.plist", files)
        self.assertIn(b"Channel retired", files["apps/where/pr-42/index.html"])
        self.assertIn(b"itms-services", files["apps/example/pr-42/index.html"])

    def test_app_without_main_has_navigation_but_no_pr_install_on_homepage(self):
        value = catalog()
        value["apps"][0]["channels"] = value["apps"][0]["channels"][1:]
        files = render_site(value, REPO, FEED_URL)
        self.assertIn(b"Where Dev", files["index.html"])
        self.assertIn(b"No main build", files["index.html"])
        self.assertNotIn(b"itms-services", files["index.html"])
        self.assertIn(b"itms-services", files["apps/where/index.html"])

    def test_astro_build_failure_reports_diagnostics_and_exposes_no_partial_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "updates.json"
            source.write_text(json.dumps(catalog()))
            output = Path(temporary) / "site"
            failure = subprocess.CompletedProcess([], 23, stdout="build log", stderr="template failed")
            with patch("installer_update_site.subprocess.run", return_value=failure), \
                    redirect_stdout(io.StringIO()) as stdout, redirect_stderr(io.StringIO()) as stderr:
                status = main(["--catalog", str(source), "--repository", REPO,
                               "--feed-url", FEED_URL, "--output", str(output)])
            self.assertEqual(status, 1)
            self.assertEqual(stdout.getvalue(), "")
            self.assertIn("exit 23", stderr.getvalue())
            self.assertIn("template failed", stderr.getvalue())
            self.assertEqual(list(Path(temporary).iterdir()), [source])

    def test_astro_preserves_exact_publication_files_and_does_not_ship_client_scripts(self):
        from installer_site_data import prepare_site
        value = catalog()
        expected = prepare_site(value, REPO, FEED_URL).files
        files = render_site(value, REPO, FEED_URL)
        for path, content in expected.items():
            self.assertEqual(files[path], content, path)
        self.assertFalse(any(path.endswith((".js", ".mjs")) for path in files))

    def test_simultaneous_builds_keep_their_catalogs_and_generated_files_isolated(self):
        from concurrent.futures import ThreadPoolExecutor
        inputs = (catalog("first", "First App", "com.example.first"),
                  catalog("second", "Second App", "com.example.second"))
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(lambda value: render_site(value, REPO, FEED_URL), inputs))
        for value, files in zip(inputs, results):
            self.assertEqual(json.loads(files["updates.json"]), value)
            app = value["apps"][0]
            self.assertIn(f'apps/{app["id"]}/main/index.html', files)
            self.assertIn(app["name"].encode(), files["index.html"])
        self.assertNotIn("apps/second/index.html", results[0])
        self.assertNotIn("apps/first/index.html", results[1])

    def test_dependency_optimizer_cache_is_written_inside_the_build_workspace(self):
        from installer_site_data import prepare_site
        BUILD_ROOT.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="cache-", dir=BUILD_ROOT) as temporary:
            workspace = Path(temporary)
            environment = stage_input(prepare_site(catalog(), REPO, FEED_URL), workspace)
            build_astro(environment, workspace / "site")
            metadata = list(Path(environment["INSTALLER_SITE_CACHE"]).rglob("_metadata.json"))
            self.assertTrue(metadata, "Vite must write its optimizer cache inside this build's isolated cache directory")

    def test_custom_domain_and_nested_base_keep_navigation_and_assets_on_the_current_host(self):
        for base in ("https://installs.example/", "https://installs.example/nested/catalog/"):
            value = catalog()
            feed = base + "updates.json"
            for channel in value["apps"][0]["channels"]:
                for release in channel["releases"]:
                    release["manifestURL"] = manifest_url(feed, "where", channel["name"], release["id"])
            with self.subTest(base=base):
                from urllib.parse import urlsplit
                root = urlsplit(base).path
                files = render_site(value, REPO, feed)
                home = files["index.html"].decode()
                self.assertIn(f'href="{root}apps/where/"', home)
                self.assertIn(f'src="{root}assets/where/', home)
                self.assertIn("https%3A%2F%2Finstalls.example%2F", home)
                self.assertEqual(json.loads(files["updates.json"]), value)
