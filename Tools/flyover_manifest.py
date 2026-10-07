"""Schema and filesystem validation for generated Flyover atlases."""

from __future__ import annotations

import json
import math
import os
import stat
from dataclasses import dataclass
from pathlib import Path, PurePosixPath


MARKER_CONTENT = "schemaVersion=1"
REQUIRED_FILES = (
    "index.html",
    "manifest.json",
    "manifest.js",
    "assets/app.js",
    "assets/styles.css",
)


class FlyoverArtifactError(ValueError):
    """A generated atlas is incomplete or unsafe to serve."""


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
    if not isinstance(manifest, dict):
        raise FlyoverArtifactError("manifest.json is not a JSON object")
    if (
        type(manifest.get("schemaVersion")) is not int
        or manifest["schemaVersion"] != 1
    ):
        raise FlyoverArtifactError("manifest.json does not use schemaVersion 1")
    _validate_manifest(manifest)

    manifest_script_path = root / "manifest.js"
    try:
        manifest_script = manifest_script_path.read_bytes()
    except OSError as error:
        raise FlyoverArtifactError(f"could not read manifest.js: {error}") from error
    expected_script = b"window.FLYOVER_MANIFEST = " + manifest_data + b";\n"
    if manifest_script != expected_script:
        raise FlyoverArtifactError("manifest.js does not match manifest.json")

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
        relative = _safe_image_path(relative_value)
        path = root.joinpath(*relative.parts)
        if not path.is_file():
            raise FlyoverArtifactError(f"the manifest image is missing: {relative}")
        asset_paths.append(relative.as_posix())

        if "thumbnailRelativePath" in image:
            thumbnail_value = image["thumbnailRelativePath"]
            assert isinstance(thumbnail_value, str)
            thumbnail = _safe_image_path(thumbnail_value)
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
        allowed_paths=frozenset((*REQUIRED_FILES, *asset_paths)),
        root_device=root_status.st_dev,
        root_inode=root_status.st_ino,
    )


