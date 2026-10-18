"""Publish the shared installer catalog after GitHub publishes a verified signed build."""

import argparse
import base64
from copy import deepcopy
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.error import HTTPError
from urllib.request import Request

from github_api import request_json
from installer_installation import validate_release
from installer_apps import load_app, validate_metadata


BRANCH = "installer-update-feed"
FILE = "updates.json"
HISTORY_LIMIT = 100


def build_id(run, attempt):
    if not str(run).isdigit() or not str(attempt).isdigit() or int(run) < 1 or int(attempt) < 1:
        raise ValueError("A positive GitHub run ID and attempt are required")
    return {"run": int(run), "attempt": int(attempt)}


def build_order(value):
    return value["run"], value["attempt"]


def app_in(catalog, app_id):
    return next((app for app in catalog["apps"] if app["id"] == app_id), None)


def channel_in(catalog, app_id, name):
    app = app_in(catalog, app_id)
    return next((channel for channel in app["channels"] if channel["name"] == name), None) if app else None


def read_catalog(value):
    if value.get("schemaVersion") != 3 or not isinstance(value.get("apps"), list):
        raise ValueError("Unsupported update catalog")
    ids, bundles = set(), set()
    for app in value["apps"]:
        validate_metadata(app)
        if app["id"] in ids or app["bundleIdentifier"] in bundles:
            raise ValueError("Duplicate installer app or bundle identifier")
        ids.add(app["id"])
        bundles.add(app["bundleIdentifier"])
        names = [channel["name"] for channel in app["channels"]]
        if len(names) != len(set(names)):
            raise ValueError("Duplicate update channels")
    return value


def apply_change(catalog, app, channel, release):
    """Merge one channel without replacing unrelated concurrent publications."""
    result = deepcopy(read_catalog(catalog))
    current_app = app_in(result, app.id)
    if current_app is None:
        current_app = {**app.metadata, "channels": []}
        result["apps"].append(current_app)
    elif current_app["bundleIdentifier"] != app.bundle_identifier:
        raise ValueError("An installer app ID cannot change its bundle identifier")
    current_app["name"] = app.name
    current = channel_in(result, app.id, channel)
    if current is None:
        current = {"name": channel, "active": False, "releases": []}
        current_app["channels"].append(current)
    if release is None:
        current["active"] = False
    else:
        releases = current["releases"]
        if releases and build_order(release["id"]) <= build_order(releases[0]["id"]):
            return result
        current["active"] = True
        current["releases"] = [release] + releases[:HISTORY_LIMIT - 1]
    current_app["channels"].sort(key=lambda item: item["name"])
    result["apps"].sort(key=lambda item: item["id"])
    return read_catalog(result)


def changes_since(previous, sha, run=subprocess.run):
    """Keep all incoming commits; mark rebases and unavailable ancestry explicitly."""
    if previous is None:
        return {"baseSHA": None, "historyChanged": False, "commits": []}
    base = previous["sha"]
    available = run(["git", "cat-file", "-e", f"{base}^{{commit}}"], capture_output=True).returncode == 0
    if not available:
        available = run(["git", "fetch", "origin", base], capture_output=True).returncode == 0
    if not available:
        return {"baseSHA": None, "historyChanged": True, "commits": []}
    ancestry = run(["git", "merge-base", "--is-ancestor", base, sha], capture_output=True)
    if ancestry.returncode not in (0, 1):
        raise ValueError("Could not check update ancestry")
    history = run(["git", "log", "--format=%H%x00%s", f"{base}..{sha}"],
                  capture_output=True, text=True, check=True)
    commits = []
    for line in history.stdout.splitlines():
        commit_sha, subject = line.split("\0", 1)
        commits.append({"sha": commit_sha, "subject": subject})
    return {"baseSHA": base, "historyChanged": ancestry.returncode == 1, "commits": commits}


