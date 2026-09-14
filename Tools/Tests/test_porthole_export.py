import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("porthole_export", ROOT / "Tools/porthole_export.py")
EXPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EXPORT)


class PortholeExportTests(unittest.TestCase):
    def test_shared_target_path_only_exports_declared_sources(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for path in ["Where/Assets/Sources/Bundle.swift", "Where/Assets/Sources/Excluded/Fixture.swift",
                         "Where/Assets/Tests/Test.swift", "Where/UI/Sources/Screen.swift"]:
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text("struct Example {}")
            target = {"name": "Assets", "path": "Where", "sources": ["Assets/Sources"],
                      "exclude": ["Assets/Sources/Excluded"],
                      "pluginUsages": [{"plugin": ["PortholeBuildPlugin", None]}]}
            self.assertEqual(EXPORT.module_sources(root, {"targets": [target]}),
                             [root / "Where/Assets/Sources/Bundle.swift"])

    def test_new_exported_module_requires_runtime_installation(self):
        package = {"targets": [
            {"name": name, "pluginUsages": [{"plugin": ["PortholeBuildPlugin", None]}]}
            for name in ["WhereUI", "NewFeature"]
        ]}
        existing = "try await PortholeGeneratedModule.install(in: registry, scope: scope)"
        with self.assertRaisesRegex(ValueError, "NewFeature"):
            EXPORT.validate_installation(package, {"WhereUI": existing})
        EXPORT.validate_installation(package, {"WhereUI": existing + "\ntry await NewFeature.PortholeGeneratedModule.install(in: registry, scope: scope)"})

    def test_control_plane_inventory_tracks_local_products_and_excludes_credentials(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = root / "Runtime"
            certificates = root / "Certificates"
            runtime.mkdir()
            certificates.mkdir()
            (runtime / "PortholeRegistry.swift").write_text("actor PortholeRegistry {}")
            (runtime / "PortholeCredentials.swift").write_text("struct PrivateCredentialStore {}")
            (certificates / "PortholeCertificates.swift").write_text("struct PrivateKeyMaterial {}")
            package = {"targets": [
                {"name": "WhereUI", "dependencies": [{"target": ["PortholeRuntime", None]}]},
                {"name": "PortholeRuntime", "path": "Runtime", "dependencies": [
                    {"product": ["Certificates", "certificates", None, None]}]},
                {"name": "PortholeUnused", "path": "Unused", "dependencies": []},
            ]}
            local = {"certificates": {"directory": str(certificates), "package": {
                "products": [{"name": "Certificates", "targets": ["PortholeCertificates"]}],
                "targets": [{"name": "PortholeCertificates", "path": ".", "dependencies": []}],
            }}}
            inventory = EXPORT.control_plane_inventory(root, package, local)["modules"]
            self.assertEqual([module["name"] for module in inventory], ["PortholeCertificates", "PortholeRuntime"])
            self.assertEqual(inventory[0]["sources"], [])
            self.assertEqual(inventory[1]["sources"], [str(runtime / "PortholeRegistry.swift")])
            self.assertEqual(inventory[1]["excludedFiles"][0]["path"], str(runtime / "PortholeCredentials.swift"))
            self.assertIn("approval", inventory[1]["reason"])

    def test_dependency_inventory_follows_manifest_opt_in(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in ["AppCore", "Credentials", "ThirdParty"]:
                (root / name).mkdir()
                (root / name / "Source.swift").write_text("struct Example {}")
            package = {"targets": [
                {"name": "AppCore", "path": "AppCore", "pluginUsages": [{"plugin": ["PortholeBuildPlugin", None]}]},
                {"name": "Credentials", "path": "Credentials", "pluginUsages": []},
                {"name": "ThirdParty", "path": "ThirdParty", "pluginUsages": [{"plugin": ["AnotherPlugin", None]}]},
            ]}
            self.assertEqual(EXPORT.module_sources(root, package), [root / "AppCore/Source.swift"])

    def test_vendored_interpreter_matches_pinned_files_without_host_modules(self):
        vendor = ROOT / "Shared/Porthole/CQuickJS"
        metadata = json.loads((vendor / "VENDOR.json").read_text())
        self.assertEqual(metadata["version"], "0.16.2")
        for path, digest in metadata["files"].items():
            with self.subTest(path=path):
                self.assertEqual(hashlib.sha256((vendor / path).read_bytes()).hexdigest(), digest)
        files = {path.name for path in (vendor / "Sources/vendor").iterdir()}
        self.assertTrue({"qjs.c", "qjsc.c", "quickjs-libc.c", "quickjs-libc.h"}.isdisjoint(files))