def _validate_manifest(manifest: dict[str, object]) -> None:
    """Validate all schema-1 data that the browser reads."""
    application = _required_object(
        manifest.get("application"),
        "manifest.application",
        ("id", "title"),
    )
    _string(application["id"], "manifest.application.id", nonempty=True)
    _string(application["title"], "manifest.application.title", nonempty=True)

    build = _required_object(
        manifest.get("build"),
        "manifest.build",
        (
            "commit",
            "dirty",
            "generatedAt",
            "xcodeVersion",
            "simulatorDevice",
            "simulatorOS",
        ),
    )
    for field in (
        "commit",
        "generatedAt",
        "xcodeVersion",
        "simulatorDevice",
        "simulatorOS",
    ):
        _string(build[field], f"manifest.build.{field}", nonempty=True)
    if type(build["dirty"]) is not bool:
        raise FlyoverArtifactError("manifest.build.dirty is not a Boolean")
    branch = build.get("branch")
    if branch is not None:
        _string(branch, "manifest.build.branch")

    profiles = _required_list(manifest.get("profiles"), "manifest.profiles", nonempty=True)
    profile_by_id = _identified_records(
        profiles,
        "manifest.profiles",
        (
            "id",
            "title",
            "device",
            "orientation",
            "colorScheme",
            "dynamicType",
            "contrast",
            "layoutDirection",
            "legibilityWeight",
            "snapshotType",
        ),
    )
    profile_values = {
        "device": {"phone", "tablet"},
        "orientation": {"portrait", "landscape"},
        "colorScheme": {"light", "dark"},
        "dynamicType": {"small", "large", "xxxl", "accessibility3"},
        "contrast": {"standard", "increased"},
        "layoutDirection": {"left-to-right", "right-to-left"},
        "legibilityWeight": {"regular", "bold"},
        "snapshotType": {"standard", "accessibility"},
    }
    for index, profile in enumerate(profiles):
        assert isinstance(profile, dict)
        _string(profile["title"], f"manifest.profiles[{index}].title", nonempty=True)
        for field, accepted in profile_values.items():
            value = _string(profile[field], f"manifest.profiles[{index}].{field}")
            if value not in accepted:
                raise FlyoverArtifactError(
                    f"manifest.profiles[{index}].{field} has an unsupported value: {value}"
                )

    groups = _required_list(manifest.get("groups"), "manifest.groups", nonempty=True)
    group_by_id = _identified_records(
        groups,
        "manifest.groups",
        ("id", "title", "order", "rootScreenID", "screenIDs"),
    )
    for index, group in enumerate(groups):
        assert isinstance(group, dict)
        _string(group["title"], f"manifest.groups[{index}].title", nonempty=True)
        if _integer(group["order"], f"manifest.groups[{index}].order") != index:
            raise FlyoverArtifactError("manifest.groups are not in stable order")
        _string(
            group["rootScreenID"],
            f"manifest.groups[{index}].rootScreenID",
            nonempty=True,
        )
        screen_ids = _string_list(
            group["screenIDs"],
            f"manifest.groups[{index}].screenIDs",
            nonempty=True,
        )
        if len(set(screen_ids)) != len(screen_ids):
            raise FlyoverArtifactError(
                f"manifest.groups[{index}].screenIDs contains a duplicate identifier"
            )

    screens = _required_list(manifest.get("screens"), "manifest.screens", nonempty=True)
    screen_by_id = _identified_records(
        screens,
        "manifest.screens",
        (
            "id",
            "title",
            "groupID",
            "groupOrder",
            "screenOrder",
            "viewport",
            "navigationContainer",
            "frame",
            "variants",
            "incomingRouteIDs",
            "outgoingRouteIDs",
        ),
    )
    variant_by_key: dict[tuple[str, str], dict[str, object]] = {}
    expected_screen_ids: list[str] = []
    for group_index, group in enumerate(groups):
        assert isinstance(group, dict)
        group_id = str(group["id"])
        group_screen_ids = _string_list(
            group["screenIDs"],
            f"manifest.groups[{group_index}].screenIDs",
            nonempty=True,
        )
        root_screen_id = str(group["rootScreenID"])
        if root_screen_id not in group_screen_ids:
            raise FlyoverArtifactError(
                f"manifest.groups[{group_index}].rootScreenID is not in its screenIDs"
            )
        expected_screen_ids.extend(group_screen_ids)
        for screen_index, screen_id in enumerate(group_screen_ids):
            screen = screen_by_id.get(screen_id)
            if screen is None:
                raise FlyoverArtifactError(
                    f"manifest.groups[{group_index}].screenIDs references an unknown screen: "
                    f"{screen_id}"
                )
            if screen["groupID"] != group_id:
                raise FlyoverArtifactError(
                    f"manifest.screens[{screen_id}].groupID does not match its group"
                )
            if screen["groupOrder"] != group_index or screen["screenOrder"] != screen_index:
                raise FlyoverArtifactError(
                    f"manifest.screens[{screen_id}] has inconsistent ordering"
                )
    if len(set(expected_screen_ids)) != len(expected_screen_ids):
        raise FlyoverArtifactError("manifest group screen lists contain a duplicate screen")
    if expected_screen_ids != list(screen_by_id):
        raise FlyoverArtifactError("manifest group screen lists do not match manifest.screens")

    for index, screen in enumerate(screens):
        assert isinstance(screen, dict)
        screen_id = str(screen["id"])
        _string(screen["title"], f"manifest.screens[{index}].title", nonempty=True)
        group_id = _string(
            screen["groupID"],
            f"manifest.screens[{index}].groupID",
            nonempty=True,
        )
        if group_id not in group_by_id:
            raise FlyoverArtifactError(
                f"manifest.screens[{index}].groupID references an unknown group: {group_id}"
            )
        _integer(screen["groupOrder"], f"manifest.screens[{index}].groupOrder")
        _integer(screen["screenOrder"], f"manifest.screens[{index}].screenOrder")
        _validate_viewport(screen["viewport"], f"manifest.screens[{index}].viewport")
        navigation = _string(
            screen["navigationContainer"],
            f"manifest.screens[{index}].navigationContainer",
        )
        if navigation not in {"stack", "none"}:
            raise FlyoverArtifactError(
                f"manifest.screens[{index}].navigationContainer has an unsupported value: "
                f"{navigation}"
            )
        _validate_rect(screen["frame"], f"manifest.screens[{index}].frame")
        _string_list(
            screen["incomingRouteIDs"],
            f"manifest.screens[{index}].incomingRouteIDs",
        )
        _string_list(
            screen["outgoingRouteIDs"],
            f"manifest.screens[{index}].outgoingRouteIDs",
        )

        variants = _required_list(
            screen["variants"],
            f"manifest.screens[{index}].variants",
            nonempty=True,
        )
        local_ids: set[str] = set()
        for variant_index, value in enumerate(variants):
            variant = _required_object(
                value,
                f"manifest.screens[{index}].variants[{variant_index}]",
                ("id", "title", "captureExtent", "imagesByProfile"),
            )
            variant_id = _string(
                variant["id"],
                f"manifest.screens[{index}].variants[{variant_index}].id",
                nonempty=True,
            )
            if variant_id in local_ids:
                raise FlyoverArtifactError(
                    f"manifest.screens[{index}].variants contains a duplicate identifier: "
                    f"{variant_id}"
                )
            local_ids.add(variant_id)
            _string(
                variant["title"],
                f"manifest.screens[{index}].variants[{variant_index}].title",
                nonempty=True,
            )
            extent = _capture_extent(
                variant["captureExtent"],
                f"manifest.screens[{index}].variants[{variant_index}].captureExtent",
            )
            images_by_profile = _required_object(
                variant["imagesByProfile"],
                f"manifest.screens[{index}].variants[{variant_index}].imagesByProfile",
                tuple(profile_by_id),
            )
            if set(images_by_profile) != set(profile_by_id):
                raise FlyoverArtifactError(
                    f"manifest.screens[{index}].variants[{variant_index}].imagesByProfile "
                    "does not match manifest.profiles"
                )
            for profile_id, relative_path in images_by_profile.items():
                _safe_image_path(
                    _string(
                        relative_path,
                        f"manifest.screens[{index}].variants[{variant_index}]"
                        f".imagesByProfile[{profile_id}]",
                        nonempty=True,
                    )
                )
            variant_by_key[(screen_id, variant_id)] = variant

    routes = _required_list(manifest.get("routes"), "manifest.routes")
    route_by_id = _identified_records(
        routes,
        "manifest.routes",
        ("id", "sourceScreenID", "destinationScreenID", "kind", "geometry"),
    )
    for index, route in enumerate(routes):
        assert isinstance(route, dict)
        for field in ("sourceScreenID", "destinationScreenID"):
            screen_id = _string(
                route[field],
                f"manifest.routes[{index}].{field}",
                nonempty=True,
            )
            if screen_id not in screen_by_id:
                raise FlyoverArtifactError(
                    f"manifest.routes[{index}].{field} references an unknown screen: "
                    f"{screen_id}"
                )
        kind = _string(route["kind"], f"manifest.routes[{index}].kind")
        if kind not in {"push", "modal"}:
            raise FlyoverArtifactError(
                f"manifest.routes[{index}].kind has an unsupported value: {kind}"
            )
        label = route.get("label")
        if label is not None:
            _string(label, f"manifest.routes[{index}].label")
        _validate_geometry(route["geometry"], f"manifest.routes[{index}].geometry")

    for index, screen in enumerate(screens):
        assert isinstance(screen, dict)
        screen_id = str(screen["id"])
        expected_incoming = [
            str(route["id"])
            for route in routes
            if isinstance(route, dict) and route["destinationScreenID"] == screen_id
        ]
        expected_outgoing = [
            str(route["id"])
            for route in routes
            if isinstance(route, dict) and route["sourceScreenID"] == screen_id
        ]
        if screen["incomingRouteIDs"] != expected_incoming:
            raise FlyoverArtifactError(
                f"manifest.screens[{index}].incomingRouteIDs does not match manifest.routes"
            )
        if screen["outgoingRouteIDs"] != expected_outgoing:
            raise FlyoverArtifactError(
                f"manifest.screens[{index}].outgoingRouteIDs does not match manifest.routes"
            )

    _validate_canvas(manifest.get("canvas"), group_by_id, screen_by_id, route_by_id)
    _validate_images(manifest.get("images"), profile_by_id, screen_by_id, variant_by_key)


