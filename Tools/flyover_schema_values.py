"""Primitive schema checks shared by Flyover validators."""

import math
from pathlib import PurePosixPath


class FlyoverArtifactError(ValueError):
    """A generated atlas is incomplete or unsafe to serve."""


def required_object(
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


def required_list(value: object, path: str, *, nonempty: bool = False) -> list[object]:
    if not isinstance(value, list):
        raise FlyoverArtifactError(f"{path} is not an array")
    if nonempty and not value:
        raise FlyoverArtifactError(f"{path} is empty")
    return value


def identified_records(
    values: list[object],
    path: str,
    fields: tuple[str, ...],
) -> dict[str, dict[str, object]]:
    records: dict[str, dict[str, object]] = {}
    for index, value in enumerate(values):
        record = required_object(value, f"{path}[{index}]", fields)
        identifier = string(record["id"], f"{path}[{index}].id", nonempty=True)
        if identifier in records:
            raise FlyoverArtifactError(
                f"{path} contains a duplicate identifier: {identifier}"
            )
        records[identifier] = record
    return records


def string(value: object, path: str, *, nonempty: bool = False) -> str:
    if not isinstance(value, str):
        raise FlyoverArtifactError(f"{path} is not a string")
    if nonempty and not value:
        raise FlyoverArtifactError(f"{path} is empty")
    return value


def string_list(value: object, path: str, *, nonempty: bool = False) -> list[str]:
    values = required_list(value, path, nonempty=nonempty)
    return [
        string(item, f"{path}[{index}]", nonempty=True)
        for index, item in enumerate(values)
    ]


def integer(value: object, path: str) -> int:
    if type(value) is not int:
        raise FlyoverArtifactError(f"{path} is not an integer")
    return value


def number(value: object, path: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise FlyoverArtifactError(f"{path} is not a number")
    result = float(value)
    if not math.isfinite(result):
        raise FlyoverArtifactError(f"{path} is not finite")
    return result


def validate_size(value: object, path: str) -> dict[str, object]:
    size = required_object(value, path, ("width", "height"))
    for field in ("width", "height"):
        if number(size[field], f"{path}.{field}") <= 0:
            raise FlyoverArtifactError(f"{path}.{field} is not positive")
    return size


def validate_rect(value: object, path: str) -> dict[str, object]:
    rect = required_object(value, path, ("x", "y", "width", "height"))
    number(rect["x"], f"{path}.x")
    number(rect["y"], f"{path}.y")
    for field in ("width", "height"):
        if number(rect[field], f"{path}.{field}") <= 0:
            raise FlyoverArtifactError(f"{path}.{field} is not positive")
    return rect


def validate_point(value: object, path: str) -> None:
    point = required_object(value, path, ("x", "y"))
    number(point["x"], f"{path}.x")
    number(point["y"], f"{path}.y")


def validate_geometry(value: object, path: str) -> None:
    geometry = required_object(
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
        validate_point(geometry[field], f"{path}.{field}")


def validate_viewport(value: object, path: str) -> None:
    viewport = required_object(value, path, ("kind",))
    kind = string(viewport["kind"], f"{path}.kind")
    fixed_size = viewport.get("fixedSize")
    if kind == "device":
        if fixed_size is not None:
            raise FlyoverArtifactError(
                f"{path}.fixedSize must be null for a device viewport"
            )
    elif kind == "fixed":
        validate_size(fixed_size, f"{path}.fixedSize")
    else:
        raise FlyoverArtifactError(f"{path}.kind has an unsupported value: {kind}")


def capture_extent(value: object, path: str) -> str:
    extent = string(value, path)
    if extent not in {"viewport", "intrinsic", "fullContent", "fullContent2D"}:
        raise FlyoverArtifactError(f"{path} has an unsupported value: {extent}")
    return extent


def safe_image_path(value: str) -> PurePosixPath:
    relative = PurePosixPath(value)
    if (
        not value
        or "\\" in value
        or relative.is_absolute()
        or ".." in relative.parts
        or relative.parts[:1] != ("images",)
        or relative.suffix.lower() != ".png"
    ):
        raise FlyoverArtifactError(
            f"the manifest contains an unsafe image path: {value}"
        )
    return relative
