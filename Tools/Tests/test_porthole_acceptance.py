from pathlib import Path
import json
import plistlib
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from porthole_acceptance import assignments, build_report, compare_bundles, executable_architectures, inspect_bundle, read_runtime_samples, summarize_runtime


def thin_executable(cpu_type=0x0100000C, cpu_subtype=0, byte_order="<", wide=True):
    """A minimal Mach-O executable header; these fixtures are never launched."""
    fields = [0xFEEDFACF if wide else 0xFEEDFACE, cpu_type, cpu_subtype, 2, 0, 0, 0]
    if wide:
        fields.append(0)
    return struct.pack(byte_order + "I" * len(fields), *fields)


def universal_executable(identities, byte_order=">", wide=False):
    """Wrap little-endian executable headers in a universal architecture table."""
    entry_format = byte_order + ("IIQQII" if wide else "IIIII")
    offset = 8 + len(identities) * struct.calcsize(entry_format)
    table = struct.pack(byte_order + "II", 0xCAFEBABF if wide else 0xCAFEBABE, len(identities))
    slices = b""
    for cpu_type, cpu_subtype in identities:
        payload = thin_executable(cpu_type, cpu_subtype)
        entry = [cpu_type, cpu_subtype, offset, len(payload), 0]
        if wide:
            entry.append(0)
        table += struct.pack(entry_format, *entry)
        slices += payload
        offset += len(payload)
    return table + slices


