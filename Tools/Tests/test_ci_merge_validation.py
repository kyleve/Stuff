import copy
import io
import json
import tempfile
import unittest
from unittest.mock import patch

from Tools.ci_changes import classify_changes
from Tools.Tests.ci_test_support import GitRepository


class MergedValidationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        repo = GitRepository(temporary.name)
        repo.write("app.py", "feature = True\n")
        self.head = repo.commit()
        repo.git("switch", "main")
        repo.git("merge", "--squash", "topic")
        repo.git("commit", "-m", "Land feature")
        self.tree = repo.git("rev-parse", "HEAD^{tree}")
        self.landed = repo.git("rev-parse", "HEAD")
        self.root = repo.root
        self.repository = "example/Stuff"
        self.pr = {
            "number": 18,
            "title": "Feature",
            "state": "closed",
            "merged_at": "2026-11-20T00:00:00Z",
            "merge_commit_sha": self.landed,
            "base": {"repo": {"full_name": self.repository}, "ref": "main"},
            "head": {"repo": {"full_name": self.repository}, "sha": self.head},
        }
        self.pulls_path = f"commits/{self.landed}/pulls?per_page=2"
        self.responses = {
            self.pulls_path: [self.pr],
            f"git/commits/{self.head}": {"sha": self.head, "tree": {"sha": self.tree}},
        }
        self.http = self.enter_patch(
            "Tools.ci_merge_validation.build_opener"
        ).return_value.open
        self.http.side_effect = lambda req, timeout: io.BytesIO(
            json.dumps(
                self.responses[
                    req.full_url.removeprefix(
                        f"https://api.github.com/repos/{self.repository}/"
                    )
                ]
            ).encode()
        )
        self.actions = self.enter_patch(
            "Tools.ci_merge_validation.validated_actions_run"
        )
        self.actions.return_value = "https://github.com/example/Stuff/actions/runs/123"
        self.native = self.enter_patch("Tools.ci_merge_validation.validated_native_run")
        self.native.return_value = "https://app.circleci.com/workflow/example"

    def enter_patch(self, path):
        context = patch(path)
        self.addCleanup(context.stop)
        return context.start()

    def classify(self, **overrides):
        arguments = dict(
            event="push",
            push_forced="false",
            branch="main",
            base="",
            head=self.landed,
            repository=self.repository,
            force=False,
        )
        return classify_changes(self.root, **(arguments | overrides))

    def test_same_tree_squash_requires_both_provider_proofs(self):
        self.assertNotEqual(self.landed, self.head)
        result = self.classify()
        self.assertTrue(result.skip_validation)
        for url in (self.actions.return_value, self.native.return_value):
            self.assertIn(url, result.reason)
        self.assertEqual(self.actions.call_args.args[1:], (18, self.head, self.tree))
        self.assertEqual(
            self.native.call_args.args[1:], (self.head, self.repository, 18)
        )
        self.native.return_value = None
        self.assertFalse(self.classify().skip_validation)
        self.native.reset_mock()
        self.actions.return_value = None
        self.assertFalse(self.classify().skip_validation)
        self.native.assert_not_called()

    def test_unrelated_push_ambiguous_pr_fork_and_changed_tree_run_in_full(self):
        for prs in (
            [],
            [self.pr, self.pr],
            [dict(self.pr, merge_commit_sha=self.head)],
            [dict(self.pr, merged_at=None)],
            [dict(self.pr, title="Fixture NO-CI")],
        ):
            with self.subTest(prs=prs):
                self.responses[self.pulls_path] = prs
                self.assertFalse(self.classify().skip_validation)
        fork = copy.deepcopy(self.pr)
        fork["head"]["repo"]["full_name"] = "another/Stuff"
        self.responses[self.pulls_path] = [fork]
        self.assertFalse(self.classify().skip_validation)
        self.responses[self.pulls_path] = [self.pr]
        self.responses[f"git/commits/{self.head}"]["tree"]["sha"] = "f" * 40
        self.assertFalse(self.classify().skip_validation)
        self.actions.assert_not_called()
        self.native.assert_not_called()

    def test_manual_other_branches_publication_and_mismatched_checkout_do_not_lookup(
        self,
    ):
        for overrides in (
            {"force": True},
            {"push_forced": "true"},
            {"push_forced": ""},
            {"event": "workflow_dispatch"},
            {"event": "api"},
            {"branch": "topic"},
            {"head": self.head},
            {"repository": ""},
        ):
            with self.subTest(overrides=overrides):
                self.assertFalse(self.classify(**overrides).skip_validation)
        self.http.assert_not_called()

    def test_api_errors_run_full_ci_without_logging_provider_data(self):
        self.http.side_effect = TimeoutError("sensitive provider response")
        result = self.classify()
        self.assertFalse(result.skip_validation)
        self.assertIn("TimeoutError", result.reason)
        self.assertNotIn("sensitive", result.reason)
