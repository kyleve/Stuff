from contextlib import redirect_stderr, redirect_stdout
from copy import deepcopy
from dataclasses import replace
import hashlib
import io
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from github_releases import asset_url
from installer_installation import manifest_url
from installer_apps import AppPresentation, load_app
from installer_update_site import main, render_site, write_site
from Fixtures.installer_update_fixtures import catalog, multiple_apps, FEED_URL, REPO


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
        command = Path(__file__).resolve().parents[1] / "installer_update_site.py"
        with tempfile.TemporaryDirectory(prefix="site fixture ü ") as temporary:
            root = Path(temporary)
            help_result = subprocess.run([sys.executable, str(command), "--help"], cwd=root,
                                         env={"PATH": "/usr/bin:/bin", "PYTHONDONTWRITEBYTECODE": "1"}, capture_output=True, text=True)
            self.assertEqual(help_result.returncode, 0, help_result.stderr)
            self.assertIn("--catalog", help_result.stdout)
            source = root / "updates.json"
            source.write_text(json.dumps(catalog()))
            result = subprocess.run([sys.executable, str(command), "--catalog", str(source),
                                     "--repository", REPO, "--feed-url", FEED_URL, "--output", str(root / "site")],
                                    cwd=root, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
            self.assertIn("Prepared", result.stdout)
            self.assertTrue((root / "site/apps/where/main/index.html").is_file())
            self.assertEqual(len(list((root / "site/assets/where").glob("*.png"))), 2)

    def test_trusted_artwork_is_packaged_once_with_content_addresses_and_dark_appearance(self):
        app = load_app("where")
        files = render_site(catalog(), REPO, FEED_URL)
        source_root = Path(__file__).resolve().parents[2]
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
            with patch("installer_update_site.load_apps", return_value={"where": broken}), \
                    redirect_stdout(io.StringIO()) as stdout, redirect_stderr(io.StringIO()) as stderr:
                self.assertEqual(main(["--catalog", str(source), "--repository", REPO,
                                       "--feed-url", FEED_URL, "--output", str(root / "site")]), 1)
            self.assertEqual(stdout.getvalue(), "")
            self.assertIn("missing-icon.png", stderr.getvalue())
            self.assertFalse((root / "site").exists())

    def test_duplicate_out_of_order_or_empty_active_channels_fail(self):
        original = catalog()
        duplicates = deepcopy(original)
        duplicates["apps"][0]["channels"] += duplicates["apps"][0]["channels"]
        unordered = deepcopy(original)
        unordered["apps"][0]["channels"][0]["releases"].reverse()
        empty = deepcopy(original)
        empty["apps"][0]["channels"][0]["releases"] = []
        for value in (duplicates, unordered, empty):
            with self.assertRaises(ValueError):
                render_site(value, REPO, FEED_URL)

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

    def test_rejects_app_collisions_and_cross_app_manifest_urls(self):
        duplicate = multiple_apps()
        duplicate["apps"][1]["id"] = "where"
        duplicate_bundle = multiple_apps()
        duplicate_bundle["apps"][1]["bundleIdentifier"] = duplicate_bundle["apps"][0]["bundleIdentifier"]
        wrong_manifest = multiple_apps()
        wrong_manifest["apps"][1]["channels"][0]["releases"][0]["manifestURL"] = wrong_manifest["apps"][0]["channels"][0]["releases"][0]["manifestURL"]
        for value in (duplicate, duplicate_bundle, wrong_manifest):
            with self.assertRaises(ValueError):
                render_site(value, REPO, FEED_URL)