def _validate_canvas(
    value: object,
    group_by_id: dict[str, dict[str, object]],
    screen_by_id: dict[str, dict[str, object]],
    route_by_id: dict[str, dict[str, object]],
) -> None:
    canvas = _required_object(
        value,
        "manifest.canvas",
        (
            "size",
            "initialFitSize",
            "groupFrames",
            "depthBandFrames",
            "screenFrames",
            "connectors",
        ),
    )
    _validate_size(canvas["size"], "manifest.canvas.size")
    _validate_size(canvas["initialFitSize"], "manifest.canvas.initialFitSize")
    group_frames = _identified_records(
        _required_list(canvas["groupFrames"], "manifest.canvas.groupFrames"),
        "manifest.canvas.groupFrames",
        ("id", "frame"),
    )
    screen_frames = _identified_records(
        _required_list(canvas["screenFrames"], "manifest.canvas.screenFrames"),
        "manifest.canvas.screenFrames",
        ("id", "frame"),
    )
    if set(group_frames) != set(group_by_id):
        raise FlyoverArtifactError("manifest.canvas.groupFrames does not match manifest.groups")
    if set(screen_frames) != set(screen_by_id):
        raise FlyoverArtifactError("manifest.canvas.screenFrames does not match manifest.screens")
    for identifier, record in group_frames.items():
        _validate_rect(record["frame"], f"manifest.canvas.groupFrames[{identifier}].frame")
    for identifier, record in screen_frames.items():
        frame = _validate_rect(
            record["frame"],
            f"manifest.canvas.screenFrames[{identifier}].frame",
        )
        if frame != screen_by_id[identifier]["frame"]:
            raise FlyoverArtifactError(
                f"manifest.canvas.screenFrames[{identifier}] does not match its screen frame"
            )

    depth_bands = _required_list(
        canvas["depthBandFrames"],
        "manifest.canvas.depthBandFrames",
    )
    for index, value in enumerate(depth_bands):
        band = _required_object(
            value,
            f"manifest.canvas.depthBandFrames[{index}]",
            ("groupID", "kind", "frame"),
        )
        group_id = _string(
            band["groupID"],
            f"manifest.canvas.depthBandFrames[{index}].groupID",
            nonempty=True,
        )
        if group_id not in group_by_id:
            raise FlyoverArtifactError(
                f"manifest.canvas.depthBandFrames[{index}].groupID references an unknown group"
            )
        kind = _string(band["kind"], f"manifest.canvas.depthBandFrames[{index}].kind")
        depth = band.get("depth")
        if kind == "route":
            if _integer(depth, f"manifest.canvas.depthBandFrames[{index}].depth") < 0:
                raise FlyoverArtifactError(
                    f"manifest.canvas.depthBandFrames[{index}].depth is negative"
                )
        elif kind == "unlinked":
            if depth is not None:
                raise FlyoverArtifactError(
                    f"manifest.canvas.depthBandFrames[{index}].depth must be null"
                )
        else:
            raise FlyoverArtifactError(
                f"manifest.canvas.depthBandFrames[{index}].kind has an unsupported value: "
                f"{kind}"
            )
        _validate_rect(band["frame"], f"manifest.canvas.depthBandFrames[{index}].frame")

    connectors = _required_list(canvas["connectors"], "manifest.canvas.connectors")
    connector_by_route: dict[str, dict[str, object]] = {}
    for index, value in enumerate(connectors):
        connector = _required_object(
            value,
            f"manifest.canvas.connectors[{index}]",
            ("routeID", "geometry"),
        )
        route_id = _string(
            connector["routeID"],
            f"manifest.canvas.connectors[{index}].routeID",
            nonempty=True,
        )
        if route_id in connector_by_route:
            raise FlyoverArtifactError(
                f"manifest.canvas.connectors contains a duplicate routeID: {route_id}"
            )
        connector_by_route[route_id] = connector
        _validate_geometry(
            connector["geometry"],
            f"manifest.canvas.connectors[{index}].geometry",
        )
    if set(connector_by_route) != set(route_by_id):
        raise FlyoverArtifactError("manifest.canvas.connectors does not match manifest.routes")
    for route_id, connector in connector_by_route.items():
        if connector["geometry"] != route_by_id[route_id]["geometry"]:
            raise FlyoverArtifactError(
                f"manifest.canvas.connectors[{route_id}] does not match its route geometry"
            )


