"""Remove expired Flyover release bundles after a successful Pages deployment."""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
import json
import os
import re
import subprocess
import sys
from urllib.request import Request

from Tools.flyover_pages import latest_release
from Tools.InstallerKit.github_api import API_VERSION, request_json


def expired_releases(releases: list[dict], deployed: str, now: datetime) -> list[int]:
    """Keep a week, the deployed bundle, and the newest published bundle.

    Validate the complete inventory before returning any deletion targets.
    Drafts and unrelated releases are outside this retention policy.
    """
    candidates = []
    identifiers = set()
    tags = set()
    for release in releases:
        if not re.fullmatch(
            r"flyover-atlas-[1-9][0-9]*-[1-9][0-9]*", release.get("tag_name", "")
        ) or release.get("draft", True):
            continue
        if type(release.get("id")) is not int or release["id"] <= 0:
            raise ValueError("Invalid Flyover release ID")
        if release["id"] in identifiers or release["tag_name"] in tags:
            raise ValueError("Duplicate Flyover release identity")
        identifiers.add(release["id"])
        tags.add(release["tag_name"])
        timestamp = release.get("published_at")
        if not isinstance(timestamp, str):
            raise ValueError("Flyover release needs a publication time")
        published = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
        if published.utcoffset() is None:
            raise ValueError("Flyover publication time needs a time zone")
        candidates.append((release, published))
    latest = latest_release([release for release, _ in candidates])
    if latest is None or deployed not in {
        release["tag_name"] for release, _ in candidates
    }:
        raise ValueError("The deployed Flyover release is missing from the inventory")
    protected = {deployed, latest["tag_name"]}
    cutoff = now - timedelta(days=7)
    return [
        release["id"]
        for release, published in candidates
        if release["tag_name"] not in protected and published < cutoff
    ]


def prune(repository: str, deployed: str, now: datetime) -> None:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid repository name")
    pages = json.loads(
        subprocess.check_output(
            ["gh", "api", f"repos/{repository}/releases", "--paginate", "--slurp"],
            text=True,
        )
    )
    targets = expired_releases(
        [release for page in pages for release in page], deployed, now
    )
    for release_id in targets:
        # Delete the exact inventoried release and its assets, not a mutable tag.
        # Git tags remain as lightweight provenance records.
        request_json(
            Request(
                f"https://api.github.com/repos/{repository}/releases/{release_id}",
                method="DELETE",
                headers={
                    "Authorization": f"Bearer {os.environ['GH_TOKEN']}",
                    "Accept": "application/vnd.github+json",
                    "X-GitHub-Api-Version": API_VERSION,
                },
            ),
            # Another successful deployment may have retired this exact ID.
            # The shared transport still fails on authentication and server errors.
            allow_missing=True,
        )
        print(f"Removed expired Flyover release {release_id}", flush=True)
    print(f"Flyover retention: removed {len(targets)} expired releases")


def main(arguments=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deployed-release", required=True)
    args = parser.parse_args(arguments)
    try:
        prune(
            os.environ["GITHUB_REPOSITORY"],
            args.deployed_release,
            datetime.now(timezone.utc),
        )
    except (
        OSError,
        ValueError,
        KeyError,
        TypeError,
        subprocess.CalledProcessError,
    ) as error:
        print(f"Flyover retention failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
