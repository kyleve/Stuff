"""Request a CircleCI archive and retrieve only that successful pipeline's IPA."""

import argparse
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
from uuid import UUID
import zipfile

from Tools.InstallerKit.circleci_archive import ArchiveRequest
from Tools.InstallerKit.github_api import request_json


WORKFLOW = "Installer Archive"
JOB = "Archive App"
ARTIFACT = "installer/app.ipa"
MAX_IPA_BYTES = 2_000_000_000  # GitHub Release asset limit; reject oversized handoffs.


def uuid(value):
    if not isinstance(value, str):
        raise ValueError("CircleCI returned an invalid identifier")
    return str(UUID(value))


def artifact_url(value):
    parsed = urlsplit(value)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.port is not None
            or parsed.username is not None or parsed.password is not None
            or not parsed.hostname.endswith(".circle-artifacts.com")):
        raise ValueError("Expected a CircleCI HTTPS artifact URL")
    return value


class ArtifactRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        parsed = urlsplit(newurl)
        if (parsed.scheme != "https" or not parsed.hostname or parsed.port is not None
                or parsed.username is not None or parsed.password is not None
                or not parsed.hostname.endswith((".circle-artifacts.com", ".amazonaws.com"))):
            raise ValueError("Unexpected CircleCI artifact redirect")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def download_ipa(url, destination, request, token):
    """Authenticate only to the artifact service, then validate before publication."""
    artifact_url(url)
    if destination.exists():
        raise ValueError("Archive destination must not exist")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as temporary:
        staged = Path(temporary) / "archive.ipa"
        download = Request(url)
        # urllib excludes unredirected headers from each redirected request.
        # CircleCI can redirect to a signed storage URL; that host gets no token.
        download.add_unredirected_header("Circle-Token", token)
        with build_opener(ArtifactRedirects).open(download, timeout=120) as response, staged.open("wb") as output:
            size = 0
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                size += len(chunk)
                if size > MAX_IPA_BYTES:
                    raise ValueError("CircleCI archive exceeds the release asset limit")
                output.write(chunk)
        request.validate_ipa(staged)
        # Exclusive creation refuses to overwrite another attempt's output.
        os.link(staged, destination)


class CircleCI:
    """Credentials go only to CircleCI services and never follow redirects."""

    def __init__(self, project, token, transport=request_json):
        if (not re.fullmatch(r"(?:circleci|gh|github)/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", project)
                or any(part in (".", "..") for part in project.split("/")) or not token):
            raise ValueError("CircleCI project slug and API token are required")
        self.project = project
        self.token = token
        self.transport = transport

    def request(self, method, path, value=None):
        return self.transport(Request(f"https://circleci.com/api/v2/{path}", method=method,
                                      data=json.dumps(value).encode() if value is not None else None,
                                      headers={"Circle-Token": self.token, "Content-Type": "application/json"}))

    def items(self, path):
        result, seen = [], set()
        page = path
        for _ in range(100):
            response = self.request("GET", page)
            result.extend(response["items"])
            token = response.get("next_page_token")
            if not token:
                return result
            if token in seen:
                raise ValueError("CircleCI repeated an API page")
            seen.add(token)
            page = f"{path}?page-token={quote(token, safe='')}"
        raise ValueError("CircleCI returned too many API pages")

    def start(self, definition, request):
        response = self.request("POST", f"project/{self.project}/pipeline/run", {
            "definition_id": uuid(definition), "config": {"branch": "main"},
            "checkout": {"branch": "main"}, "parameters": request.parameters,
        })
        if "id" not in response:
            raise ValueError("CircleCI did not create an archive pipeline; check pipeline skip rules")
        return uuid(response["id"])

    def artifact(self, pipeline):
        state = self.request("GET", f"pipeline/{pipeline}")
        if state.get("project_slug") != self.project or state.get("errors") or state.get("state") == "errored":
            raise ValueError("CircleCI archive pipeline failed configuration or project validation")
        workflows = [item for item in self.items(f"pipeline/{pipeline}/workflow") if item["name"] == WORKFLOW]
        if not workflows:
            return None
        if len(workflows) != 1 or workflows[0]["pipeline_id"] != pipeline:
            raise ValueError("CircleCI archive workflow is ambiguous; rerun the GitHub controller")
        workflow = workflows[0]
        if workflow["status"] in ("running", "on_hold"):
            return None
        if workflow["status"] != "success":
            raise ValueError(f"CircleCI archive workflow ended with status {workflow['status']}")
        jobs = [item for item in self.items(f"workflow/{uuid(workflow['id'])}/job") if item["name"] == JOB]
        if len(jobs) != 1 or jobs[0]["status"] != "success" or type(jobs[0].get("job_number")) is not int:
            raise ValueError("CircleCI archive job did not succeed")
        artifacts = [item for item in self.items(f"project/{self.project}/{jobs[0]['job_number']}/artifacts")
                     if item["path"] == ARTIFACT]
        if len(artifacts) != 1:
            raise ValueError("CircleCI archive job must contain exactly one IPA artifact")
        return artifact_url(artifacts[0]["url"])


def wait_for_archive(client, pipeline, *, timeout=3600, clock=time.monotonic, sleep=time.sleep):
    deadline = clock() + timeout
    while clock() < deadline:
        url = client.artifact(pipeline)
        if url is not None:
            return url
        sleep(15)
    raise ValueError(f"CircleCI archive timed out (pipeline {pipeline}); inspect CircleCI before retrying")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True)
    parser.add_argument("--definition", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--app", required=True)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--channel", required=True)
    parser.add_argument("--run", required=True)
    parser.add_argument("--attempt", required=True)
    parser.add_argument("--feed-url", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        request = ArchiveRequest(args.repository, args.app, args.sha, args.channel, args.run, args.attempt, args.feed_url)
        if args.output.exists():
            raise ValueError("Archive destination must not exist")
        client = CircleCI(args.project, os.environ.get("CIRCLECI_TOKEN", ""))
        pipeline = client.start(args.definition, request)
        print(f"Waiting for CircleCI archive pipeline {pipeline}", flush=True)
        download_ipa(wait_for_archive(client, pipeline), args.output, request, client.token)
        print("Retrieved and validated the signed archive.")
    except (OSError, ValueError, KeyError, TypeError, URLError, zipfile.BadZipFile) as error:
        # URL errors can contain signed download URLs; retain details as the cause.
        if isinstance(error, HTTPError):
            message = f"CircleCI artifact download failed: HTTP {error.code}"
        elif isinstance(error, URLError):
            message = f"CircleCI request failed: {type(error.reason).__name__}"
        else:
            message = str(error)
        print(f"error: {message}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
