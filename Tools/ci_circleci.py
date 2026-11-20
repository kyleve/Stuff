"""Continue CircleCI with the shared validation decision before allocating Macs."""

from http.client import HTTPException
import json
import os
import re
import sys
from urllib.error import HTTPError
from urllib.request import Request

from Tools.ci_changes import classify_changes
from Tools.ci_native_evidence import UUID, public_circleci_get
from Tools.circleci_pipeline import request_json
from Tools.repository import repository_root


def push_forced(environ):
    # The API exposes GitHub's force flag, but it is not a config-template value.
    pipeline_id = environ.get("CIRCLE_PIPELINE_ID", "")
    if (
        environ.get("CI_EVENT") != "push"
        or environ.get("CI_BRANCH") != "main"
        or environ.get("CI_MANUAL_FULL_GATE") == "true"
        or not re.fullmatch(UUID, pipeline_id)
    ):
        return ""
    try:
        values = public_circleci_get(f"pipeline/{pipeline_id}/values")
    except (OSError, HTTPException, ValueError):
        return ""
    expected = {
        "pipeline.id": pipeline_id,
        "pipeline.event.name": "push",
        "pipeline.git.branch": "main",
        "pipeline.git.repo_url": f"https://github.com/{environ.get('CI_REPOSITORY', '')}",
        "pipeline.git.revision": environ.get("CI_CHECKOUT_SHA", ""),
    }
    if isinstance(values, dict) and all(
        values.get(k) == v for k, v in expected.items()
    ):
        return values.get("pipeline.trigger_parameters.github_app.forced", "")
    return ""


def continue_pipeline(root, environ, transport):
    event = environ.get("CI_EVENT", "")
    decision = classify_changes(
        root,
        event=event,
        push_forced=push_forced(environ),
        base=environ.get("CI_BASE_SHA", ""),
        head=environ.get("CI_CHECKOUT_SHA" if event == "push" else "CI_HEAD_SHA", ""),
        branch=environ.get("CI_BRANCH", ""),
        repository=environ.get("CI_REPOSITORY", ""),
        force=environ.get("CI_MANUAL_FULL_GATE") == "true",
    )
    print(decision.reason, file=sys.stderr)
    key = environ.get("CIRCLE_CONTINUATION_KEY")
    if not key:
        raise ValueError("Missing continuation key")
    configuration = (root / ".circleci/continue.yml").read_text()
    transport(
        Request(
            "https://circleci.com/api/v2/pipeline/continue",
            method="POST",
            headers={"Content-Type": "application/json"},
            data=json.dumps(
                {
                    "continuation-key": key,
                    "configuration": configuration,
                    # Only this new parameter is passed. Original API parameters
                    # remain inherited, without conflicting with setup values.
                    "parameters": {"skip_validation": decision.skip_validation},
                }
            ).encode(),
        )
    )


def main():
    try:
        continue_pipeline(repository_root(__file__), os.environ, request_json)
    except HTTPError as error:
        print(f"CircleCI continuation failed (HTTP {error.code}).", file=sys.stderr)
        return 1
    except Exception as error:
        # Transport errors can contain the credential-bearing request body.
        print(
            f"CircleCI continuation failed ({type(error).__name__}).", file=sys.stderr
        )
        return 1
    print("CircleCI pipeline continued.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
