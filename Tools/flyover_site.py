"""Build Flyover's Astro viewer and run isolated development or artifact previews."""

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile

from Tools.astro_site import astro_command, stage_workspace
from Tools.flyover_manifest import validate_artifact
from Tools.flyover_artifact_access import open_artifact_root, open_file_beneath
from Tools.repository import repository_root

ROOT = repository_root(__file__)
SITE = ROOT / "Shared/Flyover/Web"
BUILD_ROOT = SITE / ".build"


def environment(workspace, public):
    stage_workspace(SITE, workspace)
    return {
        **os.environ,
        "ASTRO_TELEMETRY_DISABLED": "1",
        "FLYOVER_SITE_CACHE": str(workspace / "cache"),
        "FLYOVER_SITE_PUBLIC": str(public),
    }


def build_shell(output):
    """Build before capture, then copy only the completed presentation into staging."""
    BUILD_ROOT.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="build-", dir=BUILD_ROOT) as temporary:
        workspace = Path(temporary)
        public = workspace / "public"
        public.mkdir()
        target = workspace / "site"
        result = subprocess.run(
            astro_command(SITE, workspace, "build", "--outDir", str(target)),
            cwd=SITE,
            env=environment(workspace, public),
            capture_output=True,
            text=True,
        )
        if result.returncode:
            raise ValueError(
                f"Astro build failed (exit {result.returncode}):\n{result.stdout}{result.stderr}"
            )
        actual = {
            str(path.relative_to(target))
            for path in target.rglob("*")
            if path.is_file()
        }
        if "index.html" not in actual or any(
            path != "index.html" and not path.startswith("assets/") for path in actual
        ):
            raise ValueError(f"Unexpected Astro assets: {sorted(actual)}")
        for relative in actual:
            destination = output / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(target / relative, destination)
        (output / "web-assets.json").write_text(
            json.dumps(sorted(actual - {"index.html"}))
        )


def copy_artifact(artifact, output, *, captures_only):
    """Copy the validated allowlist through no-follow descriptors into a private server root."""
    with open_artifact_root(artifact) as descriptor:
        for relative in sorted(artifact.allowed_paths):
            if (
                captures_only
                and relative != "manifest.json"
                and not relative.startswith("images/")
            ):
                continue
            destination = output / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            with (
                open_file_beneath(descriptor, relative) as source,
                destination.open("xb") as target,
            ):
                shutil.copyfileobj(source, target)


def serve(mode, directory, port, lan):
    # Validate before allocating a workspace or starting Node. Never serve the source checkout.
    artifact = validate_artifact(directory)
    BUILD_ROOT.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f"{mode}-", dir=BUILD_ROOT) as temporary:
        workspace = Path(temporary)
        public = workspace / "public"
        public.mkdir()
        output = workspace / "site"
        copy_artifact(
            artifact, public if mode == "dev" else output, captures_only=mode == "dev"
        )
        env = environment(workspace, public)
        arguments = [
            mode,
            "--ignore-lock",
            "--port",
            str(port),
            "--outDir",
            str(output),
        ]
        if lan:
            arguments += ["--host", "0.0.0.0"]
            print(
                "Warning: LAN preview has no authentication or TLS. Use a trusted network.",
                flush=True,
            )
        else:
            arguments += ["--host", "127.0.0.1"]
        print(f"Flyover {mode}: {directory}", flush=True)
        process = subprocess.Popen(
            astro_command(SITE, workspace, *arguments),
            cwd=SITE,
            env=env,
            start_new_session=True,
        )
        interrupted = None

        def interrupt(number, _frame):
            nonlocal interrupted
            interrupted = number
            raise KeyboardInterrupt

        previous = {
            number: signal.signal(number, interrupt)
            for number in (signal.SIGINT, signal.SIGTERM)
        }
        try:
            status = process.wait()
            return status if status >= 0 else 128 - status
        except KeyboardInterrupt:
            return 128 + (interrupted or signal.SIGINT)
        finally:
            for number, handler in previous.items():
                signal.signal(number, handler)
            if process.poll() is None:
                # The child can exit between poll and killpg.
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    process.wait()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        process.wait()
                    process.wait()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("build", "dev", "preview"))
    parser.add_argument("directory", type=Path)
    parser.add_argument("--port", type=int, default=4321)
    parser.add_argument("--lan", action="store_true")
    args = parser.parse_args(argv)
    if not 0 <= args.port <= 65535:
        parser.error("--port must be between 0 and 65535")
    try:
        if args.mode == "build":
            build_shell(args.directory)
            return 0
        return serve(args.mode, args.directory, args.port, args.lan)
    except KeyboardInterrupt:
        return 130
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
