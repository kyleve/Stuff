"""Match a landed main tree to the two providers' completed PR validations."""

import json
import re
import subprocess
import sys
from time import sleep
from urllib.request import Request, build_opener

from Tools.ci_actions_evidence import validated_actions_run
from Tools.ci_native_evidence import validated_native_run
from Tools.circleci_pipeline import NoRedirects


class MissingMergeEvidence(Exception):
    """A provider has not shown the evidence required to reuse a PR run."""


def validated_merge(root, repository, revision, token, *, before, documentation_push):
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

    try:
        return validated_pr(
            root, repository, revision, tree, get, before, documentation_push
        )
    except MissingMergeEvidence as error:
        # GitHub can cache the association and commit statuses for 60 seconds.
        print(f"{error}. Checking again in 65 seconds.", file=sys.stderr, flush=True)
        sleep(65)
    return validated_pr(
        root, repository, revision, tree, get, before, documentation_push
    )


def previous_main_tip(get, revision, merged_at):
    # CircleCI's GitHub App push payload omits the previous revision. Use
    # GitHub's actual main ref update so a multi-commit push includes every commit.
    updates = get("activity?ref=refs/heads/main&per_page=1")
    if len(updates) != 1:
        return None
    update = updates[0]
    if (
        update["activity_type"] == "pr_merge"
        and update["ref"] == "refs/heads/main"
        and update["after"] == revision
        and update["timestamp"] == merged_at
        and re.fullmatch(r"[0-9a-f]{40}", update["before"])
    ):
        return update["before"]
    return None


def validated_pr(root, repository, revision, tree, get, before, documentation_push):
    # An associated PR alone can also describe an older ancestor or a commit
    # pushed directly to main. Require this exact commit to be the PR's merge.
    pulls = get(f"commits/{revision}/pulls?per_page=2")
    if pulls == []:
        raise MissingMergeEvidence("GitHub has no associated PR for the landed commit")
    if len(pulls) != 1:
        return None
    pr = pulls[0]
    if (
        pr["base"]["ref"] != "main"
        or pr["base"]["repo"]["full_name"] != repository
        or pr["head"]["repo"]["full_name"] != repository
        or "NO-CI" in pr["title"]
    ):
        return None
    if pr["state"] != "closed" or not pr["merged_at"]:
        raise MissingMergeEvidence(
            "GitHub has not recorded the associated PR as merged"
        )
    if pr["merge_commit_sha"] != revision:
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
        raise MissingMergeEvidence(
            f"GitHub Actions has no verified run for PR #{number}"
        )
    if actions.documentation_only:
        if not before:
            before = previous_main_tip(get, revision, pr["merged_at"])
            if not before:
                raise MissingMergeEvidence(
                    f"GitHub has no matching main ref update for PR #{number}"
                )
        if not documentation_push(before):
            return None
    native = validated_native_run(
        get,
        head,
        repository,
        number,
        jobs["circleci"],
        documentation_only=actions.documentation_only,
    )
    if not native:
        raise MissingMergeEvidence(
            f"CircleCI has no matching verified run for PR #{number}"
        )
    detail = " (documentation-only push)" if actions.documentation_only else ""
    return f"PR #{number} passed on the landed tree {tree}{detail}. GitHub Actions: {actions.url} · CircleCI: {native}"
