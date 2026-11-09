"""Migration retries, remote-edit protection, and complete-read tests."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock

from backlog_test_support import FakeLinear, manifest
from backlog_linear import Linear, LinearError, apply, verify, same_markdown


class LinearTests(unittest.TestCase):
    def test_repeat_and_pilot_resume_create_no_duplicates(self):
        client, data = FakeLinear(), manifest()
        apply(client, data, lambda: None, limit=1)
        self.assertEqual(verify(client, data, 1), 1)
        apply(client, data, lambda: None)
        apply(client, data, lambda: None)
        self.assertEqual(client.creates.count("issue"), 3)
        self.assertEqual(client.creates.count("issueRelation"), 1)
        self.assertEqual(verify(client, data), 3)

    def test_uncertain_create_recovers_by_stable_id(self):
        client, data = FakeLinear(), manifest()
        client.fail_after_issue = True
        with self.assertRaises(LinearError):
            apply(client, data, lambda: None)
        self.assertIsNone(data["entries"][0]["identifier"])
        apply(client, data, lambda: None)
        self.assertEqual(client.creates.count("issue"), 3)
        self.assertEqual(verify(client, data), 3)

    def test_checkpoint_failure_after_create_recovers(self):
        client, data = FakeLinear(), manifest()

        def save():
            if client.stored:
                raise OSError("Disk full")

        with self.assertRaises(OSError):
            apply(client, data, save)
        apply(client, data, lambda: None)
        self.assertEqual(client.creates.count("issue"), 3)

    def test_human_edit_is_never_overwritten(self):
        client, data = FakeLinear(), manifest()
        apply(client, data, lambda: None)
        issue = client.stored[data["entries"][0]["id"]]
        issue["description"] += "\nHuman correction"
        with self.assertRaisesRegex(LinearError, "preserve remote edits"):
            apply(client, data, lambda: None)
        self.assertTrue(issue["description"].endswith("Human correction"))

    def test_missing_relation_or_changed_state_fails_verification(self):
        client, data = FakeLinear(), manifest()
        apply(client, data, lambda: None)
        issue = client.stored[data["entries"][0]["id"]]
        issue["relations"]["nodes"] = []
        with self.assertRaisesRegex(LinearError, "blocking"):
            verify(client, data)
        issue["state"]["name"] = "Done"
        with self.assertRaisesRegex(LinearError, "state"):
            verify(client, data)

    def test_pagination_follows_every_page_and_rejects_stalled_cursor(self):
        client = Linear(Path("/unused"))
        client.call = Mock(
            side_effect=[
                {
                    "issues": {
                        "nodes": [1],
                        "pageInfo": {"hasNextPage": True, "endCursor": "next"},
                    }
                },
                {
                    "issues": {
                        "nodes": [2],
                        "pageInfo": {"hasNextPage": False, "endCursor": "end"},
                    }
                },
            ]
        )
        self.assertEqual(client.connection("query", "issues"), [1, 2])
        client.call = Mock(
            return_value={
                "issues": {
                    "nodes": [],
                    "pageInfo": {"hasNextPage": True, "endCursor": "same"},
                }
            }
        )
        with self.assertRaisesRegex(LinearError, "pagination"):
            client.connection("query", "issues")

    def test_access_errors_never_become_empty_backlog_or_expose_stderr(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / "node_modules/.bin/linear"
            binary.parent.mkdir(parents=True)
            binary.touch()
            for code in (4, 5, 1):
                runner = Mock(
                    return_value=subprocess.CompletedProcess([], code, "", "secret")
                )
                with self.assertRaisesRegex(LinearError, f"exit {code}") as error:
                    Linear(root, runner).call("query {}")
                self.assertNotIn("secret", str(error.exception))
            runner = Mock(
                return_value=subprocess.CompletedProcess(
                    [],
                    0,
                    json.dumps({"errors": [{"message": "secret"}], "data": {}}),
                    "",
                )
            )
            with self.assertRaisesRegex(LinearError, "GraphQL"):
                Linear(root, runner).call("query {}")

    def test_editor_normalization_preserves_semantic_structure(self):
        self.assertTrue(
            same_markdown(
                "[quick-win] [source](https://example.com/a#b)",
                r"\[quick-win\] [source](<https://example.com/a#b>)",
            )
        )
        self.assertTrue(same_markdown("- First\n- Second", "* First\n* Second"))
        self.assertTrue(
            same_markdown(
                "**A system Ruby at `/usr/bin`.**",
                "**A system Ruby at** `/usr/bin`**.**",
            )
        )
        self.assertTrue(
            same_markdown(
                "**`./sync-agents` cannot find Ruby.**",
                "`./sync-agents` **cannot find Ruby.**",
            )
        )
        self.assertFalse(same_markdown("`a_b`", "`ab`"))
        self.assertFalse(same_markdown("`\\[literal`", "`[literal`"))
        self.assertFalse(
            same_markdown(
                "[source](https://example.com/a)", "[source](https://example.com/b)"
            )
        )
        self.assertFalse(
            same_markdown("## Important\n\nEvidence", "Important\n\nEvidence")
        )
