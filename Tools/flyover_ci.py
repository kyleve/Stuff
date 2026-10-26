"""Capture every registered app serially on the unsigned CircleCI worker."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

from Tools.flyover_apps import load_apps
from Tools.flyover_bundle import pack_bundle
from Tools.repository import repository_root


def build(output: Path, sha: str) -> None:
    workspace = repository_root(__file__)
    actual = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=workspace, text=True).strip()
    if actual != sha:
        raise ValueError('CircleCI checkout differs from the requested main commit; retry the controller')
    apps = load_apps()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='flyover-capture-') as temporary:
        root = Path(temporary)
        for app in apps:
            subprocess.run([str(workspace / 'flyover'), 'export', '--app', app.app_id,
                            '--output', str(root / app.app_id)], cwd=workspace, check=True,
                           env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})
        (root / 'publication.json').write_text(json.dumps({
            'schemaVersion': 1, 'commit': sha,
            'apps': [{'id': app.app_id, 'title': app.title} for app in apps],
        }))
        pack_bundle(root, output, sha)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    build(args.output, os.environ['FLYOVER_SOURCE_SHA'])
