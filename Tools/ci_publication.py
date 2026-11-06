"""Select trusted publication jobs; CircleCI owns their dependencies and handoff."""

import json
import os
import re
import sys
import time

from Tools.ci_circleci import continue_configuration
from Tools.circleci_pipeline import request_json
from Tools.InstallerKit.circleci_archive import ArchiveRequest
from Tools.InstallerKit.installer_apps import enabled_apps, load_app
from Tools.InstallerKit.installer_distribution import (
    Publication,
    Retirement,
    eligible,
    github_fetch,
    select_plan,
    source_available,
)
from Tools.repository import repository_root


def selection(environ, fetch):
    """Webhook data can select a channel, but live GitHub state authorizes work."""
    repository = environ["PUBLICATION_REPOSITORY"]
    sha = environ["PUBLICATION_SHA"]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid publication repository")
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise ValueError("An exact control commit is required")
    if "PUBLICATION_WEBHOOK" in environ:
        event = json.loads(environ["PUBLICATION_WEBHOOK"])
        if event.get("repository", {}).get("full_name") != repository:
            return None, False, False
        if "pull_request" in event:
            number = event.get("number")
            if type(number) is not int or number < 1:
                raise ValueError("Invalid pull request number")
            # Redeliveries and delayed label events must use the current state.
            event["pull_request"] = fetch(f"repos/{repository}/pulls/{number}")
            plan = select_plan(
                "pull_request_target", event, repository, "refs/heads/main", sha
            )
            return plan, False, plan is not None
        if event.get("ref") == "refs/heads/main" and event.get("deleted") is not True:
            # Main can move between delivery and setup. Build only its current tip.
            current = fetch(f"repos/{repository}/git/ref/heads/main")["object"]["sha"]
            return Publication(current, None), False, True
        return None, False, False
    task = environ["PUBLICATION_TASK"]
    if task in ("pages", "flyover"):
        return None, task == "flyover", True
    if task != "installer":
        raise ValueError("Unknown publication task")
    number = int(environ.get("PUBLICATION_PR", "0"))
    if number < 0:
        raise ValueError("Invalid pull request number")
    if number:
        pr = fetch(f"repos/{repository}/pulls/{number}")
        if not eligible(pr, repository):
            raise ValueError("Manual publication requires an installable PR")
        return Publication(pr["head"]["sha"], number), False, True
    current = fetch(f"repos/{repository}/git/ref/heads/main")["object"]["sha"]
    return Publication(current, None), False, True


def configuration(root, environ, fetch, run):
    plan, flyover, pages = selection(environ, fetch)
    repository = environ["PUBLICATION_REPOSITORY"]
    owner, name = repository.split("/")
    feed = (
        environ.get("INSTALLER_FEED_URL")
        or f"https://{owner}.github.io/{name}/updates.json"
    )
    attempt = environ["PUBLICATION_ATTEMPT"]
    groups, workflows = {}, {}

    def site(name, requires=()):
        return {
            "publish-pages": {
                "name": name,
                "context": "github-publication",
                "feed_url": feed,
                "requires": list(requires),
            }
        }

    if plan is not None:
        for app in enabled_apps(environ):
            if not source_available(load_app(app), plan, repository, fetch):
                continue
            group = f"installer-{app}-{plan.channel}"
            common = {"app": app, "channel": plan.channel, "feed_url": feed}
            prepare, archive, finish, failure = (
                f"{phase}-{app}-{plan.channel}"
                for phase in ("prepare", "archive", "finish", "failure")
            )
            if isinstance(plan, Retirement):
                jobs = [
                    {
                        "retire-app": {
                            **common,
                            "name": finish,
                            "number": plan.pull_request,
                            "context": "github-publication",
                        }
                    }
                ]
            else:
                request = ArchiveRequest(
                    repository, app, plan.sha, plan.channel, run, attempt, feed
                )
                common.update(sha=request.sha, run=request.run, attempt=request.attempt)
                jobs = [
                    {
                        "prepare-app": {
                            **common,
                            "name": prepare,
                            "context": "github-publication",
                        }
                    },
                    site(f"Progress {group}", [{prepare: ["success", "failed"]}]),
                    {
                        "archive-app": {
                            **common,
                            "name": archive,
                            "context": "where-distribution-signing",
                            "requires": [prepare],
                        }
                    },
                    {
                        "finish-app": {
                            **common,
                            "name": finish,
                            "command": "finish",
                            "context": "github-publication",
                            "requires": [archive],
                        }
                    },
                    {
                        "finish-app": {
                            **common,
                            "name": failure,
                            "command": "fail",
                            "context": "github-publication",
                            "requires": [{archive: ["failed", "canceled"]}],
                        }
                    },
                ]
            groups[group] = {"jobs": jobs}
            workflows[group] = {
                "jobs": [
                    {group: {"serial-group": f"<< pipeline.project.slug >>/{group}"}}
                ]
            }
    if flyover:
        groups["flyover-publication"] = {
            "jobs": [
                {"export-flyover": {"sha": environ["PUBLICATION_SHA"]}},
                {
                    "publish-flyover": {
                        "sha": environ["PUBLICATION_SHA"],
                        "run": run,
                        "attempt": attempt,
                        "context": "github-publication",
                        "requires": ["export-flyover"],
                    }
                },
                site("Deploy Flyover", ["publish-flyover"]),
            ]
        }
        workflows["Flyover"] = {
            "jobs": [
                {
                    "flyover-publication": {
                        "serial-group": "<< pipeline.project.slug >>/flyover"
                    }
                }
            ]
        }
    # Main source changes and explicit site requests deploy even with no apps enabled.
    if pages and not flyover:
        workflows["App Install Site"] = {"jobs": [site("Deploy site")]}
    if not workflows:
        workflows["No publication work"] = {"jobs": ["no-publication"]}
    return (
        (root / ".circleci/jobs.yml").read_text()
        + "\n"
        + "\n".join(
            f"{key}: {json.dumps(value)}"
            for key, value in (("job-groups", groups), ("workflows", workflows))
        )
        + "\n"
    )


def main():
    try:
        # Milliseconds preserve the existing numeric build-ID schema and sort after
        # legacy GitHub run IDs. A new pipeline creates a new immutable release ID.
        run = str(time.time_ns() // 1_000_000)
        config = configuration(repository_root(__file__), os.environ, github_fetch, run)
        continue_configuration(config, {}, os.environ, request_json)
    except Exception as error:
        print(
            f"Publication selection failed ({type(error).__name__}).", file=sys.stderr
        )
        return 1
    print("Publication pipeline continued.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
