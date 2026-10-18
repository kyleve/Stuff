"""Select app channels and reject stale or conflicted CI publications."""

import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import plistlib
import re
import sys
import time
from typing import Optional, Union
from urllib.error import URLError
from urllib.request import Request
import zipfile

from Tools.InstallerKit.github_api import request_json
from Tools.InstallerKit.github_releases import GitHubReleases
from Tools.InstallerKit.installer_apps import load_app
from Tools.InstallerKit.installer_installation import manifest_url, site_url, validate_build_details, validate_bundle_version


LABEL = "installable"


@dataclass(frozen=True)
class Publication:
    sha: str
    pull_request: Optional[int]

    @property
    def channel(self):
        return f"pr-{self.pull_request}" if self.pull_request else "main"


@dataclass(frozen=True)
class Retirement:
    pull_request: int

    @property
    def channel(self):
        return f"pr-{self.pull_request}"


Plan = Optional[Union[Publication, Retirement]]


@dataclass(frozen=True)
class DistributionResult:
    summary: str
    receipt: Optional[dict]


def eligible(pr: dict, repository: str) -> bool:
    return (pr["state"] == "open"
            and pr["head"]["repo"] is not None
            and pr["head"]["repo"]["full_name"] == repository
            and pr["base"]["repo"]["full_name"] == repository
            and any(label["name"] == LABEL for label in pr["labels"]))


def select_plan(event_name: str, event: dict, repository: str, ref: str, sha: str) -> Plan:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid GitHub repository")
    if event["repository"]["full_name"] != repository:
        return None
    if event_name in ("push", "workflow_dispatch"):
        if ref != "refs/heads/main" or event.get("deleted") is True:
            return None
        revision = event["after"] if event_name == "push" else sha
        if not re.fullmatch(r"[0-9a-f]{40}", revision):
            raise ValueError("Invalid main commit SHA")
        return Publication(revision, None)
    if event_name != "pull_request_target":
        return None
    if event["action"] not in ("opened", "reopened", "synchronize", "labeled", "unlabeled", "closed"):
        return None
    pr = event["pull_request"]
    if pr["head"]["repo"] is None or pr["head"]["repo"]["full_name"] != repository:
        return None
    number = event["number"]
    if not isinstance(number, int) or isinstance(number, bool) or number < 1:
        raise ValueError("Invalid pull request number")
    # GitHub can replace a pending run with any later event in this channel.
    # Even unrelated label changes must preserve a pending refresh/retirement.
    if not eligible(pr, repository):
        return Retirement(number)
    revision = pr["head"]["sha"]
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Invalid pull request commit SHA")
    return Publication(revision, number)


def is_current(plan: Plan, repository: str, fetch) -> bool:
    if plan is None:
        return False
    if isinstance(plan, Publication) and plan.pull_request is None:
        return fetch(f"repos/{repository}/git/ref/heads/main")["object"]["sha"] == plan.sha
    # GitHub computes mergeability asynchronously. Retry delays total 30
    # seconds; recheck identity/eligibility after every wait.
    for delay in (0, 2, 4, 8, 16):
        if delay:
            time.sleep(delay)
        pr = fetch(f"repos/{repository}/pulls/{plan.pull_request}")
        if isinstance(plan, Retirement):
            return not eligible(pr, repository)
        if not eligible(pr, repository) or pr["head"]["sha"] != plan.sha:
            return False
        if pr["mergeable"] is True:
            return True
        if pr["mergeable"] is False:
            raise ValueError(f"PR #{plan.pull_request} has merge conflicts. Resolve the conflicts and push again.")
        if pr["mergeable"] is not None:
            raise ValueError("GitHub returned an invalid mergeability status")
    raise ValueError(f"GitHub has not finished checking merge conflicts for PR #{plan.pull_request}. Rerun this workflow.")


def github_fetch(path: str):
    token = os.environ.get("GH_TOKEN", "")
    if not token:
        raise ValueError("GH_TOKEN is required to check the current branch and label")
    return request_json(Request(f"https://api.github.com/{path}", headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }))


def validate_ipa(path: Path, plan: Publication, app) -> None:
    with zipfile.ZipFile(path) as archive:
        info = plistlib.loads(archive.read(f"{app.bundle_path}/Info.plist"))
        expected = {**app.required_info,
                    "CFBundleIdentifier": app.bundle_identifier,
                    "InstallerAppID": app.id, "InstallerGitStatus": "clean",
                    "InstallerGitSHA": plan.sha}
        for key, value in expected.items():
            if info.get(key) != value:
                raise ValueError(f"IPA {key} does not match the registered app build")
        for bundle in app.signed_bundles:
            for resource in ("embedded.mobileprovision", "_CodeSignature/CodeResources"):
                if not archive.getinfo(f"{bundle}/{resource}").file_size:
                    raise ValueError(f"IPA has no signing resource for {bundle}")


