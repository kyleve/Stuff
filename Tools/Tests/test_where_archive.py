import tempfile
import unittest

from Fixtures.where_distribution_fixtures import ArchiveFixture


class WhereArchiveTests(unittest.TestCase):
    def test_local_archive_preserves_project_defaults_instead_of_unknown_overrides(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixture = ArchiveFixture(temporary)
            result = fixture.run("Where/archive", "--profiles", fixture.profiles, "--output", fixture.output)
            self.assertEqual(result.returncode, 0, result.stderr)
            archive = next(command for command in fixture.commands() if "archive" in command)
            installer_settings = [argument for argument in archive if argument.startswith("INSTALLER_")]
            self.assertEqual(installer_settings, ["INSTALLER_APP_ID=where"])

    def test_signed_archive_precedes_export_and_preserves_optimized_debug(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixture = ArchiveFixture(temporary)
            metadata = {"INSTALLER_CHANNEL": "pr-42", "INSTALLER_RUN": "12", "INSTALLER_ATTEMPT": "2",
                        "INSTALLER_FEED_URL": "https://fixture.github.io/Stuff/updates.json",
                        "INSTALLER_REPOSITORY_URL": "https://github.com/fixture/Stuff"}
            result = fixture.run("Where/archive", "--profiles", fixture.profiles, "--output", fixture.output,
                                 overrides=metadata)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((fixture.output / "export/Where.ipa").is_file())
            builds = [command for command in fixture.commands() if command[0] == "mise"]
            self.assertEqual([command[4] for command in builds], ["-showBuildSettings", "archive", "-exportArchive"])
            self.assertIn("SWIFT_OPTIMIZATION_LEVEL=-O", builds[1])
            self.assertIn("Debug", builds[1])
            self.assertIn("INSTALLER_APP_ID=where", builds[1])
            for key, value in metadata.items():
                self.assertIn(f"{key}={value}", builds[1])
            self.assertIn(["ide", "--no-open"], fixture.commands())
            self.assertEqual(list(fixture.temporary.iterdir()), [])

    def test_existing_output_and_missing_profiles_fail_before_any_process(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixture = ArchiveFixture(temporary)
            fixture.output.mkdir()
            result = fixture.run("Where/archive", "--profiles", fixture.profiles, "--output", fixture.output)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("already exists", result.stderr)
            fixture.output.rmdir()
            (fixture.profiles / "WhereWidgets.mobileprovision").unlink()
            result = fixture.run("Where/archive", "--profiles", fixture.profiles, "--output", fixture.output)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing", result.stderr)
            self.assertEqual(fixture.commands(), [])
            self.assertFalse(fixture.output.exists())

    def test_failed_generation_settings_archive_and_export_stop_at_boundary(self):
        for failure in ("ide:--no-open", "mise:-showBuildSettings", "mise:archive", "mise:-exportArchive"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                fixture = ArchiveFixture(temporary)
                result = fixture.run("Where/archive", "--profiles", fixture.profiles, "--output", fixture.output,
                                     overrides={"FAIL_AT": failure})
                self.assertEqual(result.returncode, 47, result.stderr)
                self.assertFalse((fixture.output / "export/Where.ipa").exists())
                self.assertEqual(list(fixture.temporary.iterdir()), [])
                if failure != "mise:-exportArchive":
                    self.assertFalse(any("-exportArchive" in command for command in fixture.commands()))

    def test_settings_mismatch_prevents_archive_and_missing_export_is_failure(self):
        for override in ("WRONG_BUNDLE", "MISSING_IPA"):
            with self.subTest(override=override), tempfile.TemporaryDirectory() as temporary:
                fixture = ArchiveFixture(temporary)
                result = fixture.run("Where/archive", "--profiles", fixture.profiles, "--output", fixture.output,
                                     overrides={override: "1"})
                self.assertNotEqual(result.returncode, 0)
                if override == "WRONG_BUNDLE":
                    self.assertFalse(fixture.output.exists())
                    self.assertFalse(any("archive" in command for command in fixture.commands()))
