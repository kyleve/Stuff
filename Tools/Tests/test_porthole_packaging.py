"""Hermetic product fixtures exercise packaging failures without Xcode or a simulator."""
import contextlib
import copy
import io
import json
from pathlib import Path
import plistlib
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import porthole_packaging as checker
import porthole_compiler_contract as contract
import porthole_macho_symbols as symbols
import porthole_macho_exports as exports
from Fixtures.porthole_macho import thin


class PortholePackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.app = self.root / "Where.app"
        self.hosts = {"app": self.app, "WhereWidgets.appex": self.app / "PlugIns/WhereWidgets.appex",
                      "WhereShareExtension.appex": self.app / "PlugIns/WhereShareExtension.appex"}
        self.images = {}
        self.metadata = [("_$s" + stems[0] + "N", 0x0F, 1, 0, None) for stems in checker.FAMILY_STEMS.values()]
        self.support = self.app / "Frameworks/WhereApplicationSupport.framework/WhereApplicationSupport"
        for name in ["WhereApplicationSupport", "PortholeCertificates"]:
            bundle = self.app / "Frameworks" / (name + ".framework")
            self.write_plist(bundle / "Info.plist", {"CFBundleExecutable": name})
            binary = bundle / name
            binary.write_bytes(thin(self.metadata if name == "WhereApplicationSupport" else []))
            self.images[binary] = {"dependencies": ["/usr/lib/libSystem.B.dylib"], "rpaths": []}
        for name, host in self.hosts.items():
            self.write_plist(host / "Info.plist", {"CFBundleExecutable": "Host", "CFBundleIdentifier": "test.where",
                                                  "WhereConfiguration": "Release", "DTPlatformName": "iphoneos"})
            binary = host / "Host"
            binary.write_bytes(thin())
            self.images[binary] = {"dependencies": ["@rpath/WhereApplicationSupport.framework/WhereApplicationSupport",
                                                     "@rpath/PortholeCertificates.framework/PortholeCertificates"],
                                   "rpaths": ["@executable_path/Frameworks" if name == "app" else "@executable_path/../../Frameworks"]}
        self.manifests = {"RegionKit": ("regions.json", [{"id": "test", "geometry": {"file": "test.geojson"}}]),
                          "WhereUI": ("AppIcons.json", {"icons": [{"id": "test", "previewImageName": "TestIcon"}]})}
        for module, (name, value) in self.manifests.items():
            source = self.root / f"Where/{module}/Sources/Resources" / name
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text(json.dumps(value))
        for host in self.hosts.values():
            for module, names in checker.RESOURCE_PAYLOADS.items():
                bundle = host / f"Stuff_{module}.bundle"
                self.write_plist(bundle / "Info.plist", {"CFBundlePackageType": "BNDL", "CFBundleIdentifier": f"stuff.{module}.resources"})
                for name in names:
                    p = bundle / name
                    p.parent.mkdir(parents=True, exist_ok=True)
                    if name.endswith((".strings", ".stringsdict")):
                        self.write_plist(p, {"key": "value"})
                    elif name.endswith(".json"):
                        p.write_text(json.dumps(self.manifests[module][1]))
                    else:
                        p.write_bytes(b"fixture-asset-catalog")
                if module == "RegionKit":
                    (bundle / "test.geojson").write_text('{"type":"FeatureCollection","features":[]}')
        self.intent_path = self.app / "Metadata.appintents/extract.actionsdata"
        self.intent_path.parent.mkdir()
        self.intents = {"actions": {name: {"fullyQualifiedTypeName": "WhereIntents." + name, "parameters": []}
                                     for name in checker.ACTION_IDS},
                        "entities": {"RegionEntity": {"fullyQualifiedTypeName": "WhereIntents.RegionEntity"}},
                        "queries": {"RegionEntityQuery": {"fullyQualifiedIdentifier": "WhereIntents.RegionEntityQuery"}},
                        "autoShortcuts": [{"actionIdentifier": name} for name in sorted(checker.SHORTCUT_IDS)]}
        self.intent_path.write_text(json.dumps(self.intents))

    def write_plist(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(plistlib.dumps(value, fmt=plistlib.FMT_BINARY))

    def inspect(self, configuration="Release", sdk="iphoneos"):
        with patch.object(checker, "image_info", side_effect=lambda path: self.images[path]):
            return checker.inspect(self.app, self.root, configuration, sdk)

    def test_all_configuration_sdk_shapes_and_both_compiler_paths(self):
        for config in ("Debug", "Beta", "Release"):
            for sdk in ("iphoneos", "iphonesimulator"):
                self.write_plist(self.app / "Info.plist", {"CFBundleExecutable": "Host", "CFBundleIdentifier": "test.where",
                                                          "WhereConfiguration": config, "DTPlatformName": sdk})
                # Both source modes retain ordinary type metadata. Generated handlers are not a packaging requirement.
                self.support.write_bytes(thin(self.metadata))
                original = self.inspect(config, sdk)
                self.support.write_bytes(thin(self.metadata + [("_generated_private_binding", 0x0F, 1, 0, None)]))
                instrumented = self.inspect(config, sdk)
                self.assertEqual(original["status"], "passed")
                self.assertEqual(original["appIntents"], instrumented["appIntents"])
                self.assertEqual(len(original["hosts"]), 3)
                self.assertEqual(len(original["hosts"]["app"]["metadataFamilies"]), 7)

    def test_debug_loader_follows_the_app_debug_dylib_and_rejects_metadata_duplication(self):
        host = self.app / "Host"
        debug_image = self.app / "Where.debug.dylib"
        debug_image.write_bytes(thin())
        self.images[debug_image] = copy.deepcopy(self.images[host])
        self.images[host] = {"dependencies": ["@rpath/Where.debug.dylib"],
                             "rpaths": ["@executable_path", "@executable_path/Frameworks"]}
        self.assertIn("Where.debug.dylib", self.inspect()["hosts"]["app"]["images"])
        debug_image.write_bytes(thin([self.metadata[0]]))
        with self.assertRaisesRegex(ValueError, "outside the shared"):
            self.inspect()

    def move_to_build_product(self):
        original = self.app
        product = self.root / "Build/Products/Debug-iphoneos"
        product.mkdir(parents=True)
        self.app = product / "Where.app"
        shutil.move(original, self.app)
        self.images = {self.app / path.relative_to(original): value for path, value in self.images.items()}
        self.hosts = {name: self.app / path.relative_to(original) for name, path in self.hosts.items()}
        self.support = self.app / self.support.relative_to(original)
        self.intent_path = self.app / self.intent_path.relative_to(original)
        info = plistlib.loads((self.app / "Info.plist").read_bytes())
        info["WhereConfiguration"] = "Debug"
        self.write_plist(self.app / "Info.plist", info)
        package_outputs = product / "PackageFrameworks"
        shutil.copytree(self.app / "Frameworks", package_outputs)
        for info in self.images.values():
            info["rpaths"].insert(0, str(package_outputs))
        return package_outputs

    def test_debug_sibling_build_runpath_is_reported_and_requires_packaged_fallback(self):
        package_outputs = self.move_to_build_product()
        host = self.app / "Host"
        debug_image = self.app / "Where.debug.dylib"
        debug_image.write_bytes(thin())
        # The child needs the launcher's inherited Frameworks path after the build-only path is excluded.
        self.images[debug_image] = {"dependencies": copy.deepcopy(self.images[host]["dependencies"]),
                                    "rpaths": ["@loader_path", str(package_outputs)]}
        self.images[host] = {"dependencies": ["@rpath/Where.debug.dylib"],
                             "rpaths": ["@executable_path", str(package_outputs), "@executable_path/Frameworks"]}
        result = self.inspect("Debug")
        self.assertEqual(result["status"], "passed")
        self.assertIn("Where.debug.dylib", result["hosts"]["app"]["images"])
        self.assertEqual(result["excludedBuildRunpaths"]["Where.debug.dylib"], [str(package_outputs)])
        self.assertEqual(result["excludedBuildRunpaths"]["Host"], [str(package_outputs)])
        self.assertTrue(all(not path.startswith("/") and "PackageFrameworks" not in path for path in result["images"]))
        # An existing external copy must never substitute for the missing app copy.
        self.support.unlink()
        with self.assertRaises(FileNotFoundError):
            self.inspect("Debug")

    def test_build_runpath_exception_preserves_outside_and_symlink_rejections(self):
        package_outputs = self.move_to_build_product()
        host = self.app / "Host"
        original = copy.deepcopy(self.images[host])
        external = package_outputs / "WhereApplicationSupport.framework/WhereApplicationSupport"
        self.images[host]["dependencies"] = [str(external)]
        with self.assertRaisesRegex(ValueError, "outside-app"):
            self.inspect("Debug")
        self.images[host] = copy.deepcopy(original)
        arbitrary = self.root / "unrelated-frameworks"
        shutil.copytree(package_outputs, arbitrary)
        self.images[host]["rpaths"].insert(0, str(arbitrary))
        with self.assertRaisesRegex(ValueError, "outside-app"):
            self.inspect("Debug")
        self.images[host] = original
        self.support.unlink()
        self.support.symlink_to(external)
        with self.assertRaisesRegex(ValueError, "escapes its app"):
            self.inspect("Debug")

    def test_sibling_directory_without_verified_build_layout_is_not_excluded(self):
        package_outputs = self.app.parent / "PackageFrameworks"
        shutil.copytree(self.app / "Frameworks", package_outputs)
        self.images[self.app / "Host"]["rpaths"].insert(0, str(package_outputs))
        with self.assertRaisesRegex(ValueError, "outside-app"):
            self.inspect()

    def test_configuration_or_sdk_mismatch_fails(self):
        for config, sdk in [("Debug", "iphoneos"), ("Release", "iphonesimulator")]:
            with self.assertRaisesRegex(ValueError, "configuration/platform"):
                self.inspect(config, sdk)

    def test_unresolved_dependency_missing_shared_image_and_extra_extension_embed_fail(self):
        image = self.app / "Host"
        self.images[image]["rpaths"] = []
        with self.assertRaisesRegex(ValueError, "Unresolved"):
            self.inspect()
        self.images[image]["rpaths"] = ["@executable_path/Frameworks"]
        self.images[image]["dependencies"] = []
        with self.assertRaisesRegex(ValueError, "both shared"):
            self.inspect()
        duplicate = self.hosts["WhereWidgets.appex"] / "Frameworks/WhereApplicationSupport.framework"
        shutil.copytree(self.support.parent, duplicate)
        with self.assertRaisesRegex(ValueError, "one app-only"):
            self.inspect()

    def test_outside_app_image_and_resource_paths_fail(self):
        outside = self.root / "outside-image"
        outside.write_bytes(thin())
        self.images[self.app / "Host"]["dependencies"] = [str(outside)]
        with self.assertRaisesRegex(ValueError, "outside-app"):
            self.inspect()
        bundle = self.hosts["WhereWidgets.appex"] / "Stuff_WhereUI.bundle"
        shutil.rmtree(bundle)
        bundle.symlink_to(self.root)
        with self.assertRaisesRegex((ValueError, FileNotFoundError), "escapes|Info.plist"):
            checker.check_resources(self.hosts, self.app, self.root)

    def test_missing_and_duplicate_strong_or_weak_metadata_fail(self):
        self.support.write_bytes(thin(self.metadata[:-1]))
        with self.assertRaisesRegex(ValueError, "missing representative"):
            self.inspect()
        self.support.write_bytes(thin(self.metadata))
        for weak in (0, 0x80):
            (self.app / "Host").write_bytes(thin([(self.metadata[0][0], 0x0F, 1, weak, None)]))
            with self.assertRaisesRegex(ValueError, "outside the shared"):
                self.inspect()

    def test_alias_resolver_and_weak_disagreement_cannot_prove_ownership(self):
        name = self.metadata[0][0]
        alias = symbols.MachOSymbol(name, 1, symbols.N_INDR, 0, 0, "_elsewhere")
        with patch.object(symbols, "external_definitions", return_value=iter([alias])):
            with self.assertRaisesRegex(ValueError, "indirect alias"):
                checker.metadata_symbols(Path("unused"))
        for flag in (1, 2, 8, 16, 32):
            with patch.object(symbols, "external_definitions", return_value=iter([])), patch.object(
                    exports, "selected_exports", return_value=[exports.MachOExport(name, flag, 1, None, None)]):
                with self.assertRaisesRegex(ValueError, "not a direct regular export"):
                    checker.metadata_symbols(Path("unused"))
        strong = symbols.MachOSymbol(name, 1, symbols.N_SECT, 1, 0, None)
        with patch.object(symbols, "external_definitions", return_value=iter([strong])), patch.object(
                exports, "selected_exports", return_value=[exports.MachOExport(name, 4, 1, None, None)]):
            with self.assertRaisesRegex(ValueError, "disagree on weak"):
                checker.metadata_symbols(Path("unused"))

    def test_resource_payload_manifest_and_per_host_content_are_required(self):
        geometry = self.app / "Stuff_RegionKit.bundle/test.geojson"
        geometry.unlink()
        with self.assertRaises(FileNotFoundError):
            self.inspect()
        geometry.write_text('{"type":"FeatureCollection","features":[]}')
        localized = self.hosts["WhereShareExtension.appex"] / "Stuff_WhereUI.bundle/en.lproj/Localizable.strings"
        self.write_plist(localized, {"key": "different"})
        with self.assertRaisesRegex(ValueError, "resources differ"):
            self.inspect()
        self.write_plist(localized, {"key": "value"})
        (self.app / "Stuff_WhereUI.bundle/AppIcons.json").write_text('{"icons":[]}')
        with self.assertRaisesRegex(ValueError, "manifest differs"):
            self.inspect()

    def test_extension_metadata_catalogs_and_missing_or_changed_routes_fail(self):
        for location in [self.hosts["WhereWidgets.appex"], self.support.parent]:
            extra = location / "Metadata.appintents"
            extra.mkdir()
            with self.assertRaisesRegex(ValueError, "metadata outside"):
                self.inspect()
            extra.rmdir()
        changed = copy.deepcopy(self.intents)
        changed["autoShortcuts"][0]["actionIdentifier"] = "OtherIntent"
        self.intent_path.write_text(json.dumps(changed))
        with self.assertRaisesRegex(ValueError, "shortcut routes"):
            self.inspect()
        changed = copy.deepcopy(self.intents)
        del changed["actions"]["LogTripIntent"]
        self.intent_path.write_text(json.dumps(changed))
        with self.assertRaisesRegex(ValueError, "App Intents actions"):
            self.inspect()
        self.intent_path.write_text(json.dumps(self.intents))
        catalog = self.app / "Where.porthole.json"
        catalog.write_text("{}")
        with self.assertRaisesRegex(ValueError, "standalone"):
            self.inspect()

    def test_pair_ignores_only_opaque_compiled_asset_bytes_and_keeps_copy_equality(self):
        original = self.inspect()
        for host in self.hosts.values():
            (host / "Stuff_WhereAssets.bundle/Assets.car").write_bytes(b"new compiled timestamp")
        instrumented = self.inspect()
        self.assertNotEqual(original["resources"]["app"]["WhereAssets"]["sha256"],
                            instrumented["resources"]["app"]["WhereAssets"]["sha256"])
        contract.compare_packaging(original, instrumented)
        for host in self.hosts.values():
            self.write_plist(host / "Stuff_WhereUI.bundle/en.lproj/Localizable.strings", {"key": "changed"})
        with self.assertRaisesRegex(ValueError, "different packaging resources"):
            contract.compare_packaging(original, self.inspect())
        (self.app / "Stuff_WhereAssets.bundle/Assets.car").write_bytes(b"mismatched host copy")
        with self.assertRaisesRegex(ValueError, "resources differ"):
            self.inspect()

    def test_only_year_input_type_order_is_normalized(self):
        values = [{"type": 7}, {"type": 2}]
        action = self.intents["actions"]["DaysInRegionIntent"]
        action["parameters"] = [{"name": "year", "resolvableInputTypes": values},
                                {"name": "region", "resolvableInputTypes": values}]
        self.intent_path.write_text(json.dumps(self.intents))
        before = self.inspect()["appIntents"]
        action["parameters"][0]["resolvableInputTypes"] = list(reversed(values))
        self.intent_path.write_text(json.dumps(self.intents))
        year = self.inspect()["appIntents"]
        self.assertEqual(before["semanticSHA256"], year["semanticSHA256"])
        self.assertNotEqual(before["sha256"], year["sha256"])
        action["parameters"][1]["resolvableInputTypes"] = list(reversed(values))
        self.intent_path.write_text(json.dumps(self.intents))
        self.assertNotEqual(before["semanticSHA256"], self.inspect()["appIntents"]["semanticSHA256"])

    def test_report_created_by_another_call_is_not_overwritten(self):
        output = self.root / "race.json"
        def competing_report(*_):
            output.write_text("other invocation")
            return {"status": "passed"}
        args = ["--app", str(self.app), "--repository", str(self.root), "--configuration", "Release",
                "--sdk", "iphoneos", "--output", str(output)]
        with patch.object(checker, "inspect", side_effect=competing_report), self.assertRaises(FileExistsError):
            checker.main(args)
        self.assertEqual(output.read_text(), "other invocation")

    def test_command_writes_durable_failure_and_never_overwrites_a_report(self):
        output = self.root / "report.json"
        args = ["--app", str(self.app), "--repository", str(self.root), "--configuration", "Beta",
                "--sdk", "iphoneos", "--output", str(output)]
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(checker.main(args), 1)
        self.assertEqual(json.loads(output.read_text())["status"], "failed")
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            checker.main(args)


if __name__ == "__main__":
    unittest.main()
