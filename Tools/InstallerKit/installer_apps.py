"""Trusted app registrations for shared installer publication."""

import argparse
from dataclasses import dataclass
import os
import sys
import json
from pathlib import Path
import re
from typing import Optional

from Tools.repository import repository_root


REGISTRY = repository_root(__file__) / ".github/installer-apps.json"


def validate_app_id(value):
    if not isinstance(value, str) or not re.fullmatch(r"[a-z][a-z0-9-]{0,63}", value):
        raise ValueError("Invalid installer app ID")
    return value


def validate_metadata(value):
    validate_app_id(value["id"])
    if not isinstance(value["name"], str) or not value["name"].strip():
        raise ValueError("An app display name is required")
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", value["bundleIdentifier"]):
        raise ValueError("Invalid app bundle identifier")


@dataclass(frozen=True)
class AppPresentation:
    """Site-only branding from the trusted registration, independent of release metadata."""

    subtitle: str
    icon: Optional[str]
    dark_icon: Optional[str]


def presentation(value):
    if not isinstance(value, dict) or not isinstance(value.get("subtitle"), str) or not value["subtitle"].strip():
        raise ValueError("App site presentation requires a subtitle")
    for key in ("icon", "darkIcon"):
        path = value.get(key)
        if path is not None and (not isinstance(path, str) or not path.endswith(".png")
                                 or Path(path).is_absolute() or ".." in Path(path).parts):
            raise ValueError("App artwork must be a repository-relative PNG path")
    if value.get("darkIcon") and not value.get("icon"):
        raise ValueError("Dark app artwork also requires a default icon")
    return AppPresentation(value["subtitle"], value.get("icon"), value.get("darkIcon"))


@dataclass(frozen=True)
class InstallerApp:
    id: str
    name: str
    bundle_identifier: str
    bundle_path: str
    signed_bundles: tuple
    required_info: dict
    presentation: AppPresentation
    source_directory: Optional[str] = None

    @property
    def metadata(self):
        return {"id": self.id, "name": self.name, "bundleIdentifier": self.bundle_identifier}


def load_apps(path=REGISTRY):
    """Load from the trusted controller checkout, never from the IPA or PR receipt."""
    values = json.loads(path.read_text())
    ids = set()
    bundles = set()
    apps = {}
    for value in values:
        validate_metadata(value)
        if value["id"] in ids or value["bundleIdentifier"] in bundles:
            raise ValueError("Duplicate installer app or bundle identifier")
        ids.add(value["id"])
        bundles.add(value["bundleIdentifier"])
        bundle = value["bundlePath"]
        if not re.fullmatch(r"Payload/[A-Za-z0-9_-]+\.app", bundle):
            raise ValueError("Invalid IPA app bundle path")
        signed = value["signedBundles"]
        if not isinstance(signed, list) or bundle not in signed or len(signed) != len(set(signed)):
            raise ValueError("Signed bundles must include the app exactly once")
        for item in signed:
            if item != bundle and not re.fullmatch(re.escape(bundle) + r"/PlugIns/[A-Za-z0-9_-]+\.appex", item):
                raise ValueError("Invalid signed extension path")
        source = value.get("sourceDirectory")
        if source is not None and (not isinstance(source, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", source)):
            raise ValueError("Source directory must be one repository-root directory")
        info = value["requiredInfo"]
        if not isinstance(info, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in info.items()):
            raise ValueError("Expected app metadata must contain string keys and values")
        apps[value["id"]] = InstallerApp(value["id"], value["name"], value["bundleIdentifier"],
                                         bundle, tuple(signed), info,
                                         presentation(value.get("site", {"subtitle": "Development build"})), source)
    return apps


def load_app(app_id, path=REGISTRY):
    validate_app_id(app_id)
    apps = load_apps(path)
    if app_id not in apps:
        raise ValueError(f"Unregistered installer app: {app_id}")
    return apps[app_id]


SIGNING_REGISTRY = REGISTRY.with_name("installer-signing-apps.json")


def archive_product(app_id, apps_path=REGISTRY, signing_path=SIGNING_REGISTRY):
    """Resolve the exported filename from trusted signing configuration."""
    app = load_app(app_id, apps_path)
    descriptor = json.loads(signing_path.read_text())[app_id]
    product = descriptor["product"]
    if not isinstance(product, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", product):
        raise ValueError("Invalid archive product name")
    if app.bundle_path != f"Payload/{product}.app":
        raise ValueError("Signing product does not match the registered IPA bundle")
    return product


def enabled_apps(variables, apps_path=REGISTRY, signing_path=SIGNING_REGISTRY):
    """The label opts into enabled registrations, never infers an app from PR text."""
    selected = []
    for app in load_apps(apps_path).values():
        variable = f"{app.id.upper().replace('-', '_')}_DISTRIBUTION_ENABLED"
        if variables.get(variable) == "true":
            archive_product(app.id, apps_path, signing_path)
            selected.append(app.id)
    return selected


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        selected = enabled_apps(json.loads(os.environ.get("INSTALLER_VARIABLES", "{}")))
        output = f"apps={json.dumps(selected, separators=(',', ':'))}\n"
        with args.output.open("a") as destination:
            destination.write(output)
        print(output, end="")
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
