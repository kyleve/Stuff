"""Prepare the generated installer-site fixture for the CircleCI iOS test builder."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from Tools.InstallerKit.installer_apps import load_apps
from Tools.repository import repository_root


ROOT = repository_root(__file__)
INPUT_PATHS = (
    "Tools/InstallerKit",
    "Tools/Tests/Fixtures",
    "Tools/astro_site.py",
    "Tools/repository.py",
    "Tools/circleci_pipeline.py",
    ".circleci/installer_snapshot_fixture.py",
    ".circleci/continue.yml",
    ".github/installer-apps.json",
    ".mise.toml",
    ".npmrc",
    ".python-version",
    ".xcode-version",
    ".xcode-build-version",
    ":(glob)**/package.json",
    "package-lock.json",
    "npm-shrinkwrap.json",
    "Project.swift",
)
FIXTURE = "InstallerSiteSnapshots.json"


def input_digest(root):
    # The builder starts with a clean checkout. Imports and npm can add untracked
    # files between the key, restore and prepare steps.
    names = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--", *INPUT_PATHS],
        cwd=root,
    )
    paths = {Path(os.fsdecode(name)) for name in names.split(b"\0") if name}
    for app in load_apps(root / ".github/installer-apps.json").values():
        for artwork in (app.presentation.icon, app.presentation.dark_icon):
            if artwork:
                paths.add(Path(artwork))

    runtime = (
        sys.implementation.name,
        platform.python_version(),
        sys.platform,
        platform.release(),
        platform.machine(),
    )
    digest = hashlib.sha256(json.dumps(runtime).encode())
    for relative in sorted(paths):
        path = root / relative
        if root not in path.resolve().parents:
            raise ValueError(f"Fixture input escapes the repository: {relative}")
        digest.update(os.fsencode(relative) + b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def receipt_for(fixture, key):
    content = fixture.read_bytes()
    return {
        "input_sha256": key,
        "output_sha256": hashlib.sha256(content).hexdigest(),
        "bytes": len(content),
    }


def valid_receipt(cache, key):
    try:
        saved = json.loads((cache / "receipt.json").read_bytes())
        if isinstance(saved, dict) and saved.get("input_sha256") == key:
            if saved == receipt_for(cache / FIXTURE, key):
                return saved
    except (FileNotFoundError, ValueError):
        pass
    return None


def prepare(root):
    cache = root / ".build" / "installer-site-fixture"
    cache.mkdir(parents=True, exist_ok=True)
    # A second prepare in the same checkout can reuse the completed pair.
    with (cache.parent / "installer-site-fixture.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        key = input_digest(root)
        receipt = valid_receipt(cache, key)
        status = "hit" if receipt else "miss"
        if receipt is None:
            subprocess.run(["mise", "exec", "--", "npm", "ci"], cwd=root, check=True)
            with tempfile.TemporaryDirectory(dir=cache) as staged_path:
                staged = Path(staged_path)
                subprocess.run(
                    [
                        sys.executable,
                        "-m",
                        "Tools.Tests.Fixtures.installer_update_site_snapshots",
                        "--output",
                        str(staged / FIXTURE),
                    ],
                    cwd=root,
                    check=True,
                )
                receipt = receipt_for(staged / FIXTURE, key)
                (staged / "receipt.json").write_text(json.dumps(receipt) + "\n")
                # Publishing the receipt last makes an interrupted replacement a miss.
                (staged / FIXTURE).replace(cache / FIXTURE)
                (staged / "receipt.json").replace(cache / "receipt.json")
        print("Installer snapshot fixture", status, json.dumps(receipt, sort_keys=True))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("key", "prepare"))
    args = parser.parse_args()
    try:
        if args.command == "key":
            print(input_digest(ROOT))
        else:
            prepare(ROOT)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
