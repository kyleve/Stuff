"""Credential discovery and hidden prompting without developer secrets or Keychain access."""

import getpass
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock
import warnings

from Tools.InstallerKit.installer_setup_credentials import signing_environment


class InstallerSetupCredentialsTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="credentials ü ")
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.key = self.home / ".config/stuff/signing/app-store-connect.json"
        self.key.parent.mkdir(parents=True)
        self.key.write_text(
            json.dumps(
                {
                    "key_id": "fixture",
                    "issuer_id": "fixture",
                    "key": "fixture-private-key",
                }
            )
        )

    def test_default_key_and_environment_password_need_no_prompt(self):
        environment = {"MATCH_PASSWORD": "fixture-password"}
        prompt = Mock(side_effect=AssertionError("No prompt expected"))
        result = signing_environment(environment, self.home, False, prompt)
        self.assertEqual(result["INSTALLER_API_KEY_PATH"], str(self.key.resolve()))
        self.assertEqual(result["MATCH_PASSWORD"], "fixture-password")
        self.assertEqual(environment, {"MATCH_PASSWORD": "fixture-password"})

    def test_explicit_key_takes_precedence_without_silent_fallback(self):
        with self.assertRaisesRegex(ValueError, "readable Fastlane"):
            signing_environment(
                {"INSTALLER_API_KEY_PATH": "/missing", "MATCH_PASSWORD": "fixture"},
                self.home,
                False,
            )
        self.key.write_text("{}")
        with self.assertRaisesRegex(ValueError, "key_id, issuer_id, and key"):
            signing_environment({"MATCH_PASSWORD": "fixture"}, self.home, False)

    def test_interactive_prompt_is_private_and_not_persisted(self):
        prompt = Mock(return_value="fixture-password")
        result = signing_environment({}, self.home, True, prompt)
        self.assertEqual(result["MATCH_PASSWORD"], "fixture-password")
        prompt.assert_called_once_with("Existing signing repository password: ")
        self.assertEqual([p for p in self.home.rglob("*") if p.is_file()], [self.key])

    def test_missing_password_never_prompts_without_terminal(self):
        prompt = Mock()
        with self.assertRaisesRegex(ValueError, "hidden prompt"):
            signing_environment({}, self.home, False, prompt)
        prompt.assert_not_called()

    def test_echo_fallback_eof_and_empty_input_fail(self):
        def echo_warning(_):
            warnings.warn("Cannot hide input", getpass.GetPassWarning)
            self.fail("Must not reach echoed input")

        for prompt in (echo_warning, Mock(side_effect=EOFError), Mock(return_value="")):
            with self.subTest(prompt=prompt), self.assertRaises(ValueError):
                signing_environment({}, self.home, True, prompt)

    def test_interrupt_is_preserved(self):
        with self.assertRaises(KeyboardInterrupt):
            signing_environment(
                {}, self.home, True, Mock(side_effect=KeyboardInterrupt)
            )
