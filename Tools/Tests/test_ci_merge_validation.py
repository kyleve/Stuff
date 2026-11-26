import copy
import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch

from Tools.ci_actions_evidence import ActionsRun
from Tools.ci_changes import classify_changes, main
from Tools.Tests.ci_test_support import GitRepository


class MergedValidationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        repo = GitRepository(temporary.name)
        self.old_main = repo.base
        repo.git("switch", "main")
        repo.write("app.py", "feature = True\n")
        self.before = repo.commit()
        repo.git("switch", "-c", "docs")
        repo.write("README.md", "Document feature\n")
        self.head = repo.commit()
        repo.git("switch", "main")
        repo.git("merge", "--squash", "docs")
        repo.git("commit", "-m", "Land documentation")
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
        self.actions.return_value = ActionsRun(
            "https://github.com/example/Stuff/actions/runs/123", False
        )
        self.native = self.enter_patch("Tools.ci_merge_validation.validated_native_run")
        self.native.return_value = "https://app.circleci.com/workflow/example"
        self.sleep = self.enter_patch("Tools.ci_merge_validation.sleep")

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
        self.stderr = io.StringIO()
        with redirect_stderr(self.stderr):
            return classify_changes(self.root, **(arguments | overrides))

    def test_same_tree_squash_requires_both_provider_proofs(self):
        self.assertNotEqual(self.landed, self.head)
        result = self.classify()
        self.assertTrue(result.skip_validation)
        for url in (self.actions.return_value.url, self.native.return_value):
            self.assertIn(url, result.reason)
        jobs = json.loads((self.root / "Tools/ci-validation-jobs.json").read_text())
        self.assertEqual(
            self.actions.call_args.args[1:],
            (18, self.head, self.tree, jobs["github_actions"]),
        )
        self.assertEqual(
            self.native.call_args.args[1:],
            (self.head, self.repository, 18, jobs["circleci"]),
        )
        self.sleep.assert_not_called()

    def test_documentation_proof_requires_the_entire_push_and_both_providers(self):
        self.actions.return_value = ActionsRun(self.actions.return_value.url, True)
        result = self.classify(base=self.before)
        self.assertTrue(result.skip_validation)
        self.assertIn("documentation-only push", result.reason)
        self.assertTrue(self.native.call_args.kwargs["documentation_only"])
        self.native.reset_mock()
        # The associated PR and final commit contain only Markdown. The push
        # also included a previous commit changing app.py.
        for base in (self.old_main, self.landed, "f" * 40, "unknown"):
            with self.subTest(base=base):
                self.assertFalse(self.classify(base=base).skip_validation)
        self.native.assert_not_called()
        self.native.return_value = None
        self.assertFalse(self.classify(base=self.before).skip_validation)

    def test_documentation_merge_command_emits_skip_and_verification_diagnostic(self):
        self.actions.return_value = ActionsRun(self.actions.return_value.url, True)
        stdout, stderr = io.StringIO(), io.StringIO()
        with (
            patch("Tools.ci_changes.repository_root", return_value=self.root),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            status = main(
                [
                    "--event",
                    "push",
                    "--branch",
                    "main",
                    "--push-forced",
                    "false",
                    "--repository",
                    self.repository,
                    "--head",
                    self.landed,
                    "--base",
                    self.before,
                ]
            )
        self.assertEqual(status, 0)
        self.assertEqual(
            stdout.getvalue(), "skip_validation=true\nrun_boundary_tests=false\n"
        )
        self.assertIn("documentation-only push", stderr.getvalue())
        self.assertIn(self.native.return_value, stderr.getvalue())

    def test_circleci_uses_only_the_matching_main_ref_update_for_missing_before(self):
        self.actions.return_value = ActionsRun(self.actions.return_value.url, True)
        path = "activity?ref=refs/heads/main&per_page=1"
        update = {
            "activity_type": "pr_merge",
            "timestamp": self.pr["merged_at"],
            "ref": "refs/heads/main",
            "before": self.before,
            "after": self.landed,
        }
        self.responses[path] = [update]
        self.assertTrue(self.classify().skip_validation)
        for updates in (
            [],
            [update, update],
            [{**update, "ref": "refs/heads/other"}],
            [{**update, "after": self.head}],
            [{**update, "timestamp": "2026-11-19T00:00:00Z"}],
            [{**update, "activity_type": "push"}],
            [{**update, "before": self.old_main}],
            [{**update, "before": "invalid"}],
        ):
            with self.subTest(updates=updates):
                self.responses[path] = updates
                self.assertFalse(self.classify().skip_validation)

    def test_waits_for_empty_or_unmerged_pr_association(self):
        for initial in ([], [dict(self.pr, state="open", merged_at=None)]):
            with self.subTest(initial=initial):
                self.responses[self.pulls_path] = initial
                self.sleep.reset_mock()
                self.actions.reset_mock()
                self.native.reset_mock()
                self.sleep.side_effect = lambda seconds: self.responses.update(
                    {self.pulls_path: [self.pr]}
                )
                self.assertTrue(self.classify().skip_validation)
                self.sleep.assert_called_once_with(65)
                self.assertRegex(self.stderr.getvalue(), r"(?i)PR|pull request")
                self.actions.assert_called_once()
                self.native.assert_called_once()

    def test_rechecks_pr_tree_and_both_providers_after_delayed_native_result(self):
        self.native.side_effect = [None, self.native.return_value]
        self.assertTrue(self.classify().skip_validation)
        self.sleep.assert_called_once_with(65)
        self.assertIn("CircleCI", self.stderr.getvalue())
        paths = [
            call.args[0].full_url.removeprefix(
                f"https://api.github.com/repos/{self.repository}/"
            )
            for call in self.http.call_args_list
        ]
        self.assertEqual(paths, [self.pulls_path, f"git/commits/{self.head}"] * 2)
        self.assertEqual(self.actions.call_count, 2)
        self.assertEqual(self.native.call_count, 2)

    def test_retry_rejects_a_newly_disqualifying_tree(self):
        self.native.side_effect = [None, self.native.return_value]
        self.sleep.side_effect = lambda seconds: self.responses[
            f"git/commits/{self.head}"
        ]["tree"].update(sha="f" * 40)
        self.assertFalse(self.classify().skip_validation)
        self.sleep.assert_called_once_with(65)
        self.actions.assert_called_once()
        self.native.assert_called_once()

    def test_reports_last_missing_provider_after_one_retry(self):
        self.actions.side_effect = [self.actions.return_value, None]
        self.native.return_value = None
        result = self.classify()
        self.assertFalse(result.skip_validation)
        self.assertIn("CircleCI", self.stderr.getvalue())
        self.assertIn("GitHub Actions", result.reason)
        self.sleep.assert_called_once_with(65)
        self.assertEqual(self.actions.call_count, 2)
        self.native.assert_called_once()

    def test_persistently_missing_provider_retries_once_before_falling_back(self):
        for name, provider in (
            ("GitHub Actions", self.actions),
            ("CircleCI", self.native),
        ):
            with self.subTest(name=name):
                self.sleep.reset_mock()
                self.actions.reset_mock(side_effect=True)
                self.native.reset_mock(side_effect=True)
                provider.side_effect = [None, None]
                result = self.classify()
                self.assertFalse(result.skip_validation)
                self.sleep.assert_called_once_with(65)
                self.assertIn(name, self.stderr.getvalue())
                self.assertIn(name, result.reason)
                self.assertEqual(provider.call_count, 2)

    def test_missing_job_configuration_runs_full_ci(self):
        (self.root / "Tools/ci-validation-jobs.json").unlink()
        self.assertFalse(self.classify().skip_validation)
        self.actions.assert_not_called()
        self.native.assert_not_called()
        self.sleep.assert_not_called()

    def test_unrelated_push_ambiguous_pr_fork_and_changed_tree_run_in_full(self):
        for prs in (
            [self.pr, self.pr],
            [dict(self.pr, merge_commit_sha=self.head)],
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
        self.sleep.assert_not_called()

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
        self.sleep.assert_not_called()

    def test_api_errors_run_full_ci_without_logging_provider_data(self):
        self.http.side_effect = TimeoutError("sensitive provider response")
        result = self.classify()
        self.assertFalse(result.skip_validation)
        self.assertIn("TimeoutError", result.reason)
        self.assertNotIn("sensitive", result.reason)
        self.sleep.assert_not_called()
