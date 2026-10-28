from contextlib import redirect_stderr, redirect_stdout
from dataclasses import replace
import base64
import hashlib
import io
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

from Tools.InstallerKit.github_releases import asset_url
from Tools.InstallerKit.installer_installation import manifest_url
from Tools.InstallerKit.installer_apps import AppPresentation, load_app
from Tools.InstallerKit.installer_update_feed import GitHubUpdateFeed
from Tools.InstallerKit.installer_update_site import (
    BUILD_ROOT,
    build_astro,
    main,
    render_site,
    stage_input,
    write_site,
)
from Tools.repository import repository_root
from Tools.Tests.Fixtures.installer_update_fixtures import (
    catalog,
    multiple_apps,
    FEED_URL,
    REPO,
)


class InstallerUpdateSiteTests(unittest.TestCase):
    def test_published_catalog_command_builds_an_empty_site_before_first_publication(
        self,
    ):
        transport = Mock(return_value=None)
        feed = GitHubUpdateFeed(REPO, "fixture-token", transport)
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "site"
            with (
                patch(
                    "Tools.InstallerKit.installer_update_site.GitHubUpdateFeed",
                    return_value=feed,
                ),
                redirect_stdout(io.StringIO()) as stdout,
                redirect_stderr(io.StringIO()) as stderr,
            ):
                status = main(
                    [
                        "--published-catalog",
                        "--repository",
                        REPO,
                        "--feed-url",
                        FEED_URL,
                        "--output",
                        str(output),
                    ]
                )
            self.assertEqual(status, 0, stderr.getvalue())
            self.assertEqual(stderr.getvalue(), "")
            self.assertIn("Prepared", stdout.getvalue())
            self.assertEqual(
                json.loads((output / "updates.json").read_text()),
                {"schemaVersion": 3, "apps": []},
            )
            self.assertIn(
                "No builds are available yet", (output / "index.html").read_text()
            )
            self.assertFalse((output / "manifests").exists())
        self.assertTrue(
            all(call.args[0].method == "GET" for call in transport.call_args_list)
        )

    def test_published_catalog_command_keeps_existing_builds_and_retired_history(self):
        value = multiple_apps()
        value["apps"][0]["channels"][1]["active"] = False
        value["apps"][1]["channels"].append(
            {
                "name": "pr-43",
                "active": False,
                "releases": [],
                "buildStatus": {
                    "state": "preparing",
                    "id": {"run": 3, "attempt": 1},
                    "sha": "3" * 40,
                },
            }
        )
        transport = Mock(
            return_value={
                "sha": "revision",
                "encoding": "base64",
                "content": base64.b64encode(json.dumps(value).encode()).decode(),
            }
        )
        feed = GitHubUpdateFeed(REPO, "fixture-token", transport)
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "site"
            with (
                patch(
                    "Tools.InstallerKit.installer_update_site.GitHubUpdateFeed",
                    return_value=feed,
                ),
                redirect_stdout(io.StringIO()) as stdout,
                redirect_stderr(io.StringIO()) as stderr,
            ):
                status = main(
                    [
                        "--published-catalog",
                        "--repository",
                        REPO,
                        "--feed-url",
                        FEED_URL,
                        "--output",
                        str(output),
                    ]
                )
            self.assertEqual(status, 0, stderr.getvalue())
            self.assertEqual(stderr.getvalue(), "")
            self.assertIn("Prepared", stdout.getvalue())
            self.assertEqual(json.loads((output / "updates.json").read_text()), value)
            self.assertFalse((output / "manifests/where/pr-42").exists())
            self.assertFalse((output / "manifests/example/pr-43").exists())
            for path in (
                "manifests/where/main/2-1.plist",
                "manifests/example/pr-42/2-1.plist",
            ):
                self.assertTrue((output / path).is_file())

    def test_published_catalog_read_failure_stops_before_build_or_output(self):
        for failure in (
            ValueError("api.github.com: HTTP 403"),
            OSError("connection lost"),
            ValueError("Unsupported update catalog"),
            ValueError("updates.json is missing"),
        ):
            with (
                self.subTest(failure=str(failure)),
                tempfile.TemporaryDirectory() as temporary,
            ):
                output = Path(temporary) / "site"
                with (
                    patch(
                        "Tools.InstallerKit.installer_update_site.GitHubUpdateFeed"
                    ) as feed,
                    patch(
                        "Tools.InstallerKit.installer_update_site.render_site"
                    ) as render,
                    redirect_stdout(io.StringIO()) as stdout,
                    redirect_stderr(io.StringIO()) as stderr,
                ):
                    feed.return_value.load_for_deployment.side_effect = failure
                    status = main(
                        [
                            "--published-catalog",
                            "--repository",
                            REPO,
                            "--feed-url",
                            FEED_URL,
                            "--output",
                            str(output),
                        ]
                    )
                self.assertEqual(status, 1)
                self.assertEqual(stdout.getvalue(), "")
                self.assertEqual(stderr.getvalue(), f"error: {failure}\n")
                self.assertFalse(output.exists())
                render.assert_not_called()

    def test_site_feed_and_manifests_share_exact_releases_and_escape_commit_subjects(
        self,
    ):
        value = catalog()
        files = render_site(value, REPO, FEED_URL)
        self.assertEqual(json.loads(files["updates.json"]), value)
        self.assertIn(b"Install Where Dev", files["index.html"])
        detail = files["apps/where/pr-42/index.html"].decode()
        self.assertNotIn("<script>", detail)
        self.assertIn("&lt;script&gt;", detail)
        self.assertIn("itms-services://?action=download-manifest", detail)
        self.assertIn("manifests%2Fwhere%2Fpr-42%2F2-1.plist", detail)
        self.assertIn(
            f'<dt>Pull request</dt><dd><a href="https://github.com/{REPO}/pull/42">#42</a></dd>',
            detail,
        )
        self.assertNotIn(b"<dt>Pull request</dt>", files["apps/where/main/index.html"])
        for run in (1, 2):
            item = plistlib.loads(files[f"manifests/where/pr-42/{run}-1.plist"])[
                "items"
            ][0]
            self.assertEqual(
                item["assets"][0]["url"],
                asset_url(REPO, "where", "pr-42", {"run": run, "attempt": 1}),
            )

    def test_retired_channel_keeps_history_and_page_but_has_no_install_manifest(self):
        value = catalog()
        value["apps"][0]["channels"][1]["active"] = False
        files = render_site(value, REPO, FEED_URL)
        self.assertEqual(json.loads(files["updates.json"]), value)
        self.assertIn(b"Channel retired", files["apps/where/pr-42/index.html"])
        self.assertNotIn(b"itms-services", files["apps/where/pr-42/index.html"])
        self.assertFalse(
            any(path.startswith("manifests/where/pr-42/") for path in files)
        )
        self.assertIn("manifests/where/main/2-1.plist", files)

    def test_untrusted_destinations_and_invalid_metadata_fail_before_output(self):
        bad_releases = (
            {"ipaURL": "https://evil.example/Where.ipa"},
            {"manifestURL": "https://evil.example/manifest.plist"},
            {
                "manifestURL": manifest_url(
                    FEED_URL, "where", "main", {"run": 1, "attempt": 1}
                )
            },
            {"bundleVersion": "not-a-version"},
            {"sha": "<script>"},
            {
                "buildDetails": {
                    "version": "0.9.2",
                    "minimumOSVersion": "27",
                    "sizeBytes": -1,
                }
            },
            {"publishedAt": '2026-10-18T00:00:00Z" onmouseover="bad'},
        )
        for changes in bad_releases:
            with (
                self.subTest(changes=changes),
                tempfile.TemporaryDirectory() as temporary,
            ):
                value = catalog()
                value["apps"][0]["channels"][0]["releases"][0].update(changes)
                path = Path(temporary) / "updates.json"
                path.write_text(json.dumps(value))
                output = Path(temporary) / "site"
                with (
                    redirect_stderr(io.StringIO()) as stderr,
                    redirect_stdout(io.StringIO()) as stdout,
                ):
                    self.assertEqual(
                        main(
                            [
                                "--catalog",
                                str(path),
                                "--repository",
                                REPO,
                                "--feed-url",
                                FEED_URL,
                                "--output",
                                str(output),
                            ]
                        ),
                        1,
                    )
                self.assertTrue(stderr.getvalue().startswith("error:"))
                self.assertEqual(stdout.getvalue(), "")
                self.assertFalse(output.exists())

    def test_failed_file_write_leaves_no_partial_deployment_and_preserves_existing_site(
        self,
    ):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "site"
            with (
                patch.object(Path, "write_bytes", side_effect=OSError("disk full")),
                self.assertRaises(OSError),
            ):
                write_site({"updates.json": b"{}"}, output)
            self.assertEqual(list(Path(temporary).iterdir()), [])
            output.mkdir()
            (output / "index.html").write_text("existing")
            with self.assertRaisesRegex(ValueError, "must not exist"):
                write_site({"index.html": b"replacement"}, output)
            self.assertEqual((output / "index.html").read_text(), "existing")

    def test_public_command_handles_paths_with_spaces_and_help_outside_the_repository(
        self,
    ):
        command = [sys.executable, "-m", "Tools.InstallerKit.installer_update_site"]
        environment = {
            "PATH": "/usr/bin:/bin",
            "PYTHONDONTWRITEBYTECODE": "1",
            "PYTHONPATH": str(repository_root(__file__)),
        }
        with tempfile.TemporaryDirectory(prefix="site fixture ü ") as temporary:
            root = Path(temporary)
            help_result = subprocess.run(
                [*command, "--help"],
                cwd=root,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(help_result.returncode, 0, help_result.stderr)
            self.assertIn("--catalog", help_result.stdout)
            source = root / "updates.json"
            source.write_text(json.dumps(catalog()))
            result = subprocess.run(
                [
                    *command,
                    "--catalog",
                    str(source),
                    "--repository",
                    REPO,
                    "--feed-url",
                    FEED_URL,
                    "--output",
                    str(root / "site"),
                ],
                cwd=root,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
            self.assertIn("Prepared", result.stdout)
            self.assertTrue((root / "site/apps/where/main/index.html").is_file())
            self.assertEqual(len(list((root / "site/assets/where").glob("*.png"))), 2)

    def test_trusted_artwork_is_packaged_once_with_content_addresses_and_dark_appearance(
        self,
    ):
        app = load_app("where")
        files = render_site(catalog(), REPO, FEED_URL)
        source_root = repository_root(__file__)
        assets = [path for path in files if path.startswith("assets/")]
        self.assertEqual(len(assets), 2)
        for path in (app.presentation.icon, app.presentation.dark_icon):
            contents = (source_root / path).read_bytes()
            relative = f"assets/where/{hashlib.sha256(contents).hexdigest()[:16]}.png"
            self.assertEqual(files[relative], contents)
            for page in (
                "index.html",
                "apps/where/index.html",
                "apps/where/main/index.html",
            ):
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
        detail = render_site(catalog(), REPO, FEED_URL)[
            "apps/where/pr-42/index.html"
        ].decode()
        for content in (
            "48.3 MB",
            "0.9.2",
            "27.0+",
            "Oct 18, 2026",
            "00:00 UTC",
            "com.stuff.where.development",
            "actions/runs/2/attempts/1",
            "pull/42",
        ):
            self.assertIn(content, detail)

    def test_missing_registered_artwork_fails_command_before_any_site_is_written(self):
        app = load_app("where")
        broken = replace(
            app, presentation=AppPresentation("An app", "missing-icon.png", None)
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "updates.json"
            source.write_text(json.dumps(catalog()))
            with (
                patch(
                    "Tools.InstallerKit.installer_site_data.load_apps",
                    return_value={"where": broken},
                ),
                redirect_stdout(io.StringIO()) as stdout,
                redirect_stderr(io.StringIO()) as stderr,
            ):
                self.assertEqual(
                    main(
                        [
                            "--catalog",
                            str(source),
                            "--repository",
                            REPO,
                            "--feed-url",
                            FEED_URL,
                            "--output",
                            str(root / "site"),
                        ]
                    ),
                    1,
                )
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
            item = plistlib.loads(files[f"manifests/{app_id}/pr-42/2-1.plist"])[
                "items"
            ][0]
            self.assertEqual(
                item["metadata"]["bundle-identifier"], app["bundleIdentifier"]
            )
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

    def test_astro_build_failure_reports_diagnostics_and_exposes_no_partial_output(
        self,
    ):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "updates.json"
            source.write_text(json.dumps(catalog()))
            output = Path(temporary) / "site"
            failure = subprocess.CompletedProcess(
                [], 23, stdout="build log", stderr="template failed"
            )
            with (
                patch(
                    "Tools.InstallerKit.installer_update_site.subprocess.run",
                    return_value=failure,
                ),
                redirect_stdout(io.StringIO()) as stdout,
                redirect_stderr(io.StringIO()) as stderr,
            ):
                status = main(
                    [
                        "--catalog",
                        str(source),
                        "--repository",
                        REPO,
                        "--feed-url",
                        FEED_URL,
                        "--output",
                        str(output),
                    ]
                )
            self.assertEqual(status, 1)
            self.assertEqual(stdout.getvalue(), "")
            self.assertIn("exit 23", stderr.getvalue())
            self.assertIn("template failed", stderr.getvalue())
            self.assertEqual(list(Path(temporary).iterdir()), [source])

    def test_astro_preserves_exact_publication_files_and_does_not_ship_client_scripts(
        self,
    ):
        from Tools.InstallerKit.installer_site_data import prepare_site

        value = catalog()
        expected = prepare_site(value, REPO, FEED_URL).files
        files = render_site(value, REPO, FEED_URL)
        for path, content in expected.items():
            self.assertEqual(files[path], content, path)
        self.assertFalse(any(path.endswith((".js", ".mjs")) for path in files))

    def test_simultaneous_builds_keep_their_catalogs_and_generated_files_isolated(self):
        from concurrent.futures import ThreadPoolExecutor

        inputs = (
            catalog("first", "First App", "com.example.first"),
            catalog("second", "Second App", "com.example.second"),
        )
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(
                executor.map(lambda value: render_site(value, REPO, FEED_URL), inputs)
            )
        for value, files in zip(inputs, results):
            self.assertEqual(json.loads(files["updates.json"]), value)
            app = value["apps"][0]
            self.assertIn(f"apps/{app['id']}/main/index.html", files)
            self.assertIn(app["name"].encode(), files["index.html"])
        self.assertNotIn("apps/second/index.html", results[0])
        self.assertNotIn("apps/first/index.html", results[1])

    def test_dependency_optimizer_cache_is_written_inside_the_build_workspace(self):
        from Tools.InstallerKit.installer_site_data import prepare_site

        BUILD_ROOT.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="cache-", dir=BUILD_ROOT) as temporary:
            workspace = Path(temporary)
            environment = stage_input(
                prepare_site(catalog(), REPO, FEED_URL), workspace
            )
            build_astro(environment, workspace / "site")
            metadata = list(
                Path(environment["INSTALLER_SITE_CACHE"]).rglob("_metadata.json")
            )
            self.assertTrue(
                metadata,
                "Vite must write its optimizer cache inside this build's isolated cache directory",
            )

    def test_custom_domain_and_nested_base_keep_navigation_and_assets_on_the_current_host(
        self,
    ):
        for base in (
            "https://installs.example/",
            "https://installs.example/nested/catalog/",
        ):
            value = catalog()
            feed = base + "updates.json"
            for channel in value["apps"][0]["channels"]:
                for release in channel["releases"]:
                    release["manifestURL"] = manifest_url(
                        feed, "where", channel["name"], release["id"]
                    )
            with self.subTest(base=base):
                from urllib.parse import urlsplit

                root = urlsplit(base).path
                files = render_site(value, REPO, feed)
                home = files["index.html"].decode()
                self.assertIn(f'href="{root}apps/where/"', home)
                self.assertIn(f'src="{root}assets/where/', home)
                self.assertIn("https%3A%2F%2Finstalls.example%2F", home)
                self.assertEqual(json.loads(files["updates.json"]), value)
