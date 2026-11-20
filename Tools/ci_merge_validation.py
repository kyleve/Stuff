"""Match a landed main tree to the two providers' completed PR validations."""

import json
import re
import subprocess
from urllib.request import Request, build_opener

from Tools.ci_actions_evidence import validated_actions_run
from Tools.ci_native_evidence import validated_native_run
from Tools.circleci_pipeline import NoRedirects


def validated_merge(root, repository, revision, token):
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", repository, re.ASCII) or not re.fullmatch(
        r"[0-9a-f]{40}", revision
    ):
        return None
    commit, tree = subprocess.check_output(
        ["git", "log", "-1", "--format=%H %T", "HEAD"],
        cwd=root,
        text=True,
        timeout=10,
    ).split()
    if commit != revision:
        return None

    headers = {"Accept": "application/vnd.github+json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    opener = build_opener(NoRedirects)

    def get(path):
        request = Request(
            f"https://api.github.com/repos/{repository}/{path}", headers=headers
        )
        with opener.open(request, timeout=10) as response:
            return json.load(response)

    # An associated PR alone can also describe an older ancestor or a commit
    # pushed directly to main. Require this exact commit to be the PR's merge.
    pulls = get(f"commits/{revision}/pulls?per_page=2")
    if len(pulls) != 1:
        return None
    pr = pulls[0]
    if (
        pr["state"] != "closed"
        or not pr["merged_at"]
        or pr["merge_commit_sha"] != revision
        or pr["base"]["ref"] != "main"
        or pr["base"]["repo"]["full_name"] != repository
        or pr["head"]["repo"]["full_name"] != repository
        or "NO-CI" in pr["title"]
    ):
        return None

    number = pr["number"]
    head = pr["head"]["sha"]
    if (
        type(number) is not int
        or number <= 0
        or not re.fullmatch(r"[0-9a-f]{40}", head)
    ):
        return None
    # Squash and rebase merges can leave the PR head out of local Git history.
    tested_commit = get(f"git/commits/{head}")
    if tested_commit["sha"] != head or tested_commit["tree"]["sha"] != tree:
        return None
    jobs = json.loads((root / "Tools/ci-validation-jobs.json").read_text())
    actions = validated_actions_run(get, number, head, tree, jobs["github_actions"])
    if not actions:
        return None
    native = validated_native_run(get, head, repository, number, jobs["circleci"])
    if not native:
        return None
    return f"PR #{number} passed on the landed tree {tree}. GitHub Actions: {actions} · CircleCI: {native}"
