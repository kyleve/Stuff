"""Image metadata and state/profile coverage validation."""

from Tools.flyover_schema_values import (
    FlyoverArtifactError,
    required_object,
    required_list,
    string,
    integer,
    number,
    capture_extent,
    safe_image_path,
)


def validate_images(
    value: object,
    profile_by_id: dict[str, dict[str, object]],
    screen_by_id: dict[str, dict[str, object]],
    variant_by_key: dict[tuple[str, str], dict[str, object]],
) -> None:
    images = required_list(value, "manifest.images", nonempty=True)
    image_by_key: dict[tuple[str, str, str], dict[str, object]] = {}
    paths: set[str] = set()
    for index, value in enumerate(images):
        image = required_object(
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
        present_thumbnail_fields = [
            field for field in thumbnail_fields if field in image
        ]
        if present_thumbnail_fields and len(present_thumbnail_fields) != len(
            thumbnail_fields
        ):
            raise FlyoverArtifactError(
                f"manifest.images[{index}] has incomplete thumbnail metadata"
            )
        screen_id = string(
            image["screenID"], f"manifest.images[{index}].screenID", nonempty=True
        )
        variant_id = string(
            image["variantID"],
            f"manifest.images[{index}].variantID",
            nonempty=True,
        )
        profile_id = string(
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
        relative_path = safe_image_path(
            string(
                image["relativePath"],
                f"manifest.images[{index}].relativePath",
                nonempty=True,
            )
        ).as_posix()
        if relative_path in paths:
            raise FlyoverArtifactError("manifest.json contains a duplicate image path")
        paths.add(relative_path)
        if present_thumbnail_fields:
            thumbnail_path = safe_image_path(
                string(
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
                if integer(image[field], f"manifest.images[{index}].{field}") <= 0:
                    raise FlyoverArtifactError(
                        f"manifest.images[{index}].{field} is not positive"
                    )
        expected_path = variant["imagesByProfile"][profile_id]
        if relative_path != expected_path:
            raise FlyoverArtifactError(
                f"manifest.images[{index}].relativePath does not match imagesByProfile"
            )
        extent = capture_extent(
            image["captureExtent"],
            f"manifest.images[{index}].captureExtent",
        )
        if extent != variant["captureExtent"]:
            raise FlyoverArtifactError(
                f"manifest.images[{index}].captureExtent does not match its variant"
            )
        for field in ("pointWidth", "pointHeight", "scale"):
            if number(image[field], f"manifest.images[{index}].{field}") <= 0:
                raise FlyoverArtifactError(
                    f"manifest.images[{index}].{field} is not positive"
                )
        for field in ("pixelWidth", "pixelHeight"):
            if integer(image[field], f"manifest.images[{index}].{field}") <= 0:
                raise FlyoverArtifactError(
                    f"manifest.images[{index}].{field} is not positive"
                )

    expected_keys = {
        (screen_id, variant_id, profile_id)
        for screen_id, variant_id in variant_by_key
        for profile_id in profile_by_id
    }
    if set(image_by_key) != expected_keys:
        raise FlyoverArtifactError(
            "manifest.images does not contain exactly one image for each state and profile"
        )
