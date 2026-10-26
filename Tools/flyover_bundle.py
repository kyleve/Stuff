"""Bounded, validated transport for a complete set of generated atlases."""

from __future__ import annotations

import json
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import zipfile

from Tools.flyover_manifest import validate_artifact


MAX_BYTES = 900_000_000  # Leave space for the install site under Pages' 1 GB limit.
MAX_FILES = 100_000


def validate_bundle(root: Path, expected_sha: str | None = None) -> dict:
    receipt = json.loads((root / 'publication.json').read_text())
    if (receipt.get('schemaVersion') != 1
            or not re.fullmatch(r'[0-9a-f]{40}', receipt.get('commit', ''))
            or (expected_sha is not None and receipt['commit'] != expected_sha)
            or not isinstance(receipt.get('apps'), list) or not receipt['apps']):
        raise ValueError('Invalid Flyover publication identity')
    allowed = {'publication.json'}
    identities = set()
    for app in receipt['apps']:
        app_id = app.get('id')
        if (not isinstance(app_id, str) or not re.fullmatch(r'[a-z][a-z0-9-]*', app_id)
                or app_id in identities or not isinstance(app.get('title'), str)):
            raise ValueError('Invalid Flyover publication app')
        identities.add(app_id)
        artifact = validate_artifact(root / app_id)
        manifest = json.loads((artifact.root / 'manifest.json').read_text())
        if (manifest['application']['id'] != app_id or manifest['build']['commit'] != receipt['commit']
                or manifest['build']['dirty'] is not False):
            raise ValueError('Flyover capture does not match the clean publication commit')
        allowed.update(f'{app_id}/{path}' for path in artifact.allowed_paths)
        allowed.add(f'{app_id}/.flyover-generated')
    files = set()
    total = 0
    for path in root.rglob('*'):
        mode = path.lstat().st_mode
        if stat.S_ISDIR(mode):
            continue
        if not stat.S_ISREG(mode):
            raise ValueError('Flyover bundles require regular files')
        files.add(path.relative_to(root).as_posix())
        total += path.stat().st_size
    if files != allowed or total > MAX_BYTES or len(files) > MAX_FILES:
        raise ValueError('Flyover bundle assets or size do not match the publication')
    return receipt


def pack_bundle(root: Path, output: Path, sha: str) -> None:
    validate_bundle(root, sha)
    with zipfile.ZipFile(output, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(root.rglob('*')):
            if path.is_file():
                archive.write(path, path.relative_to(root).as_posix())


def unpack_bundle(source: Path, destination: Path, sha: str | None = None) -> dict:
    """Extract into a caller-owned empty temporary directory, never over a live site."""
    if any(destination.iterdir()):
        raise ValueError('Flyover extraction requires an empty directory')
    with zipfile.ZipFile(source) as archive:
        entries = archive.infolist()
        names = set()
        total = 0
        if len(entries) > MAX_FILES:
            raise ValueError('Too many Flyover bundle entries')
        for entry in entries:
            path = PurePosixPath(entry.filename)
            mode = entry.external_attr >> 16
            if (entry.filename in names or path.is_absolute() or '\\' in entry.filename
                    or any(part in ('', '.', '..') for part in entry.filename.split('/'))
                    or entry.is_dir() or stat.S_IFMT(mode) not in (0, stat.S_IFREG)
                    or entry.flag_bits & 1):
                raise ValueError('Unsafe Flyover bundle entry')
            names.add(entry.filename)
            total += entry.file_size
            if total > MAX_BYTES:
                raise ValueError('Flyover bundle exceeds the Pages size budget')
        for entry in entries:
            target = destination / entry.filename
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(entry) as input_file, target.open('xb') as output_file:
                shutil.copyfileobj(input_file, output_file)
    return validate_bundle(destination, sha)