def finish(plan: Plan, repository: str, ipa: Optional[Path], fetch, service, identifier, feed_url, app) -> DistributionResult:
    if plan is None:
        return DistributionResult("No distribution change.", None)
    if isinstance(plan, Publication):
        if ipa is None:
            raise ValueError("An IPA is required for publication")
        validate_ipa(ipa, plan, app)
        url = manifest_url(feed_url, app.id, plan.channel, identifier)
        with zipfile.ZipFile(ipa) as archive:
            info = plistlib.loads(archive.read(f"{app.bundle_path}/Info.plist"))
        version = validate_bundle_version(info.get("CFBundleVersion"))
        details = validate_build_details({"version": info.get("CFBundleShortVersionString"),
                                          "minimumOSVersion": info.get("MinimumOSVersion"),
                                          "sizeBytes": ipa.stat().st_size})
    # Recheck before upload or issuing a retirement receipt. The feed publisher
    # checks again before saving the catalog. Each channel is serialized.
    if not is_current(plan, repository, fetch):
        return DistributionResult("Skipped: the branch, label, or pull request state changed.", None)
    if isinstance(plan, Retirement):
        return DistributionResult(
            f"Selected {plan.channel} for retirement in the next Pages deployment. Historical GitHub releases remain available.",
            {"action": "retire", "appID": app.id, "channel": plan.channel})
    ipa_url = service.publish(ipa, app.id, plan.channel, identifier, plan.sha, f"{app.name} — {plan.channel}")
    page_url = site_url(feed_url) + f"apps/{app.id}/{plan.channel}/"
    return DistributionResult(f"[{plan.channel}: install {app.name}]({page_url})\n\n"
                              f"Available after the Pages deployment succeeds.\n\nCommit: `{plan.sha}`",
                              {"action": "publish", "appID": app.id, "channel": plan.channel,
                               "sha": plan.sha, "manifestURL": url, "ipaURL": ipa_url,
                               "bundleVersion": version, "buildDetails": details})


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("plan", "finish"))
    parser.add_argument("--app", required=True)
    parser.add_argument("--event", type=Path, required=True)
    parser.add_argument("--event-name", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--ref", required=True)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--ipa", type=Path)
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--run")
    parser.add_argument("--attempt")
    parser.add_argument("--feed-url")
    args = parser.parse_args(argv)
    try:
        app = load_app(args.app)
        plan = select_plan(args.event_name, json.loads(args.event.read_text()),
                           args.repository, args.ref, args.sha)
        if args.command == "plan":
            if not is_current(plan, args.repository, github_fetch):
                plan = None
            action = "publish" if isinstance(plan, Publication) else "retire" if plan else "skip"
            output = (f"action={action}\nsha={plan.sha if isinstance(plan, Publication) else ''}\n"
                      f"channel={plan.channel if plan else ''}\n")
            if args.output:
                with args.output.open("a") as destination:
                    destination.write(output)
            print(output, end="")
        else:
            identifier = None
            if args.receipt and isinstance(plan, Publication):
                if args.ipa is None:
                    raise ValueError("An IPA is required for publication")
                from Tools.InstallerKit.installer_update_feed import GitHubUpdateFeed, build_id, build_order, channel_in
                identifier = build_id(args.run, args.attempt)
                with zipfile.ZipFile(args.ipa) as archive:
                    info = plistlib.loads(archive.read(f"{app.bundle_path}/Info.plist"))
                for key, value in {"InstallerAppID": app.id,
                                   "InstallerRepositoryURL": f"https://github.com/{args.repository}",
                                   "InstallerChannel": plan.channel,
                                   "InstallerRun": args.run,
                                   "InstallerAttempt": args.attempt,
                                   "InstallerGitSHA": plan.sha,
                                   "InstallerFeedURL": args.feed_url}.items():
                    if not value or info.get(key) != value:
                        raise ValueError(f"IPA {key} does not match this distribution run")
                feed = GitHubUpdateFeed(args.repository, os.environ.get("GH_TOKEN", ""))
                catalog, _ = feed.load()
                channel = channel_in(catalog, app.id, plan.channel)
                if channel and channel["releases"] and build_order(channel["releases"][0]["id"]) > build_order(identifier):
                    print("Skipped: this channel already has a newer published build.")
                    return 0
            if isinstance(plan, Publication) and identifier is None:
                raise ValueError("Publication requires a receipt, run, attempt, and feed URL")
            service = (GitHubReleases(args.repository, os.environ.get("GH_TOKEN", ""))
                       if isinstance(plan, Publication) else None)
            result = finish(plan, args.repository, args.ipa, github_fetch, service, identifier, args.feed_url, app)
            if args.receipt and result.receipt is not None:
                args.receipt.write_text(json.dumps({**result.receipt, "run": args.run, "attempt": args.attempt}))
            print(result.summary)
            if args.output:
                with args.output.open("a") as destination:
                    destination.write(f"{result.summary}\n")
    except (OSError, ValueError, KeyError, TypeError, URLError, zipfile.BadZipFile) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
