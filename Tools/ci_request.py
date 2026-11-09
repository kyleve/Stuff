"""Request CI or publication with the authenticated CircleCI CLI."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
from uuid import UUID

from Tools.InstallerKit.installer_apps import load_app
from Tools.repository import repository_root


def settings(repository, path=None):
    path = path or repository_root(__file__) / ".circleci/project.json"
    value = json.loads(Path(path).read_text())
    if repository != value["repository"]:
        raise ValueError("CircleCI registration does not match this repository")
    if not re.fullmatch(r"circleci/[A-Za-z0-9]+/[A-Za-z0-9]+", value["project"]):
        raise ValueError("Invalid CircleCI project slug")
    UUID(value["definition"])
    return value


def request_arguments(repository, task, number, branch, registration=None):
    value = registration or settings(repository)
    if task not in ("ci", "installer", "flyover", "pages") or number < 0:
        raise ValueError("Invalid CI request")
    if task != "ci" and branch != "main":
        raise ValueError("Publication config and control checkout must use main")
    if task != "installer" and number:
        raise ValueError("Only installer publication accepts a PR number")
    parameters = (
        {"manual_full_gate": "true"}
        if task == "ci"
        else {
            "publication_task": task,
            "pull_request": number,
        }
    )
    payload = {
        "definition_id": value["definition"],
        "config": {"branch": branch},
        "checkout": {"branch": branch},
        "parameters": parameters,
    }
    return [
        "circleci",
        "api",
        f"api/v2/project/{value['project']}/pipeline/run",
        "-X",
        "POST",
        "--data",
        json.dumps(payload),
    ]


def enable_arguments(repository, app_id, registration=None):
    load_app(app_id)
    value = registration or settings(repository)
    variable = f"{app_id.upper().replace('-', '_')}_DISTRIBUTION_ENABLED"
    return [
        "circleci",
        "api",
        f"api/v2/project/{value['project']}/envvar",
        "-X",
        "POST",
        "--data",
        json.dumps({"name": variable, "value": "true"}),
    ]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("task", choices=("ci", "installer", "flyover", "pages"))
    parser.add_argument("--repository", default="kyleve/Stuff")
    parser.add_argument("--pr", type=int, default=0)
    parser.add_argument("--branch", default="main")
    args = parser.parse_args(argv)
    try:
        subprocess.run(
            request_arguments(args.repository, args.task, args.pr, args.branch),
            check=True,
        )
    except Exception as error:
        print(f"CircleCI request failed ({type(error).__name__}).", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
