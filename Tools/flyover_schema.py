"""Pure schema and catalog consistency validation, without filesystem access."""

from Tools.flyover_schema_values import (
    FlyoverArtifactError,
    required_object,
    required_list,
    identified_records,
    string,
    string_list,
    integer,
    validate_rect,
    validate_geometry,
    validate_viewport,
    capture_extent,
    safe_image_path,
)
from Tools.flyover_canvas import validate_canvas
from Tools.flyover_images import validate_images


def validate_manifest(manifest: object) -> None:
    """Validate all schema-1 data that the browser reads."""
    if not isinstance(manifest, dict):
        raise FlyoverArtifactError("manifest.json is not a JSON object")
    if type(manifest.get("schemaVersion")) is not int or manifest["schemaVersion"] != 1:
        raise FlyoverArtifactError("manifest.json does not use schemaVersion 1")
    validate_metadata(manifest)

    profiles = required_list(manifest.get("profiles"), "manifest.profiles", nonempty=True)
    profile_by_id = identified_records(
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
        string(profile["title"], f"manifest.profiles[{index}].title", nonempty=True)
        for field, accepted in profile_values.items():
            value = string(profile[field], f"manifest.profiles[{index}].{field}")
            if value not in accepted:
                raise FlyoverArtifactError(
                    f"manifest.profiles[{index}].{field} has an unsupported value: {value}"
                )

    groups = required_list(manifest.get("groups"), "manifest.groups", nonempty=True)
    group_by_id = identified_records(
        groups,
        "manifest.groups",
        ("id", "title", "order", "rootScreenID", "screenIDs"),
    )
    for index, group in enumerate(groups):
        assert isinstance(group, dict)
        string(group["title"], f"manifest.groups[{index}].title", nonempty=True)
        if integer(group["order"], f"manifest.groups[{index}].order") != index:
            raise FlyoverArtifactError("manifest.groups are not in stable order")
        string(
            group["rootScreenID"],
            f"manifest.groups[{index}].rootScreenID",
            nonempty=True,
        )
        screen_ids = string_list(
            group["screenIDs"],
            f"manifest.groups[{index}].screenIDs",
            nonempty=True,
        )
        if len(set(screen_ids)) != len(screen_ids):
            raise FlyoverArtifactError(
                f"manifest.groups[{index}].screenIDs contains a duplicate identifier"
            )

    screens = required_list(manifest.get("screens"), "manifest.screens", nonempty=True)
    screen_by_id = identified_records(
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
    validate_group_membership(groups, screen_by_id)

    for index, screen in enumerate(screens):
        assert isinstance(screen, dict)
        screen_id = str(screen["id"])
        string(screen["title"], f"manifest.screens[{index}].title", nonempty=True)
        group_id = string(
            screen["groupID"],
            f"manifest.screens[{index}].groupID",
            nonempty=True,
        )
        if group_id not in group_by_id:
            raise FlyoverArtifactError(
                f"manifest.screens[{index}].groupID references an unknown group: {group_id}"
            )
        integer(screen["groupOrder"], f"manifest.screens[{index}].groupOrder")
        integer(screen["screenOrder"], f"manifest.screens[{index}].screenOrder")
        validate_viewport(screen["viewport"], f"manifest.screens[{index}].viewport")
        navigation = string(
            screen["navigationContainer"],
            f"manifest.screens[{index}].navigationContainer",
        )
        if navigation not in {"stack", "none"}:
            raise FlyoverArtifactError(
                f"manifest.screens[{index}].navigationContainer has an unsupported value: "
                f"{navigation}"
            )
        validate_rect(screen["frame"], f"manifest.screens[{index}].frame")
        string_list(
            screen["incomingRouteIDs"],
            f"manifest.screens[{index}].incomingRouteIDs",
        )
        string_list(
            screen["outgoingRouteIDs"],
            f"manifest.screens[{index}].outgoingRouteIDs",
        )

        variants = required_list(
            screen["variants"],
            f"manifest.screens[{index}].variants",
            nonempty=True,
        )
        local_ids: set[str] = set()
        for variant_index, value in enumerate(variants):
            variant = required_object(
                value,
                f"manifest.screens[{index}].variants[{variant_index}]",
                ("id", "title", "captureExtent", "imagesByProfile"),
            )
            variant_id = string(
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
            string(
                variant["title"],
                f"manifest.screens[{index}].variants[{variant_index}].title",
                nonempty=True,
            )
            extent = capture_extent(
                variant["captureExtent"],
                f"manifest.screens[{index}].variants[{variant_index}].captureExtent",
            )
            images_by_profile = required_object(
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
                safe_image_path(
                    string(
                        relative_path,
                        f"manifest.screens[{index}].variants[{variant_index}]"
                        f".imagesByProfile[{profile_id}]",
                        nonempty=True,
                    )
                )
            variant_by_key[(screen_id, variant_id)] = variant

    routes = required_list(manifest.get("routes"), "manifest.routes")
    route_by_id = identified_records(
        routes,
        "manifest.routes",
        ("id", "sourceScreenID", "destinationScreenID", "kind", "geometry"),
    )
    for index, route in enumerate(routes):
        assert isinstance(route, dict)
        for field in ("sourceScreenID", "destinationScreenID"):
            screen_id = string(
                route[field],
                f"manifest.routes[{index}].{field}",
                nonempty=True,
            )
            if screen_id not in screen_by_id:
                raise FlyoverArtifactError(
                    f"manifest.routes[{index}].{field} references an unknown screen: "
                    f"{screen_id}"
                )
        kind = string(route["kind"], f"manifest.routes[{index}].kind")
        if kind not in {"push", "modal"}:
            raise FlyoverArtifactError(
                f"manifest.routes[{index}].kind has an unsupported value: {kind}"
            )
        label = route.get("label")
        if label is not None:
            string(label, f"manifest.routes[{index}].label")
        validate_geometry(route["geometry"], f"manifest.routes[{index}].geometry")

    validate_route_membership(screens, routes)

    validate_canvas(manifest.get("canvas"), group_by_id, screen_by_id, route_by_id)
    validate_images(manifest.get("images"), profile_by_id, screen_by_id, variant_by_key)




def validate_metadata(manifest: dict[str, object]) -> None:
    application = required_object(
        manifest.get("application"),
        "manifest.application",
        ("id", "title"),
    )
    string(application["id"], "manifest.application.id", nonempty=True)
    string(application["title"], "manifest.application.title", nonempty=True)

    build = required_object(
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
        string(build[field], f"manifest.build.{field}", nonempty=True)
    if type(build["dirty"]) is not bool:
        raise FlyoverArtifactError("manifest.build.dirty is not a Boolean")
    branch = build.get("branch")
    if branch is not None:
        string(branch, "manifest.build.branch")


def validate_group_membership(
    groups: list[object], screen_by_id: dict[str, dict[str, object]],
) -> None:
    expected_screen_ids: list[str] = []
    for group_index, group in enumerate(groups):
        assert isinstance(group, dict)
        group_id = str(group["id"])
        group_screen_ids = string_list(
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


def validate_route_membership(screens: list[object], routes: list[object]) -> None:
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
