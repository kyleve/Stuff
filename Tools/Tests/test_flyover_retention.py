from datetime import datetime, timedelta, timezone
import io
import json
import os
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from Tools.flyover_retention import expired_releases, main
from Tools.repository import repository_root


NOW = datetime(2026, 10, 26, 12, tzinfo=timezone.utc)


def pages_workflow():
    path = repository_root(__file__) / ".github/workflows/installer-pages.yml"
    return json.loads(
        subprocess.check_output(
            [
                "ruby",
                "-ryaml",
                "-rjson",
                "-e",
                "puts JSON.generate(YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true))",
                str(path),
            ],
            text=True,
        )
    )


def release(run, age, **overrides):
    return {
        "id": run,
        "tag_name": f"flyover-atlas-{run}-1",
        "draft": False,
        "published_at": (NOW - timedelta(days=age)).isoformat(),
        **overrides,
    }


class FlyoverRetentionTests(unittest.TestCase):
    def test_retains_week_boundary_future_and_both_protected_bundles(self):
        releases = [
            release(1, 8),
            release(2, 7),
            release(3, 6),
            release(4, -1),
            release(5, 20),  # The deployed bundle can be old.
            release(6, 30),  # Run order, not publication time, selects latest.
        ]
        self.assertEqual(expired_releases(releases, "flyover-atlas-5-1", NOW), [1])

    def test_single_old_bundle_survives(self):
        self.assertEqual(
            expired_releases([release(1, 90)], "flyover-atlas-1-1", NOW), []
        )

    def test_ignores_drafts_and_unrelated_releases(self):
        releases = [
            release(1, 90, tag_name="installer-1"),
            release(2, 90, draft=True),
            release(3, 90, tag_name="flyover-atlas-3-1-extra"),
            release(4, 90),
        ]
        self.assertEqual(expired_releases(releases, "flyover-atlas-4-1", NOW), [])

    def test_latest_retry_survives(self):
        releases = [release(1, 90), release(2, 90, tag_name="flyover-atlas-1-2")]
        self.assertEqual(expired_releases(releases, "flyover-atlas-1-2", NOW), [1])

    def test_cli_paginates_and_deletes_only_expired_release_ids(self):
        with (
            patch.dict("os.environ", {"GITHUB_REPOSITORY": "owner/repo"}),
            patch("Tools.flyover_retention.datetime") as clock,
            patch(
                "Tools.flyover_retention.subprocess.check_output",
                return_value=json.dumps([[release(1, 9)], [release(2, 0)]]),
            ) as inventory,
            patch("Tools.flyover_retention.subprocess.run") as delete,
            patch("sys.stdout", new_callable=io.StringIO) as output,
        ):
            clock.now.return_value = NOW
            clock.fromisoformat.side_effect = datetime.fromisoformat
            self.assertEqual(main(["--deployed-release", "flyover-atlas-2-1"]), 0)
        inventory.assert_called_once_with(
            ["gh", "api", "repos/owner/repo/releases", "--paginate", "--slurp"],
            text=True,
        )
        delete.assert_called_once_with(
            ["gh", "api", "--method", "DELETE", "repos/owner/repo/releases/1"],
            check=True,
        )
        self.assertIn("removed 1 expired releases", output.getvalue())

    def test_bad_inventory_never_deletes_any_release(self):
        for bad in (
            release(3, 90, published_at=None),
            release(3, 90, published_at="invalid"),
            release(3, 90, published_at="2026-01-01T00:00:00"),
            release(3, 90, id=True),
            release(3, 90, id=1),
            release(3, 90, tag_name="flyover-atlas-1-1"),
        ):
            with (
                self.subTest(bad=bad),
                patch.dict("os.environ", {"GITHUB_REPOSITORY": "owner/repo"}),
                patch(
                    "Tools.flyover_retention.subprocess.check_output",
                    return_value=json.dumps([[release(1, 90), bad, release(4, 0)]]),
                ),
                patch("Tools.flyover_retention.subprocess.run") as delete,
                patch("sys.stderr", new_callable=io.StringIO) as error,
            ):
                self.assertEqual(main(["--deployed-release", "flyover-atlas-4-1"]), 1)
                delete.assert_not_called()
                self.assertIn("retention failed", error.getvalue())

    def test_missing_deployed_release_fails_closed(self):
        for releases in ([], [release(1, 90)]):
            with self.assertRaisesRegex(ValueError, "missing"):
                expired_releases(releases, "flyover-atlas-2-1", NOW)

    def test_api_errors_fail_cli_and_stop_deletion(self):
        for phase in ("list", "delete"):
            with (
                self.subTest(phase=phase),
                patch.dict("os.environ", {"GITHUB_REPOSITORY": "owner/repo"}),
                patch("Tools.flyover_retention.datetime") as clock,
                patch("Tools.flyover_retention.subprocess.check_output") as inventory,
                patch("Tools.flyover_retention.subprocess.run") as delete,
                patch("sys.stderr", new_callable=io.StringIO) as error,
            ):
                clock.now.return_value = NOW
                clock.fromisoformat.side_effect = datetime.fromisoformat
                inventory.return_value = json.dumps(
                    [[release(1, 90), release(2, 90), release(3, 0)]]
                )
                target = inventory if phase == "list" else delete
                target.side_effect = subprocess.CalledProcessError(1, "gh")
                self.assertEqual(main(["--deployed-release", "flyover-atlas-3-1"]), 1)
                self.assertEqual(delete.call_count, 0 if phase == "list" else 1)
                self.assertIn("retention failed", error.getvalue())

    def test_workflow_gates_cleanup_on_deployment_and_limits_write_permission(self):
        workflow = pages_workflow()
        build, deploy, retention = (
            workflow["jobs"][key] for key in ("build", "deploy", "retain-flyover")
        )
        self.assertEqual(
            build.get("permissions", workflow["permissions"]), {"contents": "read"}
        )
        self.assertEqual(build["if"], "github.ref == 'refs/heads/main'")
        upload = next(
            s
            for s in build["steps"]
            if s.get("uses") == "actions/upload-pages-artifact@v3"
        )
        self.assertEqual(upload["with"]["name"], build["outputs"]["artifact-name"])
        self.assertEqual(upload["with"]["name"], "${{ env.PAGES_ARTIFACT }}")
        self.assertIn("github.run_attempt", build["env"]["PAGES_ARTIFACT"])
        self.assertEqual(deploy["needs"], "build")
        self.assertEqual(
            deploy["permissions"],
            {"actions": "read", "pages": "write", "id-token": "write"},
        )
        self.assertEqual(build["outputs"]["build-attempt"], "${{ github.run_attempt }}")
        freshness = deploy["steps"][0]
        self.assertEqual(freshness, retention["steps"][0])
        self.assertEqual(
            freshness["env"]["BUILD_ATTEMPT"],
            "${{ needs.build.outputs.build-attempt }}",
        )
        for job in (deploy, retention):
            for step in job["steps"][1:]:
                self.assertEqual(
                    step["if"], "steps.freshness.outputs.current == 'true'"
                )
        self.assertNotIn(upload["uses"], [s.get("uses") for s in deploy["steps"]])
        publish = next(s for s in deploy["steps"] if s.get("id") == "deployment")
        self.assertEqual(publish["uses"], "actions/deploy-pages@v4")
        self.assertEqual(
            publish["with"]["artifact_name"],
            "${{ needs.build.outputs.artifact-name }}",
        )
        self.assertEqual(
            deploy["environment"]["url"], "${{ steps.deployment.outputs.page_url }}"
        )
        self.assertEqual(deploy["outputs"]["page-url"], deploy["environment"]["url"])
        self.assertIn("flyover", [s.get("id") for s in build["steps"]])
        self.assertEqual(
            build["outputs"]["flyover-release"], "${{ steps.flyover.outputs.release }}"
        )
        self.assertEqual(set(retention["needs"]), {"build", "deploy"})
        self.assertEqual(
            retention["if"],
            "needs.deploy.outputs.page-url != '' && needs.build.outputs.flyover-release != ''",
        )
        self.assertEqual(
            retention["permissions"], {"actions": "read", "contents": "write"}
        )
        cleanup = retention["steps"][-1]
        self.assertEqual(
            cleanup["env"]["DEPLOYED_RELEASE"],
            "${{ needs.build.outputs.flyover-release }}",
        )
        self.assertIn(
            'Tools.flyover_retention --deployed-release "$DEPLOYED_RELEASE"',
            cleanup["run"],
        )

    def test_retry_preserves_the_newer_publication_waiting_behind_an_active_run(self):
        # A fresh build can replace pending work. Retrying an old build must
        # queue behind it, since the freshness check will skip the old build.
        self.assertEqual(
            pages_workflow()["concurrency"],
            {
                "group": "installer-pages",
                "cancel-in-progress": False,
                "queue": "${{ github.run_attempt > 1 && 'max' || 'single' }}",
            },
        )

    def test_retry_reuses_only_the_latest_main_build(self):
        check = pages_workflow()["jobs"]["deploy"]["steps"][0]
        current = {
            "id": 101,
            "run_number": 10,
            "head_branch": "main",
            "head_sha": "same",
        }
        for case, attempt, latest, api_status, success, publish in [
            ("fresh build", "1", None, 1, True, True),
            ("latest retry", "2", {}, 0, True, True),
            (
                "newer pending run on same commit",
                "2",
                {"id": 102, "run_number": 11, "status": "pending"},
                0,
                True,
                False,
            ),
            ("older run", "2", {"id": 99, "run_number": 9}, 0, False, False),
            ("unexpected id for same number", "2", {"id": 102}, 0, False, False),
            ("empty", "2", None, 0, False, False),
            ("invalid id", "2", {"id": None}, 0, False, False),
            ("other branch", "2", {"head_branch": "next"}, 0, False, False),
            ("API error with output", "2", {}, 1, False, False),
        ]:
            with (
                self.subTest(case=case),
                tempfile.NamedTemporaryFile(mode="r") as output,
            ):
                reply = {
                    "workflow_runs": [] if latest is None else [{**current, **latest}]
                }
                fake_gh = (
                    'gh() { echo "gh $*" >&2; echo "$REPLY"; return "$API_STATUS"; }\n'
                )
                result = subprocess.run(
                    ["bash", "-eo", "pipefail", "-c", fake_gh + check["run"]],
                    env={
                        "PATH": os.environ["PATH"],
                        "GITHUB_REPOSITORY": "owner/repo",
                        "GITHUB_RUN_ATTEMPT": attempt,
                        "GITHUB_RUN_ID": "101",
                        "GITHUB_OUTPUT": output.name,
                        "GITHUB_RUN_NUMBER": "10",
                        "BUILD_ATTEMPT": "1",
                        "REPLY": json.dumps(reply),
                        "API_STATUS": str(api_status),
                    },
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(result.returncode == 0, success, result.stderr)
                self.assertEqual(output.read(), "current=true\n" if publish else "")
                query = "gh api repos/owner/repo/actions/workflows/installer-pages.yml/runs?branch=main&per_page=1"
                self.assertEqual(query in result.stderr.splitlines(), attempt != "1")
                if case == "newer pending run on same commit":
                    self.assertIn("Skipping the reused Pages build", result.stdout)
