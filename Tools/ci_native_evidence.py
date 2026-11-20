"""Verify the native jobs CircleCI ran on a pull request's head."""

import json
import re
from urllib.request import build_opener

from Tools.circleci_pipeline import NoRedirects


# GitHub's individual commit statuses retain their creator and are newest first.
# The combined status endpoint drops the creator identity.
CIRCLECI_BOT_ID = 127350680
UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
JOB_URL = re.compile(rf"(https://app\.circleci\.com/workflow/{UUID})/job/({UUID})")


def public_circleci_get(path):
    with build_opener(NoRedirects()).open(
        f"https://circleci.com/api/v2/{path}", timeout=8
    ) as response:
        return json.load(response)


def validated_native_run(
    get, head_sha, repository, pr_number, jobs_config, *, circle_get=public_circleci_get
):
    """Return a full CircleCI workflow URL for this exact PR checkout."""
    if not re.fullmatch("[0-9a-f]{40}", head_sha):
        return None
    jobs = jobs_config["jobs"]
    if not isinstance(jobs, list):
        return None
    contexts = {f"ci/circleci: {name}" for name in jobs}
    statuses = get(f"commits/{head_sha}/statuses?per_page=100")
    latest = {}
    for status in statuses:
        context = status["context"]
        if context in contexts:
            latest.setdefault(context, status)
    if latest.keys() != contexts:
        return None

    workflow_urls = set()
    job_ids = set()
    for status in latest.values():
        if (
            status["state"] != "success"
            or (status.get("creator") or {}).get("id") != CIRCLECI_BOT_ID
        ):
            return None
        match = JOB_URL.fullmatch(status.get("target_url") or "")
        if not match:
            return None
        workflow_urls.add(match[1])
        job_ids.add(match[2])
    if len(workflow_urls) != 1 or len(job_ids) != len(jobs):
        return None
    workflow_url = workflow_urls.pop()
    workflow_id = workflow_url.rsplit("/", 1)[1]
    workflow = circle_get(f"workflow/{workflow_id}")
    pipeline_id = workflow.get("pipeline_id")
    if (
        workflow.get("id") != workflow_id
        or workflow["name"] != jobs_config["workflow"]
        or workflow.get("status") != "success"
        or not isinstance(pipeline_id, str)
        or not re.fullmatch(UUID, pipeline_id)
    ):
        return None

    # The app posts the same job contexts for manual and PR workflows. Check
    # the recorded trigger, checkout and configuration before accepting them.
    values = circle_get(f"pipeline/{pipeline_id}/values")
    repository_url = f"https://github.com/{repository}"
    expected = {
        "pipeline.id": pipeline_id,
        "pipeline.project.git_url": repository_url,
        "pipeline.git.repo_url": repository_url,
        "pipeline.git.revision": head_sha,
        "pipeline.config.repository.url": repository_url,
        "pipeline.config.file_path": ".circleci/config.yml",
        "pipeline.config.sha": head_sha,
        "pipeline.event.name": "pull_request",
        "pipeline.event.github.pull_request.base.ref": "main",
        "pipeline.event.github.pull_request.head.sha": head_sha,
        "pipeline.event.github.pull_request.number": pr_number,
    }
    if all(values.get(key) == value for key, value in expected.items()):
        return workflow_url
    return None