def _validate_images(
    value: object,
    profile_by_id: dict[str, dict[str, object]],
    screen_by_id: dict[str, dict[str, object]],
    variant_by_key: dict[tuple[str, str], dict[str, object]],
) -> None:
    images = _required_list(value, "manifest.images", nonempty=True)
    image_by_key: dict[tuple[str, str, str], dict[str, object]] = {}
    paths: set[str] = set()
    for index, value in enumerate(images):
        image = _required_object(
            value,
            f"manifest.images[{index}]",
            (
                "screenID",
                "variantID",
                "profileID",
                "relativePath",
                "pointWidth",
                "pointHeight",
                "pixelWidth",
                "pixelHeight",
                "scale",
                "captureExtent",
            ),
        )
        thumbnail_fields = (
            "thumbnailRelativePath",
            "thumbnailPixelWidth",
            "thumbnailPixelHeight",
        )
        present_thumbnail_fields = [field for field in thumbnail_fields if field in image]
        if present_thumbnail_fields and len(present_thumbnail_fields) != len(thumbnail_fields):
            raise FlyoverArtifactError(
                f"manifest.images[{index}] has incomplete thumbnail metadata"
            )
        screen_id = _string(image["screenID"], f"manifest.images[{index}].screenID", nonempty=True)
        variant_id = _string(
            image["variantID"],
            f"manifest.images[{index}].variantID",
            nonempty=True,
        )
        profile_id = _string(
            image["profileID"],
            f"manifest.images[{index}].profileID",
            nonempty=True,
        )
        if screen_id not in screen_by_id:
            raise FlyoverArtifactError(
                f"manifest.images[{index}].screenID references an unknown screen: {screen_id}"
            )
        variant = variant_by_key.get((screen_id, variant_id))
        if variant is None:
            raise FlyoverArtifactError(
                f"manifest.images[{index}].variantID references an unknown variant: {variant_id}"
            )
        if profile_id not in profile_by_id:
            raise FlyoverArtifactError(
                f"manifest.images[{index}].profileID references an unknown profile: {profile_id}"
            )
        key = (screen_id, variant_id, profile_id)
        if key in image_by_key:
            raise FlyoverArtifactError(
                "manifest.images contains a duplicate screen, variant, and profile record"
            )
        image_by_key[key] = image
        relative_path = _safe_image_path(
            _string(
                image["relativePath"],
                f"manifest.images[{index}].relativePath",
                nonempty=True,
            )
        ).as_posix()
        if relative_path in paths:
            raise FlyoverArtifactError("manifest.json contains a duplicate image path")
        paths.add(relative_path)
        if present_thumbnail_fields:
            thumbnail_path = _safe_image_path(
                _string(
                    image["thumbnailRelativePath"],
                    f"manifest.images[{index}].thumbnailRelativePath",
                    nonempty=True,
                )
            ).as_posix()
            if thumbnail_path in paths:
                raise FlyoverArtifactError(
                    "manifest.json contains a duplicate image or thumbnail path"
                )
            paths.add(thumbnail_path)
            for field in ("thumbnailPixelWidth", "thumbnailPixelHeight"):
                if _integer(image[field], f"manifest.images[{index}].{field}") <= 0:
                    raise FlyoverArtifactError(
                        f"manifest.images[{index}].{field} is not positive"
                    )
        expected_path = variant["imagesByProfile"][profile_id]
        if relative_path != expected_path:
            raise FlyoverArtifactError(
                f"manifest.images[{index}].relativePath does not match imagesByProfile"
            )
        extent = _capture_extent(
            image["captureExtent"],
            f"manifest.images[{index}].captureExtent",
        )
        if extent != variant["captureExtent"]:
            raise FlyoverArtifactError(
                f"manifest.images[{index}].captureExtent does not match its variant"
            )
        for field in ("pointWidth", "pointHeight", "scale"):
            if _number(image[field], f"manifest.images[{index}].{field}") <= 0:
                raise FlyoverArtifactError(f"manifest.images[{index}].{field} is not positive")
        for field in ("pixelWidth", "pixelHeight"):
            if _integer(image[field], f"manifest.images[{index}].{field}") <= 0:
                raise FlyoverArtifactError(f"manifest.images[{index}].{field} is not positive")

    expected_keys = {
        (screen_id, variant_id, profile_id)
        for screen_id, variant_id in variant_by_key
        for profile_id in profile_by_id
    }
    if set(image_by_key) != expected_keys:
        raise FlyoverArtifactError(
            "manifest.images does not contain exactly one image for each state and profile"
        )


