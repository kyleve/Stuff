"""Check the Swift layouts that the pinned formatter cannot enforce."""

import os
from pathlib import Path
import subprocess
import sys

from Tools.repository import repository_root


def main(paths):
    root = repository_root(__file__)
    if paths:
        inputs = b"\0".join(os.fsencode(Path(path).absolute()) for path in paths)
    else:
        inputs = subprocess.check_output(
            ["git", "ls-files", "-z", "--", "*.swift"], cwd=root
        )
    swift = Path(
        subprocess.check_output(["xcrun", "--find", "swift"], text=True).strip()
    )
    modules = swift.parents[1] / "lib/swift/host"
    scanner = Path(__file__).with_name("SwiftLayoutLint.swift")
    return subprocess.run(
        [swift, "-I", modules, "-L", modules, scanner], cwd=root, input=inputs
    ).returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
