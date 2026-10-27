"""Shared CircleCI pipeline and artifact selection transport."""

import json
import re
import time
from urllib.parse import quote, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
from uuid import UUID


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def request_json(request):
    with build_opener(NoRedirects).open(request, timeout=120) as response:
        return json.load(response)


def uuid(value):
    if not isinstance(value, str):
        raise ValueError("CircleCI returned an invalid identifier")
    return str(UUID(value))


def artifact_url(value):
    parsed = urlsplit(value)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.port is not None
        or parsed.username is not None
        or parsed.password is not None
        or not parsed.hostname.endswith(".circle-artifacts.com")
    ):
        raise ValueError("Expected a CircleCI HTTPS artifact URL")
    return value


class ArtifactRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        parsed = urlsplit(newurl)
        if (
            parsed.scheme != "https"
            or not parsed.hostname
            or parsed.port is not None
            or parsed.username is not None
            or parsed.password is not None
            or not parsed.hostname.endswith((".circle-artifacts.com", ".amazonaws.com"))
        ):
            raise ValueError("Unexpected CircleCI artifact redirect")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


class CircleCI:
    """Credentials go only to CircleCI services and never follow redirects."""

    def __init__(
        self, project, token, transport=request_json, *, workflow, job, artifact
    ):
        if (
            not re.fullmatch(
                r"(?:circleci|gh|github)/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", project
            )
            or any(part in (".", "..") for part in project.split("/"))
            or not token
        ):
            raise ValueError("CircleCI project slug and API token are required")
        self.workflow = workflow
        self.job = job
        self.artifact_path = artifact
        self.project = project
        self.token = token
        self.transport = transport

    def request(self, method, path, value=None):
        return self.transport(
            Request(
                f"https://circleci.com/api/v2/{path}",
                method=method,
                data=json.dumps(value).encode() if value is not None else None,
                headers={
                    "Circle-Token": self.token,
                    "Content-Type": "application/json",
                },
            )
        )

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
        response = self.request(
            "POST",
            f"project/{self.project}/pipeline/run",
            {
                "definition_id": uuid(definition),
                "config": {"branch": "main"},
                "checkout": {"branch": "main"},
                "parameters": request.parameters,
            },
        )
        if "id" not in response:
            raise ValueError(
                "CircleCI did not create a pipeline; check pipeline skip rules"
            )
        return uuid(response["id"])

    def artifact(self, pipeline):
        state = self.request("GET", f"pipeline/{pipeline}")
        if (
            state.get("project_slug") != self.project
            or state.get("errors")
            or state.get("state") == "errored"
        ):
            raise ValueError(
                "CircleCI pipeline failed configuration or project validation"
            )
        workflows = [
            item
            for item in self.items(f"pipeline/{pipeline}/workflow")
            if item["name"] == self.workflow
        ]
        if not workflows:
            return None
        if len(workflows) != 1 or workflows[0]["pipeline_id"] != pipeline:
            raise ValueError(
                "CircleCI workflow is ambiguous; rerun the GitHub controller"
            )
        workflow = workflows[0]
        if workflow["status"] in ("running", "on_hold"):
            return None
        if workflow["status"] != "success":
            raise ValueError(
                f"CircleCI workflow ended with status {workflow['status']}"
            )
        jobs = [
            item
            for item in self.items(f"workflow/{uuid(workflow['id'])}/job")
            if item["name"] == self.job
        ]
        if (
            len(jobs) != 1
            or jobs[0]["status"] != "success"
            or type(jobs[0].get("job_number")) is not int
        ):
            raise ValueError("CircleCI artifact job did not succeed")
        artifacts = [
            item
            for item in self.items(
                f"project/{self.project}/{jobs[0]['job_number']}/artifacts"
            )
            if item["path"] == self.artifact_path
        ]
        if len(artifacts) != 1:
            raise ValueError("CircleCI job must contain exactly one requested artifact")
        return artifact_url(artifacts[0]["url"])


def wait_for_archive(
    client, pipeline, *, timeout=3600, clock=time.monotonic, sleep=time.sleep
):
    deadline = clock() + timeout
    while clock() < deadline:
        url = client.artifact(pipeline)
        if url is not None:
            return url
        sleep(15)
    raise ValueError(
        f"CircleCI archive timed out (pipeline {pipeline}); inspect CircleCI before retrying"
    )
