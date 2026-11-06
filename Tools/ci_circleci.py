"""Continue CircleCI with the shared PR classification before allocating Macs."""

import json
import os
import sys
from urllib.error import HTTPError
from urllib.request import Request

from Tools.ci_changes import classify_changes
from Tools.circleci_pipeline import request_json
from Tools.repository import repository_root


def continue_configuration(configuration, parameters, environ, transport):
    """Submit one native continuation without exposing its short-lived credential."""
    key = environ.get("CIRCLE_CONTINUATION_KEY")
    if not key:
        raise ValueError("Missing continuation key")
    transport(
        Request(
            "https://circleci.com/api/v2/pipeline/continue",
            method="POST",
            headers={"Content-Type": "application/json"},
            data=json.dumps(
                {
                    "continuation-key": key,
                    "configuration": configuration,
                    "parameters": parameters,
                }
            ).encode(),
        )
    )


def continue_pipeline(root, environ, transport):
    decision = classify_changes(
        root,
        event=environ.get("CI_EVENT", ""),
        base=environ.get("CI_BASE_SHA", ""),
        head=environ.get("CI_HEAD_SHA", ""),
        force=environ.get("CI_MANUAL_FULL_GATE") == "true",
    )
    print(decision.reason, file=sys.stderr)
    configuration = "\n".join(
        (root / ".circleci" / name).read_text() for name in ("jobs.yml", "continue.yml")
    )
    continue_configuration(
        configuration, {"docs_only": decision.docs_only}, environ, transport
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
