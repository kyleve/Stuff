"""Shared fixtures for Flyover manifest and preview tool tests."""

import json
from pathlib import Path
from typing import Any


def write_manifest(root: Path, manifest: object) -> None:
    data = json.dumps(manifest)
    (root / "manifest.json").write_text(data)
    (root / "manifest.js").write_text("window.FLYOVER_MANIFEST = " + data + ";\n")


def create_flyover_artifact(root: Path) -> Path:
    (root / "assets").mkdir(parents=True)
    image = root / "images/screen-0001/variant-0001/phone-light.png"
    image.parent.mkdir(parents=True)
    image.write_bytes(b"PNG")
    (root / ".flyover-generated").write_text("schemaVersion=1\n")
    (root / "index.html").write_text("<!doctype html>")
    (root / "assets/app.js").write_text("")
    (root / "assets/styles.css").write_text("")
    write_manifest(root, flyover_manifest_fixture())
    return root


def flyover_manifest_fixture() -> dict[str, Any]:
    image_path = "images/screen-0001/variant-0001/phone-light.png"
    screen_frame = {"x": 50, "y": 50, "width": 300, "height": 650}
    return {
        "schemaVersion": 1,
        "application": {"id": "where", "title": "Where"},
        "build": {
            "commit": "abc123",
            "dirty": False,
            "generatedAt": "2026-09-07T12:00:00Z",
            "xcodeVersion": "Xcode 27.0",
            "simulatorDevice": "iPhone 17",
            "simulatorOS": "27.0",
        },
        "profiles": [
            {
                "id": "phone-light",
                "title": "Phone Light",
                "device": "phone",
                "orientation": "portrait",
                "colorScheme": "light",
                "dynamicType": "large",
                "contrast": "standard",
                "layoutDirection": "left-to-right",
                "legibilityWeight": "regular",
                "snapshotType": "standard",
            }
        ],
        "canvas": {
            "size": {"width": 500, "height": 700},
            "initialFitSize": {"width": 500, "height": 700},
            "groupFrames": [
                {
                    "id": "group",
                    "frame": {"x": 0, "y": 0, "width": 500, "height": 700},
                }
            ],
            "depthBandFrames": [
                {
                    "groupID": "group",
                    "kind": "route",
                    "depth": 0,
                    "frame": {"x": 20, "y": 20, "width": 460, "height": 660},
                }
            ],
            "screenFrames": [{"id": "screen", "frame": screen_frame}],
            "connectors": [],
        },
        "groups": [
            {
                "id": "group",
                "title": "Group",
                "order": 0,
                "rootScreenID": "screen",
                "screenIDs": ["screen"],
            }
        ],
        "screens": [
            {
                "id": "screen",
                "title": "Screen",
                "groupID": "group",
                "groupOrder": 0,
                "screenOrder": 0,
                "viewport": {"kind": "device"},
                "navigationContainer": "stack",
                "frame": screen_frame,
                "variants": [
                    {
                        "id": "default",
                        "title": "Default",
                        "captureExtent": "viewport",
                        "imagesByProfile": {"phone-light": image_path},
                    }
                ],
                "incomingRouteIDs": [],
                "outgoingRouteIDs": [],
            }
        ],
        "routes": [],
        "images": [
            {
                "screenID": "screen",
                "variantID": "default",
                "profileID": "phone-light",
                "relativePath": image_path,
                "pointWidth": 402,
                "pointHeight": 874,
                "pixelWidth": 1206,
                "pixelHeight": 2622,
                "scale": 3,
                "captureExtent": "viewport",
            }
        ],
    }
