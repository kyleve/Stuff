"""Schema and filesystem validation for generated Flyover atlases."""

from __future__ import annotations

import json
import os
import stat
from dataclasses import dataclass
from pathlib import Path, PurePosixPath


from Tools.flyover_schema import validate_manifest
from Tools.flyover_schema_values import FlyoverArtifactError, safe_image_path


MARKER_CONTENT = "schemaVersion=1"
REQUIRED_FILES = (
    "index.html",
    "manifest.json",
    "web-assets.json",
)


@dataclass(frozen=True)
class FlyoverArtifact:
    root: Path
    allowed_paths: frozenset[str]
    root_device: int
    root_inode: int


def validate_artifact(
    directory: Path,
    *,
    require_marker: bool = True,
) -> FlyoverArtifact:
    """Validate a generated atlas and return its HTTP allowlist."""
    root = directory
    try:
        root_status = os.lstat(root)
    except FileNotFoundError:
        raise FlyoverArtifactError(
            f"no generated atlas exists at {root}. Run ./flyover export first."
        ) from None
    except OSError as error:
        raise FlyoverArtifactError(f"could not inspect the atlas path {root}: {error}") from error
    if stat.S_ISLNK(root_status.st_mode):
        raise FlyoverArtifactError(f"the atlas directory is a symbolic link: {root}")
    if not stat.S_ISDIR(root_status.st_mode):
        raise FlyoverArtifactError(f"the atlas path is not a directory: {root}")

    symbolic_link = next((path for path in root.rglob("*") if path.is_symlink()), None)
    if symbolic_link is not None:
        relative = symbolic_link.relative_to(root)
        raise FlyoverArtifactError(f"the atlas contains a symbolic link: {relative}")

    marker = root / ".flyover-generated"
    if require_marker:
        if not marker.is_file():
            raise FlyoverArtifactError(
                f"the directory is not a generated Flyover atlas: {root}"
            )
        try:
            marker_content = marker.read_text(encoding="utf-8").strip()
        except (OSError, UnicodeError) as error:
            raise FlyoverArtifactError(f"could not read {marker}: {error}") from error
        if marker_content != MARKER_CONTENT:
            raise FlyoverArtifactError(
                f"the generated marker is unsupported: {marker_content or 'empty'}"
            )

    for relative in REQUIRED_FILES:
        path = root / relative
        if not path.is_file():
            raise FlyoverArtifactError(f"the generated atlas is missing {relative}")

    manifest_path = root / "manifest.json"
    try:
        manifest_data = manifest_path.read_bytes()
        manifest = json.loads(manifest_data)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise FlyoverArtifactError(f"could not read manifest.json: {error}") from error
    validate_manifest(manifest)

    web_assets_path = root / "web-assets.json"
    try:
        web_assets = json.loads(web_assets_path.read_bytes())
    except (OSError, ValueError) as error:
        raise FlyoverArtifactError(f"could not read web-assets.json: {error}") from error
    if not isinstance(web_assets, list) or not web_assets:
        raise FlyoverArtifactError("web-assets.json must contain the built asset paths")
    for relative in web_assets:
        if (not isinstance(relative, str) or not relative.startswith("assets/")
                or any(part in ("", ".", "..") for part in relative.split("/"))
                or "\\" in relative or "%" in relative or "?" in relative or "#" in relative
                or PurePosixPath(relative).suffix not in (".js", ".css")
                or not (root / relative).is_file()):
            raise FlyoverArtifactError(f"invalid or missing web asset: {relative}")
    if len(set(web_assets)) != len(web_assets):
        raise FlyoverArtifactError("duplicate web asset")
    actual_web_assets = {path.relative_to(root).as_posix() for path in (root / "assets").rglob("*") if path.is_file()}
    if set(web_assets) != actual_web_assets:
        raise FlyoverArtifactError("web asset files do not match web-assets.json")

    images = manifest.get("images")
    if not isinstance(images, list):
        raise FlyoverArtifactError("manifest.json has no image list")

    asset_paths: list[str] = []
    for image in images:
        if not isinstance(image, dict):
            raise FlyoverArtifactError("manifest.json contains an invalid image record")
        relative_value = image.get("relativePath")
        if not isinstance(relative_value, str):
            raise FlyoverArtifactError("manifest.json contains an invalid image path")
        relative = safe_image_path(relative_value)
        path = root.joinpath(*relative.parts)
        if not path.is_file():
            raise FlyoverArtifactError(f"the manifest image is missing: {relative}")
        asset_paths.append(relative.as_posix())

        if "thumbnailRelativePath" in image:
            thumbnail_value = image["thumbnailRelativePath"]
            assert isinstance(thumbnail_value, str)
            thumbnail = safe_image_path(thumbnail_value)
            thumbnail_path = root.joinpath(*thumbnail.parts)
            if not thumbnail_path.is_file():
                raise FlyoverArtifactError(
                    f"the manifest thumbnail is missing: {thumbnail}"
                )
            asset_paths.append(thumbnail.as_posix())

    if len(set(asset_paths)) != len(asset_paths):
        raise FlyoverArtifactError("manifest.json contains a duplicate image or thumbnail path")

    images_directory = root / "images"
    if images_directory.is_dir():
        actual_paths = {
            path.relative_to(root).as_posix()
            for path in images_directory.rglob("*.png")
            if path.is_file()
        }
    else:
        actual_paths = set()
    declared_paths = set(asset_paths)
    if actual_paths != declared_paths:
        raise FlyoverArtifactError(
            "the image files do not match the manifest "
            f"({len(declared_paths)} declared, {len(actual_paths)} found)"
        )

    return FlyoverArtifact(
        root=root,
        allowed_paths=frozenset((*REQUIRED_FILES, *web_assets, *asset_paths)),
        root_device=root_status.st_dev,
        root_inode=root_status.st_ino,
    )
