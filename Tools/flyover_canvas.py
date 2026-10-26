"""Canvas geometry and catalog-reference validation."""

from Tools.flyover_schema_values import (
    FlyoverArtifactError,
    required_object,
    required_list,
    identified_records,
    string,
    integer,
    validate_size,
    validate_rect,
    validate_geometry,
)


def validate_canvas(
    value: object,
    group_by_id: dict[str, dict[str, object]],
    screen_by_id: dict[str, dict[str, object]],
    route_by_id: dict[str, dict[str, object]],
) -> None:
    canvas = required_object(
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
    validate_size(canvas["size"], "manifest.canvas.size")
    validate_size(canvas["initialFitSize"], "manifest.canvas.initialFitSize")
    group_frames = identified_records(
        required_list(canvas["groupFrames"], "manifest.canvas.groupFrames"),
        "manifest.canvas.groupFrames",
        ("id", "frame"),
    )
    screen_frames = identified_records(
        required_list(canvas["screenFrames"], "manifest.canvas.screenFrames"),
        "manifest.canvas.screenFrames",
        ("id", "frame"),
    )
    if set(group_frames) != set(group_by_id):
        raise FlyoverArtifactError("manifest.canvas.groupFrames does not match manifest.groups")
    if set(screen_frames) != set(screen_by_id):
        raise FlyoverArtifactError("manifest.canvas.screenFrames does not match manifest.screens")
    for identifier, record in group_frames.items():
        validate_rect(record["frame"], f"manifest.canvas.groupFrames[{identifier}].frame")
    for identifier, record in screen_frames.items():
        frame = validate_rect(
            record["frame"],
            f"manifest.canvas.screenFrames[{identifier}].frame",
        )
        if frame != screen_by_id[identifier]["frame"]:
            raise FlyoverArtifactError(
                f"manifest.canvas.screenFrames[{identifier}] does not match its screen frame"
            )

    depth_bands = required_list(
        canvas["depthBandFrames"],
        "manifest.canvas.depthBandFrames",
    )
    for index, value in enumerate(depth_bands):
        band = required_object(
            value,
            f"manifest.canvas.depthBandFrames[{index}]",
            ("groupID", "kind", "frame"),
        )
        group_id = string(
            band["groupID"],
            f"manifest.canvas.depthBandFrames[{index}].groupID",
            nonempty=True,
        )
        if group_id not in group_by_id:
            raise FlyoverArtifactError(
                f"manifest.canvas.depthBandFrames[{index}].groupID references an unknown group"
            )
        kind = string(band["kind"], f"manifest.canvas.depthBandFrames[{index}].kind")
        depth = band.get("depth")
        if kind == "route":
            if integer(depth, f"manifest.canvas.depthBandFrames[{index}].depth") < 0:
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
        validate_rect(band["frame"], f"manifest.canvas.depthBandFrames[{index}].frame")

    connectors = required_list(canvas["connectors"], "manifest.canvas.connectors")
    connector_by_route: dict[str, dict[str, object]] = {}
    for index, value in enumerate(connectors):
        connector = required_object(
            value,
            f"manifest.canvas.connectors[{index}]",
            ("routeID", "geometry"),
        )
        route_id = string(
            connector["routeID"],
            f"manifest.canvas.connectors[{index}].routeID",
            nonempty=True,
        )
        if route_id in connector_by_route:
            raise FlyoverArtifactError(
                f"manifest.canvas.connectors contains a duplicate routeID: {route_id}"
            )
        connector_by_route[route_id] = connector
        validate_geometry(
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
