"""Validate the three Where ad hoc profiles before archiving or exporting."""

import argparse
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import json
from pathlib import Path
import plistlib
import re
import shlex
import sys


@dataclass(frozen=True)
class Target:
    name: str
    environment_key: str


TARGETS = (
    Target("Where", "TUIST_WHERE_ADHOC_APP_PROFILE"),
    Target("WhereWidgets", "TUIST_WHERE_ADHOC_WIDGET_PROFILE"),
    Target("WhereShareExtension", "TUIST_WHERE_ADHOC_SHARE_PROFILE"),
)


@dataclass(frozen=True)
class Profile:
    target: str
    uuid: str
    team: str
    bundle_id: str


def read_profile(target: Target, data: dict, now: datetime) -> Profile:
    profile_uuid = data.get("UUID", "")
    if not isinstance(profile_uuid, str) or not re.fullmatch(
        r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", profile_uuid
    ):
        raise ValueError(f"{target.name}: invalid profile UUID")
    teams = data.get("TeamIdentifier", [])
    if (not isinstance(teams, list) or len(teams) != 1
            or not isinstance(teams[0], str)
            or not re.fullmatch(r"[A-Z0-9]{10}", teams[0])):
        raise ValueError(f"{target.name}: expected one Apple Developer team")
    expiration = data.get("ExpirationDate")
    if not isinstance(expiration, datetime) or expiration.replace(tzinfo=timezone.utc) <= now:
        raise ValueError(f"{target.name}: provisioning profile is expired or has no expiry")
    entitlements = data.get("Entitlements", {})
    devices = data.get("ProvisionedDevices", [])
    if (not isinstance(entitlements, dict) or entitlements.get("get-task-allow") is not False
            or data.get("ProvisionsAllDevices") is True
            or not isinstance(devices, list) or not devices
            or not all(isinstance(device, str) and device for device in devices)):
        raise ValueError(f"{target.name}: an ad hoc profile with registered devices is required")
    application_id = entitlements.get("application-identifier", "")
    if not isinstance(application_id, str) or "." not in application_id:
        raise ValueError(f"{target.name}: missing application identifier")
    prefix, bundle_id = application_id.split(".", 1)
    prefixes = data.get("ApplicationIdentifierPrefix", [])
    if (not isinstance(prefixes, list) or prefix not in prefixes
            or not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle_id)):
        raise ValueError(f"{target.name}: an explicit app identifier is required")
    return Profile(target.name, profile_uuid, teams[0], bundle_id)


def prepare(profiles_directory: Path, destination: Path, now: datetime) -> None:
    profiles = []
    device_sets = []
    for target in TARGETS:
        with (profiles_directory / f"{target.name}.plist").open("rb") as source:
            data = plistlib.load(source)
        if not isinstance(data, dict):
            raise ValueError(f"{target.name}: invalid provisioning profile")
        profiles.append(read_profile(target, data, now))
        device_sets.append(set(data["ProvisionedDevices"]))
    if len({profile.team for profile in profiles}) != 1:
        raise ValueError("All Where profiles must belong to the same Apple Developer team")
    if len({profile.bundle_id for profile in profiles}) != len(TARGETS):
        raise ValueError("Each Where target needs its own provisioning profile")
    if len({profile.uuid for profile in profiles}) != len(TARGETS):
        raise ValueError("Each Where target needs a distinct profile UUID")
    if not all(devices == device_sets[0] for devices in device_sets):
        raise ValueError("All Where profiles must include the same registered devices")

    destination.mkdir(parents=True, exist_ok=True)
    (destination / "profiles.json").write_text(json.dumps([asdict(profile) for profile in profiles]))
    environment = {"TUIST_DEVELOPMENT_TEAM": profiles[0].team}
    for target, profile in zip(TARGETS, profiles):
        environment[target.environment_key] = profile.uuid
    (destination / "signing.env").write_text("".join(
        f"export {key}={shlex.quote(value)}\n" for key, value in environment.items()
    ))
    with (destination / "ExportOptions.plist").open("wb") as output:
        plistlib.dump({
            "method": "release-testing",
            "destination": "export",
            "signingStyle": "manual",
            "signingCertificate": "Apple Distribution",
            "teamID": profiles[0].team,
            "provisioningProfiles": {profile.bundle_id: profile.uuid for profile in profiles},
            "manageAppVersionAndBuildNumber": False,
            "thinning": "<none>",
        }, output)


def validate_settings(settings: list, profiles: list) -> None:
    for profile in profiles:
        matches = [item["buildSettings"] for item in settings if item.get("target") == profile["target"]]
        if len(matches) != 1:
            raise ValueError(f"Expected one build-settings entry for {profile['target']}")
        actual = matches[0]
        expected = {
            "PRODUCT_BUNDLE_IDENTIFIER": profile["bundle_id"],
            "DEVELOPMENT_TEAM": profile["team"],
            "PROVISIONING_PROFILE_SPECIFIER": profile["uuid"],
            "CODE_SIGN_STYLE": "Manual",
            "WHERE_AUDIENCE": "development",
        }
        for key, value in expected.items():
            if actual.get(key) != value:
                raise ValueError(f"{profile['target']}: {key} does not match the ad hoc signing plan")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare_parser = commands.add_parser("prepare")
    prepare_parser.add_argument("--profiles", type=Path, required=True)
    prepare_parser.add_argument("--output", type=Path, required=True)
    settings_parser = commands.add_parser("validate-settings")
    settings_parser.add_argument("--settings", type=Path, required=True)
    settings_parser.add_argument("--profiles", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "prepare":
            prepare(args.profiles, args.output, datetime.now(timezone.utc))
        else:
            validate_settings(json.loads(args.settings.read_text()), json.loads(args.profiles.read_text()))
    except (OSError, ValueError, plistlib.InvalidFileException, KeyError, TypeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
