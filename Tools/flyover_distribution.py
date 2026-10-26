"""Request native capture on CircleCI and retain a verified release bundle."""

import argparse
from dataclasses import dataclass
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.error import HTTPError, URLError
from urllib.request import Request, build_opener
import zipfile

from Tools.circleci_pipeline import ArtifactRedirects, CircleCI, artifact_url, wait_for_archive
from Tools.flyover_bundle import MAX_BYTES, unpack_bundle


@dataclass(frozen=True)
class CaptureRequest:
    sha: str

    def __post_init__(self):
        if not re.fullmatch(r'[0-9a-f]{40}', self.sha):
            raise ValueError('An exact main commit is required')

    @property
    def parameters(self):
        return {'flyover_export': 'true', 'flyover_sha': self.sha}


def download(url: str, output: Path, token: str) -> None:
    request = Request(artifact_url(url))
    request.add_unredirected_header('Circle-Token', token)
    with build_opener(ArtifactRedirects).open(request, timeout=120) as response, output.open('xb') as target:
        size = 0
        while chunk := response.read(1024 * 1024):
            size += len(chunk)
            if size > MAX_BYTES:
                raise ValueError('Flyover download exceeds the size budget')
            target.write(chunk)


def publish(project: str, definition: str, repository: str, sha: str, run: str, attempt: str) -> None:
    if not all(re.fullmatch(r'[1-9][0-9]*', value) for value in (run, attempt)):
        raise ValueError('Invalid GitHub run identity')
    request = CaptureRequest(sha)
    client = CircleCI(project, os.environ['CIRCLECI_TOKEN'], workflow='Flyover Export',
                      job='Export Flyover', artifact='flyover/atlases.zip')
    pipeline = client.start(definition, request)
    print(f'Waiting for Flyover capture pipeline {pipeline}', flush=True)
    with tempfile.TemporaryDirectory(prefix='flyover-publish-') as temporary:
        root = Path(temporary)
        archive = root / 'atlases.zip'
        download(wait_for_archive(client, pipeline), archive, client.token)
        extracted = root / 'verified'
        extracted.mkdir()
        unpack_bundle(archive, extracted, sha)
        # Immutable, non-latest releases retain the previous successful artifact.
        # Draft creation prevents an incomplete upload from becoming selectable.
        tag = f'flyover-atlas-{run}-{attempt}'
        subprocess.run(['gh', 'release', 'create', tag, str(archive), '--repo', repository,
                        '--target', sha, '--draft', '--prerelease', '--latest=false',
                        '--title', f'Flyover atlas {run}.{attempt}', '--notes', f'Native QA captures from {sha}.'], check=True)
        subprocess.run(['gh', 'release', 'edit', tag, '--repo', repository, '--draft=false'], check=True)
        subprocess.run(['gh', 'workflow', 'run', 'installer-pages.yml', '--repo', repository, '--ref', 'main'], check=True)


def main(arguments=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sha', required=True)
    args = parser.parse_args(arguments)
    try:
        publish(os.environ['CIRCLECI_PROJECT'], os.environ['CIRCLECI_PIPELINE'], os.environ['GITHUB_REPOSITORY'],
                args.sha, os.environ['GITHUB_RUN_ID'], os.environ['GITHUB_RUN_ATTEMPT'])
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        # Signed artifact URLs must not appear in controller logs.
        if isinstance(error, HTTPError):
            message = f'CircleCI request failed: HTTP {error.code}'
        elif isinstance(error, URLError):
            message = f'CircleCI request failed: {type(error.reason).__name__}'
        else:
            message = str(error)
        print(f'flyover publication: {message}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
