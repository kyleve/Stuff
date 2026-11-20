"""Identify a full CI workflow that ran on the landed PR's exact source tree."""

REQUIRED_ACTIONS_JOBS = {
    "Classify changes",
    "Lint & Formatting",
    "Tool Tests",
    "Web Checks & Tests",
    "Bumper Bowling",
    "Build & Test (macOS)",
}


def succeeded(record):
    return record["status"] == "completed" and record["conclusion"] == "success"


def validated_actions_run(get, pr_number, head_sha, tree_sha):
    """Return the matching attempt URL. The selector handles API/schema errors."""
    runs = get(
        "actions/workflows/ci.yml/runs"
        f"?event=pull_request&head_sha={head_sha}&per_page=1"
    )["workflow_runs"]
    if not runs:
        return None
    run = runs[0]
    if (
        not succeeded(run)
        or run["event"] != "pull_request"
        or run["path"] != ".github/workflows/ci.yml"
        or run["head_sha"] != head_sha
        or run["head_repository"]["id"] != run["repository"]["id"]
    ):
        return None

    # GitHub can return an empty association after merge or branch deletion.
    # The classifier records the event PR number alongside the actual checkout tree.
    if run["pull_requests"] and not any(
        pr["number"] == pr_number and pr["head"]["sha"] == head_sha
        for pr in run["pull_requests"]
    ):
        return None

    run_id = run["id"]
    attempt = run["run_attempt"]
    response = get(f"actions/runs/{run_id}/attempts/{attempt}/jobs?per_page=100")
    jobs = response["jobs"]
    if response["total_count"] != len(jobs) or len(jobs) != len(REQUIRED_ACTIONS_JOBS):
        return None
    by_name = {job["name"]: job for job in jobs}
    if by_name.keys() != REQUIRED_ACTIONS_JOBS or not all(
        succeeded(job)
        and job["run_id"] == run_id
        and job["run_attempt"] == attempt
        and job["head_sha"] == head_sha
        for job in jobs
    ):
        return None

    marker = f"Check agent guidance for PR #{pr_number} on tree {tree_sha}"
    if not any(
        step["name"] == marker and succeeded(step)
        for step in by_name["Classify changes"]["steps"]
    ):
        return None
    return f"https://github.com/{run['repository']['full_name']}/actions/runs/{run_id}/attempts/{attempt}"