class PortholeAcceptanceTests(unittest.TestCase):
    def make_bundle(self, root, configuration="Debug", platform="iphonesimulator", executable=None):
        bundle = root / "Where.app"
        bundle.mkdir(parents=True)
        info = {"CFBundleExecutable": "Where", "CFBundleIdentifier": "com.stuff.where",
                "WhereConfiguration": configuration, "DTPlatformName": platform, "DTSDKBuild": "fixture",
                "DTXcodeBuild": "fixture", "WhereSwiftOptimizationLevel": "-Onone" if configuration == "Debug" else "-O",
                "WhereSwiftCompilationMode": "singlefile" if configuration == "Debug" else "wholemodule",
                "WhereGitSHA": "fixture-revision", "WhereGitStatus": "clean"}
        (bundle / "Info.plist").write_bytes(plistlib.dumps(info))
        (bundle / "Where").write_bytes(thin_executable() if executable is None else executable)
        return bundle

    def test_counts_regular_files_without_following_external_links(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bundle = self.make_bundle(root)
            outside = root / "outside"
            outside.mkdir()
            (outside / "large").write_bytes(b"x" * 10000)
            (bundle / "linked").symlink_to(outside)
            catalog = bundle / "Fixture.porthole.json"
            catalog.write_text("{}")
            result = inspect_bundle(bundle, "Debug")
            expected = sum(item.stat().st_size for item in (bundle / "Where", bundle / "Info.plist", catalog))
            self.assertEqual(result["logicalBytes"], expected)
            self.assertEqual(result["standalonePortholeCatalogFileBytes"], 2)
            self.assertEqual(result["portholeCatalogBytes"], result["standalonePortholeCatalogFileBytes"])
            self.assertEqual(result["symbolicLinksExcluded"], 1)

    def test_zero_standalone_catalog_bytes_does_not_claim_embedded_catalogs_are_free(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = thin_executable() + b"opaque compiled sourceArchiveJSON and coverageJSON bytes"
            bundle = self.make_bundle(root, executable=executable)
            framework = bundle / "Frameworks" / "Fixture.framework" / "Fixture"
            framework.parent.mkdir(parents=True)
            framework.write_bytes(b"opaque compiled module catalog bytes")
            report = build_report({"Debug": bundle}, {}, [])
            measured = report["configurations"]["Debug"]["bundle"]
            self.assertEqual(report["version"], 1)
            self.assertEqual(measured["standalonePortholeCatalogFileBytes"], 0)
            self.assertEqual(measured["portholeCatalogBytes"], 0)
            self.assertEqual(measured["executableBytes"], len(executable))
            self.assertEqual(measured["embeddedFrameworkBytes"], framework.stat().st_size)
            self.assertEqual(measured["logicalBytes"], len(executable) + framework.stat().st_size
                             + (bundle / "Info.plist").stat().st_size)
            self.assertIn("only standalone .porthole.json files", measured["catalogSizeDefinition"])
            self.assertIn("does not isolate the size of embedded catalogs or source archives",
                          measured["catalogSizeDefinition"])

    def test_rejects_empty_artifacts_and_wrong_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            bundle = self.make_bundle(Path(directory))
            with self.assertRaises(ValueError):
                inspect_bundle(bundle, "Beta")
            (bundle / "Where").write_bytes(b"")
            report = build_report({"Debug": bundle}, {}, [])
            self.assertEqual(report["configurations"]["Debug"]["bundle"]["status"], "rejected")
            self.assertEqual(report["configurations"]["Release"]["bundle"]["status"], "missing")
            self.assertEqual(report["acceptance"], "notEvaluated")

    def test_matching_missing_build_stamps_do_not_establish_comparability(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bundles = [self.make_bundle(root / name) for name in ("current", "baseline")]
            for bundle in bundles:
                path = bundle / "Info.plist"
                info = plistlib.loads(path.read_bytes())
                for key in ("DTXcodeBuild", "WhereSwiftOptimizationLevel", "WhereSwiftCompilationMode", "WhereGitSHA"):
                    del info[key]
                path.write_bytes(plistlib.dumps(info))
            result = build_report({"Debug": bundles[0]}, {"Debug": bundles[1]}, [])["configurations"]["Debug"]
            self.assertEqual(result["bundle"]["status"], "measured")
            self.assertEqual(result["baseline"]["status"], "measured")
            self.assertEqual(result["difference"]["status"], "rejected")
            for key in ("xcodeBuild", "optimization", "compilationMode", "buildIdentity"):
                self.assertIn(key, result["difference"]["reason"])
            self.assertNotIn("logicalByteDifference", result["difference"])

    def test_unknown_identity_on_either_side_rejects_comparison(self):
        with tempfile.TemporaryDirectory() as directory:
            known = inspect_bundle(self.make_bundle(Path(directory)), "Debug")
            fields = ("configuration", "bundleIdentifier", "platform", "sdkBuild", "xcodeBuild",
                      "optimization", "compilationMode", "buildIdentity")
            for key in fields:
                for invalid in (None, "", "  ", "unknown", " Unknown ", 17):
                    incomplete = {**known, key: invalid}
                    for current, baseline in ((known, incomplete), (incomplete, known), (incomplete, incomplete)):
                        with self.subTest(field=key, invalid=invalid):
                            result = compare_bundles(current, baseline)
                            self.assertEqual(result["status"], "rejected")
                            self.assertIn(key, result["reason"])
                            self.assertNotIn("logicalByteDifference", result)

    def test_known_different_source_revisions_remain_comparable(self):
        with tempfile.TemporaryDirectory() as directory:
            current = inspect_bundle(self.make_bundle(Path(directory)), "Debug")
            baseline = {**current, "buildIdentity": "earlier-fixture-revision"}
            self.assertEqual(compare_bundles(current, baseline)["status"], "measured")

    def test_rejects_comparison_between_device_and_simulator(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            simulator = inspect_bundle(self.make_bundle(root / "sim"), "Debug")
            device = inspect_bundle(self.make_bundle(root / "device", platform="iphoneos"), "Debug")
            self.assertEqual(compare_bundles(device, simulator)["status"], "rejected")
            self.assertEqual(compare_bundles(device, device)["logicalByteDifference"], 0)

    def test_rejects_comparison_between_thin_and_multiple_architecture_simulator_apps(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            arm64 = inspect_bundle(self.make_bundle(root / "arm64"), "Debug")
            universal = inspect_bundle(self.make_bundle(root / "universal", executable=universal_executable(
                [(0x0100000C, 0), (0x01000007, 3)])), "Debug")
            self.assertEqual([item["name"] for item in arm64["architectures"]], ["arm64"])
            self.assertEqual([item["name"] for item in universal["architectures"]], ["x86_64", "arm64"])
            for current, baseline in ((arm64, universal), (universal, arm64)):
                difference = compare_bundles(current, baseline)
                self.assertEqual(difference["status"], "rejected")
                self.assertIn("architectures", difference["reason"])
                self.assertNotIn("logicalByteDifference", difference)

    def test_matching_architectures_preserve_logical_byte_difference(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            baseline = inspect_bundle(self.make_bundle(root / "baseline"), "Debug")
            current = inspect_bundle(self.make_bundle(root / "current", executable=thin_executable() + b"payload"), "Debug")
            difference = compare_bundles(current, baseline)
            self.assertEqual(difference["status"], "measured")
            self.assertEqual(difference["logicalByteDifference"], 7)
            self.assertEqual(difference["executableByteDifference"], 7)
            del baseline["architectures"]
            self.assertEqual(compare_bundles(current, baseline)["status"], "rejected")

    def test_reads_both_byte_orders_and_header_widths(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "fixture"
            for byte_order in ("<", ">"):
                for wide, cpu_type, cpu_subtype, name in ((False, 7, 3, "i386"), (True, 0x0100000C, 0, "arm64")):
                    with self.subTest(byte_order=byte_order, wide=wide):
                        executable.write_bytes(thin_executable(cpu_type, cpu_subtype, byte_order, wide))
                        self.assertEqual(executable_architectures(executable), [
                            {"name": name, "cpuType": cpu_type, "cpuSubtype": cpu_subtype}])

    def test_reads_universal_formats_and_ignores_slice_order(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            forward = [(0x0100000C, 0), (0x01000007, 3)]
            expected = [{"name": "x86_64", "cpuType": 0x01000007, "cpuSubtype": 3},
                        {"name": "arm64", "cpuType": 0x0100000C, "cpuSubtype": 0}]
            for byte_order in ("<", ">"):
                for wide in (False, True):
                    for identities in (forward, forward[::-1]):
                        with self.subTest(byte_order=byte_order, wide=wide, identities=identities):
                            executable = root / "fixture"
                            executable.write_bytes(universal_executable(identities, byte_order, wide))
                            self.assertEqual(executable_architectures(executable), expected)

    def test_compares_cpu_subtype_and_capability_bits(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for cpu_type, baseline_subtype, current_subtype in ((0x01000007, 3, 8), (0x0100000C, 2, 0x80000002)):
                baseline = inspect_bundle(self.make_bundle(root / str(cpu_type) / "baseline", executable=thin_executable(
                    cpu_type, baseline_subtype)), "Debug")
                current = inspect_bundle(self.make_bundle(root / str(cpu_type) / "current", executable=thin_executable(
                    cpu_type, current_subtype)), "Debug")
                self.assertEqual(compare_bundles(current, baseline)["status"], "rejected")

    def test_rejects_unrecognized_and_incomplete_executable_data_in_reports(self):
        valid_fat = universal_executable([(0x0100000C, 0), (0x01000007, 3)])
        mismatched_fat = bytearray(valid_fat)
        struct.pack_into(">I", mismatched_fat, 8, 0x01000007)
        overlapping_fat = bytearray(valid_fat)
        struct.pack_into(">I", overlapping_fat, 36, 48)
        bad_commands = bytearray(thin_executable())
        struct.pack_into("<II", bad_commands, 16, 1, 8)
        bad_file_type = bytearray(thin_executable())
        struct.pack_into("<I", bad_file_type, 12, 6)
        cases = {
            "unrecognized": b"synthetic Mach-O fixture",
            "short_magic": b"\xcf\xfa",
            "short_header": thin_executable()[:16],
            "unknown_architecture": thin_executable(99, 0),
            "wrong_header_width": thin_executable(wide=False),
            "load_commands_out_of_bounds": bad_commands,
            "dylib_is_not_app_executable": bad_file_type,
            "empty_architecture_table": struct.pack(">II", 0xCAFEBABE, 0),
            "short_architecture_table": valid_fat[:20],
            "truncated_slice": valid_fat[:-1],
            "slice_disagrees_with_table": mismatched_fat,
            "overlapping_slices": overlapping_fat,
            "duplicate_architecture": universal_executable([(0x0100000C, 0), (0x0100000C, 0)]),
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, data in cases.items():
                with self.subTest(name=name):
                    bundle = self.make_bundle(root / name, executable=data)
                    report = build_report({"Debug": bundle}, {"Debug": bundle}, [])
                    configuration = report["configurations"]["Debug"]
                    self.assertEqual(configuration["bundle"]["status"], "rejected")
                    self.assertTrue(configuration["bundle"]["reason"])
                    self.assertNotIn("logicalByteDifference", configuration["difference"])

    def test_runtime_samples_require_evidence_and_preserve_platform_and_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = root / "capture.trace"
            evidence.write_text("synthetic test evidence")
            sample = {"configuration": "Debug", "variant": "portholeDisabled", "metric": "launchMilliseconds",
                      "value": 10, "platform": "macOS", "hardware": "test fixture", "osVersion": "fixture",
                      "buildIdentity": "fixture", "method": "fixture only", "coldStart": True,
                      "recordedAt": "2026-09-13T00:00:00Z", "evidencePath": "capture.trace"}
            path = root / "samples.json"
            path.write_text(json.dumps({"version": 1, "samples": [sample, {**sample, "value": 20}]}))
            loaded = read_runtime_samples(path)
            summary = summarize_runtime(loaded, "Debug")
            self.assertEqual(summary["status"], "incomplete")
            self.assertEqual(summary["groups"][0]["median"], 15)
            self.assertEqual(summary["groups"][0]["platform"], "macOS")
            evidence.unlink()
            with self.assertRaises(ValueError):
                read_runtime_samples(path)

    def test_duplicate_configuration_is_rejected(self):
        with self.assertRaises(ValueError):
            assignments(["Debug=/one", "Debug=/two"])


if __name__ == "__main__":
    unittest.main()
