import io
import json
import subprocess
import unittest
from unittest.mock import Mock, patch

from Tools import ci_publication
from Tools.InstallerKit.installer_distribution import Publication, Retirement
from Tools.InstallerKit.installer_update_feed import apply_change, BuildStatus
from Tools.InstallerKit.installer_apps import load_app
from Tools.repository import repository_root
from Fixtures.circleci_distribution_fixtures import pull_request, archive_request

REQUEST = archive_request()
ENV = {
    "PUBLICATION_REPOSITORY": REQUEST.repository,
    "PUBLICATION_SHA": REQUEST.sha,
    "PUBLICATION_ATTEMPT": "321",
    "PUBLICATION_TASK": "installer",
    "PUBLICATION_PR": "42",
    "WHERE_DISTRIBUTION_ENABLED": "true",
}
RUN = "1793980000000"


def config(environment, fetch):
    text = ci_publication.configuration(
        repository_root(__file__), environment, fetch, RUN
    )
    return json.loads(
        subprocess.check_output(
            [
                "ruby",
                "-ryaml",
                "-rjson",
                "-e",
                "puts JSON.generate(YAML.load(STDIN.read))",
            ],
            input=text,
            text=True,
        )
    )


class CIPublicationTests(unittest.TestCase):
    def test_manual_pr_keeps_label_and_same_repository_gates(self):
        for update in (
            {"state": "closed"},
            {"labels": []},
            {"head": {"repo": {"full_name": "fork/repo"}, "sha": REQUEST.sha}},
        ):
            with self.assertRaises(ValueError):
                ci_publication.selection(
                    ENV, Mock(return_value={**pull_request(), **update})
                )
        plan, flyover, pages = ci_publication.selection(
            ENV, Mock(return_value=pull_request())
        )
        self.assertEqual(plan, Publication(REQUEST.sha, 42))
        self.assertEqual((flyover, pages), (False, True))

    def test_webhook_redelivery_uses_live_state_for_retirement_and_refresh(self):
        event = {
            "repository": {"full_name": REQUEST.repository},
            "number": 42,
            "action": "labeled",
            "pull_request": pull_request(),
        }
        env = {**ENV, "PUBLICATION_WEBHOOK": json.dumps(event)}
        self.assertEqual(
            ci_publication.selection(
                env, Mock(return_value={**pull_request(), "labels": []})
            )[0],
            Retirement(42),
        )
        event["action"] = "unlabeled"
        event["pull_request"]["labels"] = []
        env["PUBLICATION_WEBHOOK"] = json.dumps(event)
        self.assertEqual(
            ci_publication.selection(env, Mock(return_value=pull_request()))[0],
            Publication(REQUEST.sha, 42),
        )

    def test_untrusted_or_unrelated_webhooks_never_request_archive(self):
        for event in (
            {"repository": {"full_name": "fork/repo"}},
            {
                "repository": {"full_name": REQUEST.repository},
                "ref": "refs/heads/topic",
            },
            {
                "repository": {"full_name": REQUEST.repository},
                "ref": "refs/heads/main",
                "deleted": True,
            },
        ):
            result = ci_publication.selection(
                {**ENV, "PUBLICATION_WEBHOOK": json.dumps(event)}, Mock()
            )
            self.assertEqual(result, (None, False, False))

    def test_main_event_resolves_current_head_and_always_builds_site(self):
        event = {
            "repository": {"full_name": REQUEST.repository},
            "ref": "refs/heads/main",
            "after": "b" * 40,
        }
        plan, _, pages = ci_publication.selection(
            {**ENV, "PUBLICATION_WEBHOOK": json.dumps(event)},
            Mock(return_value={"object": {"sha": REQUEST.sha}}),
        )
        self.assertEqual(plan, Publication(REQUEST.sha, None))
        self.assertTrue(pages)

    def test_native_graph_has_success_and_failure_routes_and_no_write_token_on_archive(
        self,
    ):
        value = config(ENV, Mock(return_value=pull_request()))
        jobs = value["job-groups"]["installer-where-pr-42"]["jobs"]
        by_name = {
            options["name"]: (job, options)
            for entry in jobs
            for job, options in entry.items()
        }
        archive = by_name["archive-where-pr-42"][1]
        self.assertEqual(archive["context"], "where-distribution-signing")
        self.assertEqual(archive["requires"], ["prepare-where-pr-42"])
        success = by_name["finish-where-pr-42"][1]
        failure = by_name["failure-where-pr-42"][1]
        self.assertEqual(success["command"], "finish")
        self.assertEqual(success["requires"], ["archive-where-pr-42"])
        self.assertEqual(failure["command"], "fail")
        self.assertEqual(
            failure["requires"], [{"archive-where-pr-42": ["failed", "canceled"]}]
        )
        self.assertTrue(
            all(
                options["context"] == "github-publication"
                for name, (_, options) in by_name.items()
                if not name.startswith("archive-")
            )
        )
        invocation = value["workflows"]["installer-where-pr-42"]["jobs"][0][
            "installer-where-pr-42"
        ]
        self.assertTrue(invocation["serial-group"].endswith("/installer-where-pr-42"))

    def test_no_enabled_apps_still_deploys_site_without_signing(self):
        value = config(
            {**ENV, "WHERE_DISTRIBUTION_ENABLED": "false"},
            Mock(return_value=pull_request()),
        )
        self.assertEqual(value["job-groups"], {})
        self.assertEqual(set(value["workflows"]), {"App Install Site"})

    def test_new_run_identity_sorts_after_legacy_github_ids(self):
        app = load_app("where")
        catalog = {"schemaVersion": 3, "apps": []}
        old = BuildStatus("preparing", {"run": 42000000000, "attempt": 1}, REQUEST.sha)
        new = BuildStatus("preparing", {"run": int(RUN), "attempt": 1}, REQUEST.sha)
        catalog = apply_change(catalog, app, "pr-42", old)
        catalog = apply_change(catalog, app, "pr-42", new)
        self.assertEqual(
            catalog["apps"][0]["channels"][0]["buildStatus"]["id"]["run"], int(RUN)
        )

    def test_command_only_continues_after_a_complete_plan_and_redacts_errors(self):
        with (
            patch.dict("os.environ", ENV),
            patch("Tools.ci_publication.github_fetch", side_effect=OSError("secret")),
            patch("Tools.ci_publication.continue_configuration") as continuation,
            patch("sys.stderr", new_callable=io.StringIO) as stderr,
        ):
            self.assertEqual(ci_publication.main(), 1)
        continuation.assert_not_called()
        self.assertNotIn("secret", stderr.getvalue())
