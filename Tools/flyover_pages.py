"""Compose the latest complete Flyover bundle into the shared Pages deployment."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from Tools.flyover_apps import load_apps
from Tools.flyover_bundle import MAX_BYTES, unpack_bundle
from Tools.flyover_manifest import validate_artifact


def version_images(root: Path) -> None:
    """Give published captures immutable URLs across daily deployments."""
    manifest_path = root / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    replacements = {}
    image_records = [
        record
        for image in manifest["images"]
        for record in [image, *image.get("thumbnailVariants", [])]
    ]
    for image in image_records:
        for field in ("relativePath", "thumbnailRelativePath"):
            if field not in image:
                continue
            relative = image[field]
            source = root / relative
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
            destination = source.with_name(f"{source.stem}-{digest}{source.suffix}")
            source.rename(destination)
            replacements[relative] = destination.relative_to(root).as_posix()
            image[field] = replacements[relative]
    for screen in manifest["screens"]:
        for variant in screen["variants"]:
            variant["imagesByProfile"] = {
                profile: replacements[path]
                for profile, path in variant["imagesByProfile"].items()
            }
    manifest_path.write_text(json.dumps(manifest))
    validate_artifact(root)


def latest_release(releases: list[dict]) -> dict | None:
    candidates = []
    for release in releases:
        match = re.fullmatch(
            r"flyover-atlas-([1-9][0-9]*)-([1-9][0-9]*)", release.get("tag_name", "")
        )
        if match and not release.get("draft", True):
            candidates.append((int(match[1]), int(match[2]), release))
    return max(candidates, key=lambda item: item[:2])[2] if candidates else None


def compose(output: Path, repository: str) -> str | None:
    if not (output / "index.html").is_file() or (output / "flyover").exists():
        raise ValueError("Flyover requires a fresh, complete install-site output")
    pages = json.loads(
        subprocess.check_output(
            ["gh", "api", f"repos/{repository}/releases", "--paginate", "--slurp"],
            text=True,
        )
    )
    release = latest_release([release for page in pages for release in page])
    destination = output / "flyover"
    with tempfile.TemporaryDirectory(prefix="flyover-pages-") as temporary:
        root = Path(temporary)
        extracted = root / "extracted"
        extracted.mkdir()
        published_apps = []
        if release is not None:
            assets = [
                asset for asset in release["assets"] if asset["name"] == "atlases.zip"
            ]
            if (
                len(assets) != 1
                or not 0 < assets[0]["size"] <= MAX_BYTES
                or not re.fullmatch(r"sha256:[0-9a-f]{64}", assets[0].get("digest", ""))
            ):
                raise ValueError(
                    "The Flyover release needs one bounded, digest-verified atlas bundle"
                )
            subprocess.run(
                [
                    "gh",
                    "release",
                    "download",
                    release["tag_name"],
                    "--repo",
                    repository,
                    "--pattern",
                    "atlases.zip",
                    "--dir",
                    str(root),
                ],
                check=True,
            )
            archive = root / "atlases.zip"
            if archive.stat().st_size != assets[0]["size"]:
                raise ValueError("Flyover release size mismatch")
            with archive.open("rb") as stream:
                digest = hashlib.sha256()
                while chunk := stream.read(1024 * 1024):
                    digest.update(chunk)
            if "sha256:" + digest.hexdigest() != assets[0]["digest"]:
                raise ValueError("Flyover release digest mismatch")
            receipt = unpack_bundle(archive, extracted, release["target_commitish"])
            published_apps = receipt["apps"]
        registered = {app.app_id for app in load_apps()}
        destination.mkdir()
        links = []
        for app in published_apps:
            if app["id"] in registered:
                shutil.copytree(extracted / app["id"], destination / app["id"])
                version_images(destination / app["id"])
                links.append(
                    f'<li><a href="./{app["id"]}/">{html.escape(app["title"])}</a></li>'
                )
        content = (
            "<ul>" + "".join(links) + "</ul>"
            if links
            else "<p>No published atlases yet.</p>"
        )
        (destination / "index.html").write_text(
            '<!doctype html><html lang="en"><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width, initial-scale=1">'
            "<title>Flyover QA atlases</title><main><h1>Flyover QA atlases</h1>"
            + content
            + '<p><a href="../">App downloads</a></p></main></html>'
        )
        if (
            sum(path.stat().st_size for path in output.rglob("*") if path.is_file())
            > 1_000_000_000
        ):
            raise ValueError("Combined Pages site exceeds the 1 GB publication budget")
    return release["tag_name"] if release is not None else None


def main(arguments=None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(arguments)
    tag = compose(args.output, os.environ["GITHUB_REPOSITORY"])
    if tag is not None and "GITHUB_OUTPUT" in os.environ:
        with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
            stream.write(f"release={tag}\n")


if __name__ == "__main__":
    main()