def _required_object(
    value: object,
    path: str,
    fields: tuple[str, ...],
) -> dict[str, object]:
    if not isinstance(value, dict):
        raise FlyoverArtifactError(f"{path} is not an object")
    missing = next((field for field in fields if field not in value), None)
    if missing is not None:
        raise FlyoverArtifactError(f"{path} is missing {missing}")
    return value


def _required_list(value: object, path: str, *, nonempty: bool = False) -> list[object]:
    if not isinstance(value, list):
        raise FlyoverArtifactError(f"{path} is not an array")
    if nonempty and not value:
        raise FlyoverArtifactError(f"{path} is empty")
    return value


def _identified_records(
    values: list[object],
    path: str,
    fields: tuple[str, ...],
) -> dict[str, dict[str, object]]:
    records: dict[str, dict[str, object]] = {}
    for index, value in enumerate(values):
        record = _required_object(value, f"{path}[{index}]", fields)
        identifier = _string(record["id"], f"{path}[{index}].id", nonempty=True)
        if identifier in records:
            raise FlyoverArtifactError(f"{path} contains a duplicate identifier: {identifier}")
        records[identifier] = record
    return records


def _string(value: object, path: str, *, nonempty: bool = False) -> str:
    if not isinstance(value, str):
        raise FlyoverArtifactError(f"{path} is not a string")
    if nonempty and not value:
        raise FlyoverArtifactError(f"{path} is empty")
    return value


