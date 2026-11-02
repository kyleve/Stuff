"""Compose build metadata, hosted capture, validation, and atlas publication."""

from dataclasses import dataclass
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import time

from Tools.flyover_manifest import validate_artifact
from Tools.flyover_apps import load_app
from Tools.flyover_publication import AtlasPublication, validate_destination


@dataclass(frozen=True)
class ExportRequest:
    destination: Path
    profiles: tuple[str, ...]
    app_id: str = "where"


def run_capture_process(arguments: list[str], *, environment=None) -> None:
    """Reap the capture runner before publication or recovery can proceed."""
    subprocess.run(arguments, check=True, env=environment)


def build_environment(workspace: Path, destination: Path) -> dict[str, str]:
    """Read Git before staging so generated output does not mark a clean tree dirty."""

    def git(*arguments, fallback=None):
        result = subprocess.run(
            ["git", "-C", str(workspace), *arguments],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        if result.returncode:
            if fallback is not None:
                return fallback
            raise ValueError("could not read the Git working-tree status")
        return result.stdout.rstrip("\n")

    status_arguments = ["status", "--porcelain", "--untracked-files=all", "--", "."]
    if destination.exists():
        try:
            relative = destination.relative_to(workspace)
        except ValueError:
            relative = None
        if relative is not None:
            status_arguments.append(":(exclude,top,literal)" + relative.as_posix())
    dirty = bool(git(*status_arguments))
    xcode = os.environ.get("FLYOVER_XCODE_VERSION_OVERRIDE")
    if not xcode:
        try:
            result = subprocess.run(
                ["xcodebuild", "-version"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
            )
            xcode = (
                result.stdout.strip().replace("\n", " ")
                if result.returncode == 0
                else ""
            )
        except FileNotFoundError:
            xcode = ""
    return {
        "FLYOVER_EXPORT_COMMIT": git("rev-parse", "HEAD", fallback="unknown"),
        "FLYOVER_EXPORT_DIRTY": str(dirty).lower(),
        "FLYOVER_EXPORT_BRANCH": git("branch", "--show-current", fallback=""),
        "FLYOVER_EXPORT_GENERATED_AT": datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "FLYOVER_EXPORT_XCODE_VERSION": xcode or "unknown",
        "FLYOVER_EXPORT_SIMULATOR_DEVICE": "iPhone 17",
        "FLYOVER_EXPORT_SIMULATOR_OS": "27.2",
    }


def export_atlas(request: ExportRequest, workspace: Path) -> None:
    app = load_app(request.app_id)
    validate_destination(request.destination)
    metadata = build_environment(workspace, request.destination)
    started = time.monotonic()
    with AtlasPublication(request.destination) as publication:
        staging = publication.staging
        builder = os.environ.get("FLYOVER_WEB_BUILD_RUNNER")
        if builder:
            run_capture_process([builder, str(staging)])
        else:
            from Tools.flyover_site import build_shell

            build_shell(staging)
        print(
            f"==> Exporting {len(request.profiles)} profile(s) to {request.destination}",
            flush=True,
        )
        run_capture_process(
            [
                os.environ.get("FLYOVER_CAPTURE_RUNNER", str(workspace / "test")),
                "--only",
                app.test_identifier,
            ],
            environment={
                **os.environ,
                **metadata,
                "FLYOVER_EXPORT_DIRECTORY": str(staging),
                "FLYOVER_EXPORT_PROFILES": ",".join(request.profiles),
            },
        )
        validate_artifact(staging, require_marker=False)
        if (
            json.loads((staging / "manifest.json").read_text())["application"]["id"]
            != app.app_id
        ):
            raise ValueError("Captured application does not match the selected app")
        publication.publish()
    print_summary(request.destination, int(time.monotonic() - started))


def print_summary(destination: Path, elapsed: int) -> None:
    manifest = json.loads((destination / "manifest.json").read_text())
    size = sum(path.stat().st_size for path in destination.rglob("*") if path.is_file())
    print(
        f"Flyover export complete: {len(manifest['screens'])} screens, "
        f"{sum(len(screen['variants']) for screen in manifest['screens'])} states, "
        f"{len(manifest['profiles'])} profiles, {len(manifest['images'])} images, "
        f"{size} bytes in {elapsed}s"
    )
    print(destination)
