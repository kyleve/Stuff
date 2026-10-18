"""Canonical HTTPS locations and OTA manifests for registered iOS app releases."""

import plistlib
import re
from urllib.parse import urlsplit, urlencode

from Tools.InstallerKit.github_releases import asset_url, release_tag
from Tools.InstallerKit.installer_apps import validate_metadata


def site_url(feed_url):
    value = urlsplit(feed_url)
    if (value.scheme != "https" or not value.hostname or value.username is not None
            or value.password is not None or value.port is not None or value.query or value.fragment
            or not value.path.endswith("/updates.json")
            or not re.fullmatch(r"/[A-Za-z0-9_./~-]+", value.path)
            or any(part in (".", "..") for part in value.path.split("/"))):
        raise ValueError("Feed URL must be an HTTPS updates.json URL without credentials, port, query, or fragment")
    return feed_url[:-len("updates.json")]


def manifest_path(app_id, channel, identifier):
    release_tag(app_id, channel, identifier)  # Validate channel and build identity first.
    return f"manifests/{app_id}/{channel}/{identifier['run']}-{identifier['attempt']}.plist"


def manifest_url(feed_url, app_id, channel, identifier):
    return site_url(feed_url) + manifest_path(app_id, channel, identifier)


def install_url(manifest):
    return "itms-services://?" + urlencode({"action": "download-manifest", "url": manifest})


def validate_bundle_version(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value):
        raise ValueError("IPA CFBundleVersion must be a numeric bundle version")
    return value


def validate_build_details(value):
    """Optional catalog details, read from the signed IPA when publishing new builds."""
    if not isinstance(value, dict):
        raise ValueError("Build details must be an object")
    for key in ("version", "minimumOSVersion"):
        if not isinstance(value.get(key), str) or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value[key]):
            raise ValueError(f"Build details {key} must be a numeric version")
    if type(value.get("sizeBytes")) is not int or value["sizeBytes"] <= 0:
        raise ValueError("Build details sizeBytes must be a positive integer")
    return value


def validate_release(release, repository, app_id, channel, feed_url):
    expected_manifest = manifest_url(feed_url, app_id, channel, release["id"])
    if release["manifestURL"] != expected_manifest:
        raise ValueError("Manifest URL does not match this app, channel, build, and Pages site")
    if release["ipaURL"] != asset_url(repository, app_id, channel, release["id"]):
        raise ValueError("IPA URL does not match this GitHub release")
    validate_bundle_version(release["bundleVersion"])
    if "buildDetails" in release:
        validate_build_details(release["buildDetails"])


def manifest(app, release):
    validate_metadata(app)
    return plistlib.dumps({"items": [{
        "assets": [{"kind": "software-package", "url": release["ipaURL"]}],
        "metadata": {"bundle-identifier": app["bundleIdentifier"], "bundle-version": release["bundleVersion"],
                     "kind": "software", "title": app["name"]},
    }]}, fmt=plistlib.FMT_XML)
