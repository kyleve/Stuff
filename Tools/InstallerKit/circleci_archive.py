"""Validate a trusted controller's archive request before checking out build code."""

import argparse
from dataclasses import dataclass
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from urllib.error import URLError
from urllib.request import Request
import zipfile

from Tools.InstallerKit.github_api import API_VERSION, request_json
from Tools.InstallerKit.installer_apps import load_app, archive_product
from Tools.InstallerKit.installer_distribution import Publication, is_current, validate_ipa
from Tools.InstallerKit.installer_installation import manifest_url
from Tools.InstallerKit.installer_update_feed import build_id


@dataclass(frozen=True)
class ArchiveRequest:
    """GitHub run identity stays stable across the CircleCI artifact handoff."""

    repository: str
    app_id: str
    sha: str
    channel: str
    run: str
    attempt: str
    feed_url: str

    def __post_init__(self):
        if (not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", self.repository)
                or any(part in (".", "..") for part in self.repository.split("/"))):
            raise ValueError("Invalid GitHub repository")
        if not re.fullmatch(r"[0-9a-f]{40}", self.sha):
            raise ValueError("An exact source commit is required")
        archive_product(self.app_id)
        manifest_url(self.feed_url, self.app_id, self.channel, build_id(self.run, self.attempt))

    @property
    def plan(self):
        number = None if self.channel == "main" else int(self.channel[3:])
        return Publication(self.sha, number)

    @property
    def parameters(self):
        return {"installer_archive": "true", "installer_app": self.app_id, "installer_sha": self.sha,
                "installer_channel": self.channel, "installer_run": self.run,
                "installer_attempt": self.attempt, "installer_feed_url": self.feed_url}

    def validate_ipa(self, path):
        app = load_app(self.app_id)
        validate_ipa(path, self.plan, app)
        with zipfile.ZipFile(path) as archive:
            info = plistlib.loads(archive.read(f"{app.bundle_path}/Info.plist"))
        expected = {"InstallerRepositoryURL": f"https://github.com/{self.repository}",
                    "InstallerChannel": self.channel, "InstallerRun": self.run,
                    "InstallerAttempt": self.attempt, "InstallerFeedURL": self.feed_url}
        for key, value in expected.items():
            if info.get(key) != value:
                raise ValueError(f"IPA {key} does not match the archive request")


def stage(request, output):
    """Validate the selected product before exposing a stable transport filename."""
    product = archive_product(request.app_id)
    source = output / "export" / f"{product}.ipa"
    request.validate_ipa(source)
    # Exclusive creation keeps retries from replacing another archive's bytes.
    os.link(source, output / "app.ipa")


def public_github_fetch(path):
    # Public repository reads need no GitHub credential on the signing worker.
    return request_json(Request(f"https://api.github.com/{path}", headers={
        "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": API_VERSION,
    }))


def prepare(request, source, fetch=public_github_fetch, run=subprocess.run):
    if source.exists() or source.is_symlink():
        raise ValueError("Archive source directory must not exist")
    repository = fetch(f"repos/{request.repository}")
    if repository.get("private") is not False or repository.get("full_name") != request.repository:
        raise ValueError("Archives require the registered public repository")
    if not is_current(request.plan, request.repository, fetch):
        raise ValueError("Archive request is no longer current and installable")
    # Every argument is separate; branch names and PR text never become shell code.
    run(["git", "clone", "--filter=blob:none", "--no-checkout",
         f"https://github.com/{request.repository}.git", str(source)], check=True)
    run(["git", "-C", str(source), "fetch", "--depth=1", "origin", request.sha], check=True)
    run(["git", "-C", str(source), "-c", "core.hooksPath=/dev/null", "checkout", "--detach", request.sha], check=True)
    revision = run(["git", "-C", str(source), "rev-parse", "HEAD"],
                   check=True, text=True, capture_output=True).stdout.strip()
    if revision != request.sha:
        raise ValueError("Checked-out commit does not match the archive request")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "validate", "stage"))
    parser.add_argument("path", type=Path)
    args = parser.parse_args(argv)
    try:
        request = ArchiveRequest(*(os.environ[name] for name in (
            "INSTALLER_REPOSITORY", "INSTALLER_APP_ID", "INSTALLER_BUILD_SHA", "INSTALLER_CHANNEL",
            "INSTALLER_RUN", "INSTALLER_ATTEMPT", "INSTALLER_FEED_URL")))
        if args.command == "prepare":
            prepare(request, args.path)
        elif args.command == "stage":
            stage(request, args.path)
        else:
            request.validate_ipa(args.path)
    except subprocess.CalledProcessError as error:
        return error.returncode
    except (OSError, ValueError, KeyError, TypeError, URLError, zipfile.BadZipFile) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
