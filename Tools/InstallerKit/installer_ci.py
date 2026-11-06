"""Publish a CircleCI workspace archive through the existing installer policy."""

import argparse
import json
import os
from pathlib import Path
import sys
import zipfile

from Tools.InstallerKit.circleci_archive import ArchiveRequest
from Tools.InstallerKit.github_releases import GitHubReleases
from Tools.InstallerKit.installer_apps import load_app
from Tools.InstallerKit.installer_installation import validate_workflow_url
from Tools.InstallerKit.installer_distribution import (
    Retirement,
    finish,
    github_fetch,
    is_current,
)
from Tools.InstallerKit.installer_update_feed import (
    BuildStatus,
    GitHubUpdateFeed,
    build_id,
    publish_receipt,
    publish_status,
)


def request_from_environment(environ):
    return ArchiveRequest(
        *(
            environ[name]
            for name in (
                "INSTALLER_REPOSITORY",
                "INSTALLER_APP_ID",
                "INSTALLER_BUILD_SHA",
                "INSTALLER_CHANNEL",
                "INSTALLER_RUN",
                "INSTALLER_ATTEMPT",
                "INSTALLER_FEED_URL",
            )
        )
    )


def prepare(request, feed, fetch, workflow_url=None):
    if workflow_url is not None:
        validate_workflow_url(workflow_url)
    if not is_current(request.plan, request.repository, fetch):
        raise ValueError("Publication request is no longer current")
    publish_status(
        request.app_id,
        request.channel,
        BuildStatus(
            "preparing",
            build_id(request.run, request.attempt),
            request.sha,
            workflow_url,
        ),
        feed,
        fetch,
    )


def complete(request, archive, feed, fetch, releases, workflow_url=None):
    """A missing/invalid workspace IPA fails the attempt without replacing a release."""
    if workflow_url is not None:
        validate_workflow_url(workflow_url)
    try:
        request.validate_ipa(archive)
        result = finish(
            request.plan,
            request.repository,
            archive,
            fetch,
            releases,
            build_id(request.run, request.attempt),
            request.feed_url,
            load_app(request.app_id),
        )
        if result.receipt is not None:
            publish_receipt(
                {
                    **result.receipt,
                    "run": request.run,
                    "attempt": request.attempt,
                    **(
                        {"workflowURL": workflow_url}
                        if workflow_url is not None
                        else {}
                    ),
                },
                feed,
                fetch,
                request.feed_url,
            )
        return result.summary
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile):
        publish_status(
            request.app_id,
            request.channel,
            BuildStatus(
                "failed",
                build_id(request.run, request.attempt),
                request.sha,
                workflow_url,
            ),
            feed,
            fetch,
        )
        raise


def retire(repository, app_id, number, feed_url, feed, fetch):
    result = finish(
        Retirement(number),
        repository,
        None,
        fetch,
        None,
        None,
        feed_url,
        load_app(app_id),
    )
    if result.receipt is not None:
        publish_receipt(result.receipt, feed, fetch, feed_url)
    return result.summary


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "finish", "fail", "retire"))
    parser.add_argument("--workspace", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        repository = os.environ["INSTALLER_REPOSITORY"]
        token = os.environ["GH_TOKEN"]
        workflow_url = os.environ["INSTALLER_WORKFLOW_URL"]
        feed = GitHubUpdateFeed(repository, token)
        if args.command == "retire":
            print(
                retire(
                    repository,
                    os.environ["INSTALLER_APP_ID"],
                    int(os.environ["INSTALLER_PR"]),
                    os.environ["INSTALLER_FEED_URL"],
                    feed,
                    github_fetch,
                )
            )
        else:
            request = request_from_environment(os.environ)
            if args.command == "prepare":
                prepare(request, feed, github_fetch, workflow_url)
                args.workspace.mkdir(parents=True, exist_ok=True)
                (args.workspace / "request.json").write_text(
                    json.dumps(request.__dict__)
                )
            elif args.command == "fail":
                publish_status(
                    request.app_id,
                    request.channel,
                    BuildStatus(
                        "failed",
                        build_id(request.run, request.attempt),
                        request.sha,
                        workflow_url,
                    ),
                    feed,
                    github_fetch,
                )
            else:
                if (
                    json.loads((args.workspace / "request.json").read_text())
                    != request.__dict__
                ):
                    raise ValueError("Workspace publication identity does not match")
                print(
                    complete(
                        request,
                        args.workspace / "app.ipa",
                        feed,
                        github_fetch,
                        GitHubReleases(repository, token),
                        workflow_url,
                    )
                )
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile) as error:
        print(
            f"Installer publication failed ({type(error).__name__}).", file=sys.stderr
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
