from copy import deepcopy
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

from Tools.InstallerKit.installer_apps import load_app, REGISTRY, validate_app_id
from Tools.InstallerKit.installer_distribution import Publication, validate_ipa


class InstallerAppsTests(unittest.TestCase):
    def test_another_app_needs_no_where_metadata_or_extensions(self):
        value = {
            "id": "example",
            "name": "Example Dev",
            "bundleIdentifier": "com.example.development",
            "bundlePath": "Payload/Example.app",
            "signedBundles": ["Payload/Example.app"],
            "requiredInfo": {"ExampleAudience": "development"},
        }
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            registry = root / "apps.json"
            registry.write_text(json.dumps([value]))
            app = load_app("example", registry)
            sha = "a" * 40
            info = {
                "CFBundleIdentifier": app.bundle_identifier,
                "InstallerAppID": app.id,
                "InstallerGitSHA": sha,
                "InstallerGitStatus": "clean",
                "ExampleAudience": "development",
            }
            ipa = root / "Example.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr(f"{app.bundle_path}/Info.plist", plistlib.dumps(info))
                for resource in (
                    "embedded.mobileprovision",
                    "_CodeSignature/CodeResources",
                ):
                    archive.writestr(f"{app.bundle_path}/{resource}", b"signed fixture")
            validate_ipa(ipa, Publication(sha, None), app)
            with self.assertRaises((ValueError, KeyError)):
                validate_ipa(ipa, Publication(sha, None), load_app("where"))

    def test_registry_rejects_duplicate_apps_bundles_and_unsafe_paths(self):
        original = json.loads(REGISTRY.read_text())
        invalid = [original + original]
        for changes in (
            {"id": "../escape"},
            {"bundlePath": "../../outside.app"},
            {"signedBundles": ["Payload/Where.app", "../../outside"]},
            {"site": {"subtitle": "App", "icon": "../outside.png"}},
            {"site": {"subtitle": "App", "icon": "/tmp/outside.png"}},
            {"site": {"subtitle": "App", "icon": "https://example.org/icon.svg"}},
            {"site": {"subtitle": "App", "darkIcon": "icon.png"}},
            {"site": {"subtitle": ""}},
            {"site": None},
            {"name": ""},
            {"bundleIdentifier": "invalid"},
        ):
            invalid.append([{**original[0], **changes}])
        duplicate_bundle = deepcopy(original)
        duplicate_bundle.append({**original[0], "id": "another"})
        invalid.append(duplicate_bundle)
        with tempfile.TemporaryDirectory() as temporary:
            registry = Path(temporary) / "apps.json"
            for values in invalid:
                registry.write_text(json.dumps(values))
                with self.subTest(values=values), self.assertRaises(ValueError):
                    load_app("where", registry)
            registry.write_text(json.dumps(original))
            with self.assertRaisesRegex(ValueError, "Unregistered"):
                load_app("missing", registry)

    def test_site_artwork_is_optional_and_does_not_enter_the_update_catalog(self):
        original = json.loads(REGISTRY.read_text())[0]
        with tempfile.TemporaryDirectory() as temporary:
            registry = Path(temporary) / "apps.json"
            registry.write_text(json.dumps([original]))
            app = load_app("where", registry)
            self.assertEqual(app.presentation.icon, original["site"]["icon"])
            self.assertEqual(app.presentation.dark_icon, original["site"]["darkIcon"])
            self.assertNotIn("site", app.metadata)
            del original["site"]
            registry.write_text(json.dumps([original]))
            app = load_app("where", registry)
            self.assertIsNone(app.presentation.icon)
            self.assertIsNone(app.presentation.dark_icon)

    def test_app_id_is_one_bounded_path_component(self):
        for value in ("", "../where", "Where", "where/main", "where\n", "a" * 65):
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate_app_id(value)
        self.assertEqual(validate_app_id("sample-app2"), "sample-app2")

    def test_enabled_apps_are_explicit_and_export_names_come_from_signing(self):
        from Tools.InstallerKit.installer_apps import archive_product, enabled_apps

        self.assertEqual(enabled_apps({}), [])
        self.assertEqual(
            enabled_apps({"WHERE_DISTRIBUTION_ENABLED": "true"}), ["where"]
        )
        self.assertEqual(
            enabled_apps(
                {
                    "WHERE_DISTRIBUTION_ENABLED": "true",
                    "THROW_DISTRIBUTION_ENABLED": "true",
                }
            ),
            ["where", "throw"],
        )
        self.assertEqual(enabled_apps({"THROW_DISTRIBUTION_ENABLED": "false"}), [])
        self.assertEqual(archive_product("throw"), "Throw")
        with tempfile.TemporaryDirectory() as temporary:
            signing = Path(temporary) / "signing.json"
            for product in ("Where", "../Throw", "Throw\n"):
                signing.write_text(json.dumps({"throw": {"product": product}}))
                with self.subTest(product=product), self.assertRaises(ValueError):
                    archive_product("throw", signing_path=signing)

    def test_selection_command_outputs_multiple_apps_without_credentials(self):
        import subprocess
        import sys
        from Tools.repository import repository_root

        with tempfile.TemporaryDirectory(prefix="apps ü ") as temporary:
            output = Path(temporary) / "output"
            result = subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "Tools.InstallerKit.installer_apps",
                    "--output",
                    str(output),
                ],
                cwd=temporary,
                capture_output=True,
                text=True,
                env={
                    "PATH": "/usr/bin:/bin",
                    "PYTHONPATH": str(repository_root(__file__)),
                    "INSTALLER_VARIABLES": json.dumps(
                        {
                            "WHERE_DISTRIBUTION_ENABLED": "true",
                            "THROW_DISTRIBUTION_ENABLED": "true",
                        }
                    ),
                },
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
            self.assertEqual(result.stdout, 'apps=["where","throw"]\n')
            self.assertEqual(output.read_text(), result.stdout)
