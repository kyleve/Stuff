"""Source preservation, classification, and date policy tests."""

import unittest
from backlog_test_support import manifest
from backlog_inventory import (
    concise_title,
    description,
    historical_dates,
    parse_file,
    resolve_links,
)


class InventoryTests(unittest.TestCase):
    def test_nested_task_is_distinct_but_parent_keeps_full_evidence(self):
        entries = manifest()["entries"]
        self.assertEqual(len(entries), 3)
        self.assertEqual(entries[1]["parent_id"], entries[0]["id"])
        self.assertEqual(entries[1]["blocked_by"], [entries[0]["id"]])
        self.assertIn("Cover the fix", entries[0]["body"])
        self.assertIn("origin:human", entries[0]["labels"])

    def test_supporting_bullets_remain_in_parent(self):
        source = "# Open issues\n## P0s\n- fix: Fault\n  - Evidence, not a task\n  Correction: partial fix only.\n# Completed issues\n"
        entries = parse_file("TODOs.md", source, "abc")
        self.assertEqual(len(entries), 1)
        self.assertIn("Correction: partial fix only.", entries[0]["body"])
        self.assertEqual(entries[0]["state"], "Backlog")
        self.assertEqual(entries[0]["priority"], 2)

    def test_reviewed_generic_children_and_old_unformatted_items(self):
        source = "## Open issues\n### P2s\n- Old parent\n\t- Independent generic task\n## Completed issues\n- An old completion\n"
        entries = parse_file("Shared/Inspector/TODOs.md", source, "abc", [4])
        self.assertEqual(len(entries), 3)
        self.assertEqual(entries[1]["parent_id"], entries[0]["id"])
        self.assertEqual(entries[1]["blocked_by"], [])
        self.assertEqual(entries[2]["priority"], 0)

    def test_section_context_is_retained(self):
        source = "# Open issues\n## PX\nA direction, not verified.\n- design: Explore this\n- design: Another idea\n# Completed issues\n"
        entry = parse_file("TODOs.md", source, "abc")[0]
        self.assertIn("A direction, not verified.", entry["context"])
        self.assertIn("exploratory", entry["labels"])
        second = parse_file("TODOs.md", source, "abc")[1]
        self.assertEqual(second["context"], entry["context"])

    def test_unattached_prose_is_an_error(self):
        with self.assertRaisesRegex(ValueError, "Unclassified"):
            parse_file(
                "TODOs.md", "# Open issues\nUnaccounted historical note\n", "abc"
            )

    def test_audit_origin_and_conflicting_dates_are_not_creation_or_closure(self):
        self.assertEqual(
            historical_dates("(human 2026-01-01; audit 2026-02-01)", "Done"), {}
        )
        self.assertEqual(
            historical_dates("resolved 2026-01-01; resolved 2026-01-02", "Done"), {}
        )
        self.assertEqual(historical_dates("resolved 2026-01-01", "Backlog"), {})
        self.assertEqual(
            historical_dates("resolved 2026-01-01", "Done")["completedAt"],
            "2026-01-01T00:00:00Z",
        )

    def test_relative_links_and_unknown_dates(self):
        item = manifest()
        text = resolve_links(
            "[code](../Package.swift) [web](https://example.com)",
            "Where/TODOs.md",
            "abc",
            item,
        )
        self.assertIn("/blob/abc/Package.swift", text)
        self.assertIn("[web](https://example.com)", text)
        self.assertIn(
            "Historical createdAt unknown", description(item["entries"][0], item)
        )

    def test_ids_are_stable_and_distinguish_identical_entries(self):
        source = "# Open issues\n- Same\n- Same\n"
        one = parse_file("TODOs.md", source, "abc")
        self.assertEqual(one, parse_file("TODOs.md", source, "abc"))
        self.assertNotEqual(one[0]["id"], one[1]["id"])

    def test_title_preserves_identifier_underscores(self):
        self.assertEqual(
            concise_title("fix: `github_slug` accepts malformed values"),
            "github_slug accepts malformed values",
        )

    def test_multiline_and_category_titles_retain_the_subject(self):
        self.assertEqual(
            concise_title(
                "fix: The capture can\n  overflow at large sizes. Next sentence."
            ),
            "The capture can overflow at large sizes",
        )
        self.assertIn(
            "LaunchLifecycle",
            concise_title("design: TLA+ — LaunchLifecycle model. More."),
        )
        self.assertIn(
            "hosting",
            concise_title("test: broken-snapshots — replace the hosting tests. More."),
        )

    def test_creation_estimates_are_disclosed_and_precede_completion(self):
        from backlog_inventory import estimate_creation_dates

        entries = parse_file(
            "TODOs.md",
            "# Completed issues\n- fix: Work (audit 2026-02-01; human 2026-01-01) (resolved 2026-03-01)\n",
            "abc",
        )
        estimate_creation_dates(entries)
        self.assertEqual(entries[0]["estimated_created_at"], "2026-02-01T00:00:00Z")
        self.assertIn(
            "Estimated creation date",
            description(entries[0], {"source_revision": "abc"}),
        )
        entries[0]["body"] = "(audit 2026-03-01) (human 2026-04-01)"
        estimate_creation_dates(entries)
        self.assertEqual(entries[0]["estimated_created_at"], "2026-02-28T00:00:00Z")
        entries[0]["dates"]["createdAt"] = "2026-01-01T00:00:00Z"
        entries[0].pop("estimated_created_at")
        estimate_creation_dates(entries)
        self.assertNotIn("estimated_created_at", entries[0])
