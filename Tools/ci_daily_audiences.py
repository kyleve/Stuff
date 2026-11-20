"""Check whether the scheduled Where audience builds have already passed on this main revision."""

import json
import os
import re
import sys
from urllib.parse import quote

from Tools.ci_native_evidence import public_circleci_get
from Tools.circleci_pipeline import uuid
from Tools.repository import repository_root


def built_workflow(pipeline, revision, names, get):
    """Return a prior build URL only for a successful scheduled compile of this checkout."""
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        return None
    values = get(f"pipeline/{uuid(pipeline)}/values")
    project = values["pipeline.project.slug"]
    repository = values["pipeline.git.repo_url"]
    expected = {
        "pipeline.project.slug": project,
        "pipeline.event.name": "schedule",
        "pipeline.git.repo_url": repository,
        "pipeline.git.branch": "main",
        "pipeline.git.revision": revision,
        "pipeline.config.repository.url": repository,
        "pipeline.config.file_path": ".circleci/config.yml",
        "pipeline.config.ref": "refs/heads/main",
        "pipeline.config.sha": revision,
    }
    if any(values.get(key) != value for key, value in expected.items()):
        return None

    history = get(
        f"insights/{project}/workflows/{quote(names['workflow'], safe='')}?branch=main"
    )
    latest = max(history["items"], key=lambda run: run["created_at"], default=None)
    if not latest or latest["status"] != "success":
        return None
    workflow_id = uuid(latest["id"])
    workflow = get(f"workflow/{workflow_id}")
    if (
        workflow["project_slug"] != project
        or workflow["name"] != names["workflow"]
        or workflow["status"] != "success"
    ):
        return None
    prior = get(f"pipeline/{uuid(workflow['pipeline_id'])}/values")
    if any(prior.get(key) != value for key, value in expected.items()):
        return None
    jobs = get(f"workflow/{workflow_id}/job")
    if not any(
        job["name"] == names["job"] and job["status"] == "success"
        for job in jobs["items"]
    ):
        return None
    return f"https://app.circleci.com/workflow/{workflow_id}"


def main():
    try:
        names = json.loads(
            (repository_root(__file__) / "Tools/ci-validation-jobs.json").read_text()
        )["daily_where_audiences"]
        workflow = built_workflow(
            os.environ["CIRCLE_PIPELINE_ID"],
            os.environ["CI_CHECKOUT_SHA"],
            names,
            public_circleci_get,
        )
    except Exception as error:
        print(
            f"Cannot verify the last daily build ({type(error).__name__}). Building both audiences.",
            file=sys.stderr,
        )
        return 1
    if workflow:
        print(f"Both Where audiences already built this main revision in {workflow}.")
        return 0
    print("This main revision needs a successful daily build of both Where audiences.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