def _string_list(value: object, path: str, *, nonempty: bool = False) -> list[str]:
    values = _required_list(value, path, nonempty=nonempty)
    return [_string(item, f"{path}[{index}]", nonempty=True) for index, item in enumerate(values)]


def _integer(value: object, path: str) -> int:
    if type(value) is not int:
        raise FlyoverArtifactError(f"{path} is not an integer")
    return value


def _number(value: object, path: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise FlyoverArtifactError(f"{path} is not a number")
    result = float(value)
    if not math.isfinite(result):
        raise FlyoverArtifactError(f"{path} is not finite")
    return result


def _validate_size(value: object, path: str) -> dict[str, object]:
    size = _required_object(value, path, ("width", "height"))
    for field in ("width", "height"):
        if _number(size[field], f"{path}.{field}") <= 0:
            raise FlyoverArtifactError(f"{path}.{field} is not positive")
    return size


def _validate_rect(value: object, path: str) -> dict[str, object]:
    rect = _required_object(value, path, ("x", "y", "width", "height"))
    _number(rect["x"], f"{path}.x")
    _number(rect["y"], f"{path}.y")
    for field in ("width", "height"):
        if _number(rect[field], f"{path}.{field}") <= 0:
            raise FlyoverArtifactError(f"{path}.{field} is not positive")
    return rect


def _validate_point(value: object, path: str) -> None:
    point = _required_object(value, path, ("x", "y"))
    _number(point["x"], f"{path}.x")
    _number(point["y"], f"{path}.y")


def _validate_geometry(value: object, path: str) -> None:
    geometry = _required_object(
        value,
        path,
        (
            "start",
            "end",
            "firstControl",
            "secondControl",
            "firstArrowPoint",
            "secondArrowPoint",
        ),
    )
    for field in (
        "start",
        "end",
        "firstControl",
        "secondControl",
        "firstArrowPoint",
        "secondArrowPoint",
    ):
        _validate_point(geometry[field], f"{path}.{field}")


def _validate_viewport(value: object, path: str) -> None:
    viewport = _required_object(value, path, ("kind",))
    kind = _string(viewport["kind"], f"{path}.kind")
    fixed_size = viewport.get("fixedSize")
    if kind == "device":
        if fixed_size is not None:
            raise FlyoverArtifactError(f"{path}.fixedSize must be null for a device viewport")
    elif kind == "fixed":
        _validate_size(fixed_size, f"{path}.fixedSize")
    else:
        raise FlyoverArtifactError(f"{path}.kind has an unsupported value: {kind}")


def _capture_extent(value: object, path: str) -> str:
    extent = _string(value, path)
    if extent not in {"viewport", "intrinsic", "fullContent", "fullContent2D"}:
        raise FlyoverArtifactError(f"{path} has an unsupported value: {extent}")
    return extent


def _safe_image_path(value: str) -> PurePosixPath:
    relative = PurePosixPath(value)
    if (
        not value
        or "\\" in value
        or relative.is_absolute()
        or ".." in relative.parts
        or relative.parts[:1] != ("images",)
        or relative.suffix.lower() != ".png"
    ):
        raise FlyoverArtifactError(f"the manifest contains an unsafe image path: {value}")
    return relative
