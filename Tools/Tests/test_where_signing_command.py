import base64
from pathlib import Path
import tempfile
import unittest

from Fixtures.where_distribution_fixtures import ArchiveFixture, TARGET_NAMES


class WhereSigningCommandTests(unittest.TestCase):
    def signing_environment(self, fixture):
        values = {
            "WHERE_SIGNING_DIR": str(fixture.temporary / "where-signing-fixture"),
            "WHERE_DISTRIBUTION_CERTIFICATE_BASE64": base64.b64encode(b"fixture certificate").decode(),
            "WHERE_DISTRIBUTION_CERTIFICATE_PASSWORD": "fixture password",
        }
        for target, key in zip(TARGET_NAMES, ("APP", "WIDGET", "SHARE")):
            values[f"WHERE_{key}_PROFILE_BASE64"] = base64.b64encode(
                (fixture.profiles / f"{target}.mobileprovision").read_bytes()).decode()
        return values

    def test_cleanup_restores_search_list_and_removes_only_owned_material(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixture = ArchiveFixture(temporary)
            environment = self.signing_environment(fixture)
            profile_root = fixture.home / "Library/Developer/Xcode/UserData/Provisioning Profiles"
            profile_root.mkdir(parents=True)
            existing = profile_root / "unrelated.mobileprovision"
            existing.write_bytes(b"existing profile")
            result = fixture.run(".github/where-signing.sh", "prepare", overrides=environment)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(list(profile_root.iterdir())), 4)
            result = fixture.run(".github/where-signing.sh", "cleanup", overrides=environment)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(list(profile_root.iterdir()), [existing])
            self.assertEqual(existing.read_bytes(), b"existing profile")
            self.assertFalse(Path(environment["WHERE_SIGNING_DIR"]).exists())
            self.assertIn(["security", "list-keychains", "-d", "user", "-s", "/fixture/login.keychain-db"],
                          fixture.commands())

    def test_partial_setup_is_cleaned_and_failed_cleanup_retains_recovery_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixture = ArchiveFixture(temporary)
            environment = self.signing_environment(fixture)
            result = fixture.run(".github/where-signing.sh", "prepare",
                                 overrides={**environment, "FAIL_AT": "security:import"})
            self.assertEqual(result.returncode, 47)
            result = fixture.run(".github/where-signing.sh", "cleanup",
                                 overrides={**environment, "FAIL_AT": "security:delete-keychain"})
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Recovery files remain", result.stderr)
            self.assertTrue(Path(environment["WHERE_SIGNING_DIR"]).is_dir())
            result = fixture.run(".github/where-signing.sh", "cleanup", overrides=environment)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(Path(environment["WHERE_SIGNING_DIR"]).exists())

    def test_preexisting_state_is_neither_replaced_nor_deleted(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixture = ArchiveFixture(temporary)
            environment = self.signing_environment(fixture)
            state = Path(environment["WHERE_SIGNING_DIR"])
            state.mkdir()
            sentinel = state / "unrelated"
            sentinel.touch()
            for command in ("prepare", "cleanup"):
                result = fixture.run(".github/where-signing.sh", command, overrides=environment)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(sentinel.exists())
            self.assertEqual(fixture.commands(), [])

    def test_failed_search_list_read_does_not_restore_partial_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixture = ArchiveFixture(temporary)
            environment = self.signing_environment(fixture)
            result = fixture.run(".github/where-signing.sh", "prepare",
                                 overrides={**environment, "FAIL_AT": "security:list-keychains"})
            self.assertEqual(result.returncode, 47)
            result = fixture.run(".github/where-signing.sh", "cleanup", overrides=environment)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(Path(environment["WHERE_SIGNING_DIR"]).exists())
            keychain_commands = [command for command in fixture.commands() if "list-keychains" in command]
            self.assertEqual(keychain_commands, [["security", "list-keychains", "-d", "user"]])
