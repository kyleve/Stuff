import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("porthole_compiler_contract", ROOT / "Tools/porthole_compiler_contract.py")
CONTRACT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONTRACT)


def compiler_line(module, configuration, sdk, original):
    _, optimization, condition = CONTRACT.CONFIGURATIONS[configuration]
    tokens = ["builtin-SwiftDriver", "--", "/Xcode/toolchain/bin/swiftc", "-module-name", module,
              "-sdk", f"/Xcode/{sdk}.sdk", "-target", "arm64-apple-ios26.0" + ("-simulator" if sdk == "iphonesimulator" else ""),
              "-swift-version", "6", optimization, "-D", "SWIFT_PACKAGE"]
    if configuration != "Debug":
        tokens.append("-whole-module-optimization")
    if configuration == "Debug":
        tokens.extend(["-D", "DEBUG"])
    if module == "Where":
        tokens.extend(["-D", condition])
    if original:
        tokens.append("-DPORTHOLE_ORIGINAL_SOURCE_CHECK")
    else:
        tokens.extend(["-Xfrontend", "-disable-access-control", "-enable-private-imports"])
    tokens.extend(["-c", "@/build/file list.SwiftFileList"])
    return "    " + shlex.join(tokens) + "\n"


class PortholeCompilerContractTests(unittest.TestCase):
    def evidence(self, text, configuration="Debug", sdk="iphonesimulator", original=False, modules=None):
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary) / "build.log"
            log.write_text(text)
            return CONTRACT.compiler_evidence(log, modules or {"Where"}, configuration, sdk,
                                              Path(f"/Xcode/{sdk}.sdk"), Path("/Xcode/toolchain/bin/swiftc"), original)

    def test_all_six_pairs_preserve_actual_settings(self):
        for configuration in CONTRACT.CONFIGURATIONS:
            for sdk in CONTRACT.DESTINATIONS:
                with self.subTest(configuration=configuration, sdk=sdk):
                    pair = [self.evidence("".join(compiler_line(module, configuration, sdk, original)
                                                  for module in ["Where", "WhereCore"]),
                                          configuration, sdk, original, {"Where", "WhereCore"})
                            for original in [True, False]]
                    CONTRACT.compare(*pair)
                    self.assertEqual(pair[0]["Where"]["compilationMode"], "singlefile" if configuration == "Debug" else "wholemodule")

    def test_command_has_identical_explicit_settings_for_each_build(self):
        for configuration in CONTRACT.CONFIGURATIONS:
            for sdk in CONTRACT.DESTINATIONS:
                pair = [CONTRACT.build_command(configuration, sdk, Path("/SDK"), Path("/" + variant), 2)
                        for variant in ["original", "instrumented"]]
                differences = [(a, b) for a, b in zip(*pair) if a != b]
                self.assertEqual(differences, [("/original", "/instrumented")])
                self.assertIn("ARCHS=arm64", pair[0])
                self.assertIn("CODE_SIGNING_ALLOWED=NO", pair[0])
                self.assertFalse(any(item.startswith(("SWIFT_COMPILATION_MODE=", "SWIFT_OPTIMIZATION_LEVEL=")) for item in pair[0]))
                self.assertEqual(CONTRACT.argument(pair[0], "-jobs"), "2")
                self.assertEqual(CONTRACT.argument(pair[0], "-destination"), CONTRACT.DESTINATIONS[sdk])
        with self.assertRaisesRegex(ValueError, "positive"):
            CONTRACT.build_command("Debug", "iphoneos", Path("/SDK"), Path("/products"), 0)

    def test_environment_sets_both_guards_and_preserves_other_conditions(self):
        base = {CONTRACT.GUARD: "unexpected", "TUIST_" + CONTRACT.GUARD: "unexpected",
                "SDKROOT": "/iPhoneOS.sdk", "SWIFT_EXEC": "/alternate/swift", "OTHER": "keep"}
        for original in [True, False]:
            env = CONTRACT.environment(base, original, "Beta")
            self.assertEqual(env[CONTRACT.GUARD], "1" if original else "0")
            self.assertEqual(env["TUIST_" + CONTRACT.GUARD], env[CONTRACT.GUARD])
            self.assertEqual(env["OTHER"], "keep")
            self.assertEqual(env["PORTHOLE_BUILD_CONFIGURATION"], "Beta")
            self.assertNotIn("SDKROOT", env)
            self.assertNotIn("SWIFT_EXEC", env)
        self.assertEqual(base[CONTRACT.GUARD], "unexpected")

    def test_module_inventory_tracks_manifest_opt_in(self):
        package = {"targets": [{"name": "NewCore", "pluginUsages": [{"plugin": ["PortholeBuildPlugin", None]}]},
                               {"name": "PortholeCredentials", "pluginUsages": []}]}
        self.assertEqual(CONTRACT.exported_modules(package), {"Where", "NewCore"})
        with self.assertRaisesRegex(ValueError, "no Porthole"):
            CONTRACT.exported_modules({"targets": []})

    def test_missing_and_cached_module_commands_cannot_pass(self):
        with self.assertRaisesRegex(ValueError, "WhereCore"):
            self.evidence(compiler_line("Where", "Debug", "iphonesimulator", False), modules={"Where", "WhereCore"})
        with self.assertRaisesRegex(ValueError, "No compiler invocation"):
            self.evidence("** BUILD SUCCEEDED **\n")

    def test_wrong_flags_and_guard_conditions_fail(self):
        original = compiler_line("Where", "Debug", "iphonesimulator", True)
        instrumented = compiler_line("Where", "Debug", "iphonesimulator", False)
        for line, is_original, expected in [
            (original.replace("-DPORTHOLE_ORIGINAL_SOURCE_CHECK", ""), True, "condition"),
            (original + "", False, "private-access"),
            (instrumented, True, "private-access"),
            (instrumented.replace("-enable-private-imports", ""), False, "private-access"),
            (instrumented + " -DPORTHOLE_ORIGINAL_SOURCE_CHECK", False, "condition"),
        ]:
            with self.subTest(line=line), self.assertRaisesRegex(ValueError, expected):
                self.evidence(line.replace("\n", " ") + "\n", original=is_original)

    def test_wrong_toolchain_sdk_architecture_and_optimization_fail(self):
        line = compiler_line("Where", "Debug", "iphonesimulator", False)
        for before, after, expected in [
            ("/Xcode/toolchain/bin/swiftc", "/Other/bin/swiftc", "toolchain"),
            ("/Xcode/iphonesimulator.sdk", "/Other/iphonesimulator.sdk", "SDK"),
            ("arm64-apple-ios26.0-simulator", "x86_64-apple-ios26.0-simulator", "architecture"),
            ("arm64-apple-ios26.0-simulator", "arm64-apple-ios26.0", "destination"),
            ("-Onone", "-O", "-Onone"),
            ("WHERE_DEVELOPMENT", "WHERE_BETA", "audience"),
        ]:
            with self.subTest(before=before, after=after), self.assertRaisesRegex(ValueError, expected):
                self.evidence(line.replace(before, after))

    def test_multiple_inconsistent_invocations_fail(self):
        line = compiler_line("Where", "Debug", "iphonesimulator", False)
        with self.assertRaisesRegex(ValueError, "inconsistent"):
            self.evidence(line + line.replace("-D DEBUG", "-D ANOTHER_CONDITION"))

    def test_quoted_toolchain_paths_remain_compiler_evidence(self):
        compiler = Path("/Xcode Beta/toolchain/bin/swiftc")
        line = compiler_line("Where", "Debug", "iphonesimulator", False)
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary) / "build.log"
            log.write_text(line.replace("/Xcode/toolchain/bin/swiftc", shlex.quote(str(compiler))))
            facts = CONTRACT.compiler_evidence(log, {"Where"}, "Debug", "iphonesimulator",
                                               Path("/Xcode/iphonesimulator.sdk"), compiler, False)
            self.assertEqual(facts["Where"]["toolchain"], str(compiler.parent))

    def test_normalized_pair_still_rejects_different_compiler_conditions(self):
        original = self.evidence(compiler_line("Where", "Debug", "iphonesimulator", True), original=True)
        changed = copy.deepcopy(original)
        changed["Where"]["conditions"].append("UNRELATED")
        with self.assertRaisesRegex(ValueError, "different compiler settings"):
            CONTRACT.compare(original, changed)
        with self.assertRaisesRegex(ValueError, "module sets"):
            CONTRACT.compare(original, {})

    def test_package_modes_and_optimization_stay_target_owned_but_must_match(self):
        line = compiler_line("Core", "Beta", "iphoneos", False)
        facts = self.evidence(line.replace("-O", "-Osize").replace("-whole-module-optimization", ""),
                              "Beta", "iphoneos", modules={"Core"})
        self.assertEqual(facts["Core"]["optimization"], "-Osize")
        self.assertEqual(facts["Core"]["compilationMode"], "singlefile")
        for field, replacement in [("optimization", "-O"), ("compilationMode", "wholemodule")]:
            changed = copy.deepcopy(facts)
            changed["Core"][field] = replacement
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "different compiler settings"):
                CONTRACT.compare(facts, changed)

    def fake_runner(self, commands, *, failure=None, version="Build version 27A5252f", diagnostic=None):
        def run(command, *, root, env, log):
            commands.append((command, env))
            if failure == log.stem:
                raise subprocess.CalledProcessError(65, command)
            output = ""
            if log.stem == "xcode-version":
                output = "Xcode 27.0\n" + version + "\n"
            elif log.stem == "compiler-path":
                output = "/Xcode/toolchain/bin/swiftc\n"
            elif log.stem == "compiler-version":
                output = "Apple Swift version 6.3\n"
            elif log.stem == "sdk-path":
                output = "/Xcode/iphoneos.sdk\n"
            elif log.stem.endswith("-package"):
                output = json.dumps({"targets": [{"name": "WhereCore", "pluginUsages": [{"plugin": ["PortholeBuildPlugin", None]}]}]})
            elif log.stem.endswith("-packaging"):
                report = {"status": "passed", "configuration": "Beta", "sdk": "iphoneos",
                          "resources": {"app": {"RegionKit": {"files": 1, "crossBuildSHA256": "same", "opaqueCompiledFiles": []}}},
                          "appIntents": {"semanticSHA256": "same"}}
                Path(CONTRACT.argument(command, "--output")).write_text(json.dumps(report))
            elif log.stem.endswith("-build"):
                output = "".join(compiler_line(module, "Beta", "iphoneos", env[CONTRACT.GUARD] == "1")
                                 for module in ["Where", "WhereCore"])
            log.write_text(output)
            errors = log.with_suffix(".stderr.log")
            errors.write_text("")
            if diagnostic is not None and log.stem == "original-build":
                destination, text = diagnostic
                with (log if destination == "stdout" else errors).open("a") as stream:
                    stream.write(text + "\n")
        return run

    def test_orchestration_builds_paired_fresh_products_and_writes_evidence(self):
        with tempfile.TemporaryDirectory() as temporary, contextlib.redirect_stdout(io.StringIO()):
            root = Path(temporary)
            (root / ".xcode-build-version").write_text("27A5252f\n")
            commands = []
            output = root / "evidence"
            result = CONTRACT.run_contract(root, output, "Beta", "iphoneos", 2, run=self.fake_runner(commands))
            self.assertEqual(result["state"], "passed")
            self.assertEqual(result, json.loads((output / "result.json").read_text()))
            builds = [(command, env) for command, env in commands if "xcodebuild" in command and "build" in command]
            self.assertEqual([env[CONTRACT.GUARD] for _, env in builds], ["1", "0"])
            self.assertEqual([env["TUIST_" + CONTRACT.GUARD] for _, env in builds], ["1", "0"])
            self.assertNotEqual(CONTRACT.argument(builds[0][0], "-derivedDataPath"), CONTRACT.argument(builds[1][0], "-derivedDataPath"))
            self.assertEqual(sum(command == ["./ide", "--no-open"] for command, _ in commands), 2)
            packaging = [(command, env) for command, env in commands if any("porthole_packaging.py" in item for item in command)]
            self.assertEqual(len(packaging), 2)
            self.assertEqual([env[CONTRACT.GUARD] for _, env in packaging], ["1", "0"])
            self.assertTrue(CONTRACT.argument(packaging[0][0], "--app").endswith("original-products/Build/Products/Beta-iphoneos/Where.app"))
            self.assertTrue(CONTRACT.argument(packaging[1][0], "--app").endswith("instrumented-products/Build/Products/Beta-iphoneos/Where.app"))
            self.assertEqual(result["originalPackaging"], "original-packaging.json")
            self.assertEqual(result["instrumentedPackaging"], "instrumented-packaging.json")
            self.assertGreater(commands.index(packaging[0]), commands.index(builds[-1]))
            with self.assertRaisesRegex(ValueError, "already exists"):
                CONTRACT.run_contract(root, output, "Beta", "iphoneos", 2, run=self.fake_runner(commands))

    def test_build_failure_stops_the_pair_and_keeps_honest_state(self):
        with tempfile.TemporaryDirectory() as temporary, contextlib.redirect_stdout(io.StringIO()):
            root = Path(temporary)
            (root / ".xcode-build-version").write_text("27A5252f\n")
            commands = []
            output = root / "evidence"
            with self.assertRaises(subprocess.CalledProcessError):
                CONTRACT.run_contract(root, output, "Beta", "iphoneos", 2,
                                      run=self.fake_runner(commands, failure="original-build"))
            result = json.loads((output / "result.json").read_text())
            self.assertEqual(result["state"], "failed")
            self.assertEqual(result["steps"][-1]["name"], "original-build")
            self.assertEqual(result["steps"][-1]["state"], "failed")
            self.assertNotIn("instrumented", result)

    def test_packaging_failure_marks_completed_build_pair_failed(self):
        with tempfile.TemporaryDirectory() as temporary, contextlib.redirect_stdout(io.StringIO()):
            root = Path(temporary)
            (root / ".xcode-build-version").write_text("27A5252f\n")
            with self.assertRaises(subprocess.CalledProcessError):
                CONTRACT.run_contract(root, root / "evidence", "Beta", "iphoneos", 2,
                                      run=self.fake_runner([], failure="instrumented-packaging"))
            result = json.loads((root / "evidence/result.json").read_text())
            self.assertEqual(result["state"], "failed")
            self.assertEqual(result["steps"][-1]["name"], "instrumented-packaging")
            self.assertEqual(result["steps"][-1]["state"], "failed")
            self.assertIn("original", result)
            self.assertIn("instrumented", result)

    def test_packaging_comparison_rejects_route_or_resource_differences(self):
        original = {"configuration": "Release", "sdk": "iphoneos", "resources": {"app": {"RegionKit": {"files": 1, "crossBuildSHA256": "same", "opaqueCompiledFiles": []}}},
                    "appIntents": {"semanticSHA256": "same"}}
        CONTRACT.compare_packaging(original, copy.deepcopy(original))
        for field, value in [("configuration", "Beta"), ("sdk", "iphonesimulator"), ("resources", {})]:
            changed = copy.deepcopy(original)
            changed[field] = value
            with self.assertRaisesRegex(ValueError, "different packaging"):
                CONTRACT.compare_packaging(original, changed)
        changed = copy.deepcopy(original)
        changed["appIntents"]["semanticSHA256"] = "changed"
        with self.assertRaisesRegex(ValueError, "different App Intents"):
            CONTRACT.compare_packaging(original, changed)

    def test_extension_diagnostic_scan_checks_both_streams_without_rejecting_other_warnings(self):
        failures = ["ld: warning: dylib is not safe for use in application extensions",
                    "warning: API unavailable in app extensions",
                    "error: extension-unsafe API", "warning: application extensions: API is unavailable"]
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary) / "build.log"
            errors = log.with_suffix(".stderr.log")
            for destination in (log, errors):
                for message in failures:
                    with self.subTest(destination=destination.name, message=message):
                        log.write_text("ordinary build line\n")
                        errors.write_text("unrelated warning: unused value\n")
                        with destination.open("a") as stream:
                            stream.write(message + "\n")
                        with self.assertRaisesRegex(ValueError, "Extension-unsafe diagnostic in " + destination.name + ":2"):
                            CONTRACT.check_extension_diagnostics(log)
            log.write_text("Build task: extension-safe API\n")
            errors.write_text("warning: unused value\n")
            CONTRACT.check_extension_diagnostics(log)
            errors.unlink()
            with self.assertRaises(FileNotFoundError):
                CONTRACT.check_extension_diagnostics(log)
            errors.write_bytes(b"x" * (CONTRACT.MAX_BUILD_LOG_LINE_BYTES + 1))
            with self.assertRaisesRegex(ValueError, "line exceeds"):
                CONTRACT.check_extension_diagnostics(log)
            with errors.open("wb") as stream:
                stream.truncate(CONTRACT.MAX_BUILD_LOG_BYTES + 1)
            with self.assertRaisesRegex(ValueError, "bounded diagnostic scan"):
                CONTRACT.check_extension_diagnostics(log)

    def test_zero_exit_build_with_extension_warning_stops_pair_and_marks_step_failed(self):
        for destination in ("stdout", "stderr"):
            with self.subTest(destination=destination), tempfile.TemporaryDirectory() as temporary, contextlib.redirect_stdout(io.StringIO()):
                root = Path(temporary)
                (root / ".xcode-build-version").write_text("27A5252f\n")
                commands = []
                output = root / "evidence"
                with self.assertRaisesRegex(ValueError, "Extension-unsafe diagnostic"):
                    CONTRACT.run_contract(root, output, "Beta", "iphoneos", 2,
                        run=self.fake_runner(commands, diagnostic=(destination, "ld: warning: image is not safe for use in application extensions")))
                result = json.loads((output / "result.json").read_text())
                self.assertEqual(result["state"], "failed")
                self.assertEqual(result["steps"][-1]["name"], "original-build")
                self.assertEqual(result["steps"][-1]["state"], "failed")
                self.assertNotIn("original", result)
                self.assertFalse(any(env[CONTRACT.GUARD] == "0" and "build" in command for command, env in commands))

    def test_wrong_or_missing_xcode_version_fails_before_generation(self):
        for version in ["Build version Other", "no build version"]:
            with self.subTest(version=version), tempfile.TemporaryDirectory() as temporary, contextlib.redirect_stdout(io.StringIO()):
                root = Path(temporary)
                (root / ".xcode-build-version").write_text("27A5252f\n")
                commands = []
                with self.assertRaisesRegex(ValueError, "pinned Xcode"):
                    CONTRACT.run_contract(root, root / "evidence", "Beta", "iphoneos", 2,
                                          run=self.fake_runner(commands, version=version))
                self.assertEqual(len(commands), 1)

    def test_runner_keeps_diagnostics_out_of_machine_readable_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            log = root / "manifest.log"
            CONTRACT.run_command([sys.executable, "-c", "import sys; print('{}'); print('warning: example', file=sys.stderr)"],
                                 root=root, env=os.environ.copy(), log=log)
            self.assertEqual(json.loads(log.read_text()), {})
            self.assertEqual((root / "manifest.stderr.log").read_text(), "warning: example\n")


if __name__ == "__main__":
    unittest.main()