class GitHubUpdateFeed:
    """CAS writes preserve other channels; deployment always reads the latest catalog."""

    def __init__(self, repository, token, transport=request_json):
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository) or not token:
            raise ValueError("GitHub repository and token are required for the update feed")
        self.repository = repository
        self.token = token
        self.transport = transport

    def request(self, method, path, value=None, allow_missing=False):
        request = Request(f"https://api.github.com/repos/{self.repository}/{path}",
                          method=method, data=json.dumps(value).encode() if value is not None else None,
                          headers={"Authorization": f"Bearer {self.token}",
                                   "Accept": "application/vnd.github+json",
                                   "Content-Type": "application/json",
                                   "X-GitHub-Api-Version": "2022-11-28"})
        return self.transport(request, allow_missing=allow_missing)

    def load(self):
        response = self.request("GET", f"contents/{FILE}?ref={BRANCH}", allow_missing=True)
        if response is None:
            return {"schemaVersion": 3, "apps": []}, None
        if response.get("encoding") != "base64":
            raise ValueError("Update catalog exceeds the GitHub Contents API size limit")
        return read_catalog(json.loads(base64.b64decode(response["content"]))), response["sha"]

    def ensure_branch(self):
        if self.request("GET", f"git/ref/heads/{BRANCH}", allow_missing=True) is not None:
            return
        main = self.request("GET", "git/ref/heads/main")["object"]["sha"]
        try:
            self.request("POST", "git/refs", {"ref": f"refs/heads/{BRANCH}", "sha": main})
        except ValueError as error:
            if not isinstance(error.__cause__, HTTPError) or error.__cause__.code != 422:
                raise
            # Another channel can create the branch concurrently.
            self.request("GET", f"git/ref/heads/{BRANCH}")

    def save(self, app, channel, make_release, is_current):
        self.ensure_branch()
        for _ in range(5):
            catalog, revision = self.load()
            if not is_current():
                return False
            current = channel_in(catalog, app.id, channel)
            previous = current["releases"][0] if current and current["releases"] else None
            release = make_release(previous)
            updated = apply_change(catalog, app, channel, release)
            if updated == catalog:
                return True
            content = json.dumps(updated, ensure_ascii=False, separators=(",", ":")).encode()
            if len(content) > 900_000:
                raise ValueError("Update catalog is too large; reduce retained history before retrying")
            body = {"branch": BRANCH, "message": f"Update {app.id} channel {channel}",
                    "content": base64.b64encode(content).decode()}
            if revision is not None:
                body["sha"] = revision
            try:
                self.request("PUT", f"contents/{FILE}", body)
                return True
            except ValueError as error:
                if not isinstance(error.__cause__, HTTPError) or error.__cause__.code not in (409, 422):
                    raise
        raise ValueError("Update catalog changed repeatedly; rerun this workflow")

    def deploy(self):
        self.request("POST", "actions/workflows/installer-pages.yml/dispatches", {"ref": "main"})


def publish_receipt(receipt, feed, fetch, feed_url, run=subprocess.run):
    from installer_distribution import Publication, Retirement, is_current

    app = load_app(receipt["appID"])
    channel = receipt["channel"]
    if not re.fullmatch(r"main|pr-[1-9][0-9]*", channel):
        raise ValueError("Invalid distribution channel")
    number = None if channel == "main" else int(channel[3:])
    if receipt["action"] == "publish":
        plan = Publication(receipt["sha"], number)
        identifier = build_id(receipt["run"], receipt["attempt"])
        if not re.fullmatch(r"[0-9a-f]{40}", plan.sha):
            raise ValueError("Invalid published commit")
        validate_release({**receipt, "id": identifier}, feed.repository, app.id, channel, feed_url)

        def make_release(previous):
            return {"id": identifier, "sha": plan.sha,
                    "manifestURL": receipt["manifestURL"], "ipaURL": receipt["ipaURL"],
                    "bundleVersion": receipt["bundleVersion"],
                    **({"buildDetails": receipt["buildDetails"]} if "buildDetails" in receipt else {}),
                    "publishedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    **changes_since(previous, plan.sha, run)}
    elif receipt["action"] == "retire" and number is not None:
        plan = Retirement(number)
        make_release = lambda _: None
    else:
        raise ValueError("Invalid publication receipt")
    if feed.save(app, channel, make_release, lambda: is_current(plan, feed.repository, fetch)):
        feed.deploy()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--feed-url", required=True)
    args = parser.parse_args(argv)
    try:
        from installer_distribution import github_fetch
        if not args.receipt.exists():
            print("No publication receipt; update catalog unchanged.")
            return 0
        feed = GitHubUpdateFeed(args.repository, os.environ.get("GH_TOKEN", ""))
        publish_receipt(json.loads(args.receipt.read_text()), feed, github_fetch, args.feed_url)
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
