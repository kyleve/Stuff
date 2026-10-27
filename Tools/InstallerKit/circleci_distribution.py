"""Request a CircleCI archive and retrieve only that successful pipeline's IPA."""

import argparse
from http.client import HTTPException
import os
from pathlib import Path
import sys
import tempfile
from urllib.error import HTTPError, URLError
from urllib.request import Request, build_opener
import zipfile

from Tools.InstallerKit.circleci_archive import ArchiveRequest
from Tools.circleci_pipeline import (
    ArtifactRedirects,
    artifact_url,
    CircleCI as PipelineClient,
    wait_for_archive,
)
from Tools.InstallerKit.github_api import request_json


WORKFLOW = "Installer Archive"
JOB = "Archive App"
ARTIFACT = "installer/app.ipa"
MAX_IPA_BYTES = 2_000_000_000  # GitHub Release asset limit; reject oversized handoffs.


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
        with (
            build_opener(ArtifactRedirects).open(download, timeout=120) as response,
            staged.open("wb") as output,
        ):
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


class CircleCI(PipelineClient):
    """Installer-specific artifact selection over the shared transport."""

    def __init__(self, project, token, transport=request_json):
        super().__init__(
            project, token, transport, workflow=WORKFLOW, job=JOB, artifact=ARTIFACT
        )


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
        request = ArchiveRequest(
            args.repository,
            args.app,
            args.sha,
            args.channel,
            args.run,
            args.attempt,
            args.feed_url,
        )
        if args.output.exists():
            raise ValueError("Archive destination must not exist")
        client = CircleCI(args.project, os.environ.get("CIRCLECI_TOKEN", ""))
        pipeline = client.start(args.definition, request)
        print(f"Waiting for CircleCI archive pipeline {pipeline}", flush=True)
        download_ipa(
            wait_for_archive(client, pipeline), args.output, request, client.token
        )
        print("Retrieved and validated the signed archive.")
    except (
        OSError,
        ValueError,
        KeyError,
        TypeError,
        HTTPException,
        URLError,
        zipfile.BadZipFile,
    ) as error:
        # URL errors can contain signed download URLs; retain details as the cause.
        if isinstance(error, HTTPError):
            message = f"CircleCI artifact download failed: HTTP {error.code}"
        elif isinstance(error, URLError):
            message = f"CircleCI request failed: {type(error.reason).__name__}"
        else:
            # Header validation errors embed header values in their text.
            # Never print arbitrary exception text, arguments, or response data.
            message = f"{type(error).__name__}; archive retrieval did not complete"
        print(f"error: {message}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
