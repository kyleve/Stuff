"""Validate installer publication data and prepare Astro's input and public files."""

from dataclasses import dataclass
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import urlsplit

from installer_apps import AppPresentation, load_apps
from installer_installation import install_url, manifest, manifest_path, site_url, validate_release
from installer_update_feed import read_catalog


SOURCE_ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class PreparedSite:
    """Validated presentation data and the exact files deployed with its pages."""

    data: dict
    files: dict


def app_artwork(app, presentation, base_path, files):
    """Copy trusted artwork; a missing registration produces a monogram in Astro."""
    urls = {}
    for key, path in (("icon", presentation.icon), ("darkIcon", presentation.dark_icon)):
        urls[key] = None
        if path is None:
            continue
        source = (SOURCE_ROOT / path).resolve()
        if SOURCE_ROOT not in source.parents:
            raise ValueError("App artwork must stay inside the repository")
        contents = source.read_bytes()
        if not contents.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ValueError(f"App artwork is not a PNG: {path}")
        relative = f'assets/{app["id"]}/{hashlib.sha256(contents).hexdigest()[:16]}.png'
        files[relative] = contents
        urls[key] = base_path + relative
    return {"subtitle": presentation.subtitle, **urls}


def validate_channel(app, channel, repository, feed_url, files):
    name = channel["name"]
    if not re.fullmatch(r"main|pr-[1-9][0-9]*", name) or type(channel["active"]) is not bool:
        raise ValueError("Invalid update channel")
    if channel["active"] and not channel["releases"]:
        raise ValueError("Active channel has no releases")
    prior = None
    for release in channel["releases"]:
        validate_release(release, repository, app["id"], name, feed_url)
        order = (release["id"]["run"], release["id"]["attempt"])
        if prior is not None and order >= prior:
            raise ValueError("Releases must be unique and newest first")
        prior = order
        if not re.fullmatch(r"[0-9a-f]{40}", release["sha"]):
            raise ValueError("Invalid build commit")
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", release["publishedAt"]):
            raise ValueError("Publication date must use UTC")
        datetime.fromisoformat(release["publishedAt"].replace("Z", "+00:00"))
        if channel["active"]:
            files[manifest_path(app["id"], name, release["id"])] = manifest(app, release)


def prepare_site(catalog, repository, feed_url, registered_apps=None):
    """Keep catalog, URL, identity, and retirement policy outside the HTML renderer."""
    root = site_url(feed_url)
    base_path = urlsplit(root).path
    read_catalog(catalog)
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid GitHub repository")
    registered_apps = load_apps() if registered_apps is None else registered_apps
    files = {"updates.json": json.dumps(catalog, ensure_ascii=False, separators=(",", ":")).encode(),
             ".nojekyll": b""}
    apps = []
    for app in sorted(catalog["apps"], key=lambda value: (value["name"].casefold(), value["id"])):
        registered = registered_apps.get(app["id"])
        if registered and registered.bundle_identifier != app["bundleIdentifier"]:
            raise ValueError("Catalog bundle identifier differs from its registered app")
        presentation = registered.presentation if registered else AppPresentation("Development build", None, None)
        artwork = app_artwork(app, presentation, base_path, files)
        channels = []
        for channel in app["channels"]:
            validate_channel(app, channel, repository, feed_url, files)
            if channel["active"]:
                release = channel["releases"][0]
                for commit in release["commits"]:
                    if not re.fullmatch(r"[0-9a-f]{40}", commit["sha"]) or not isinstance(commit["subject"], str):
                        raise ValueError("Invalid commit in release notes")
                channels.append({"name": channel["name"], "state": "active", "release": release,
                                 "installURL": install_url(release["manifestURL"])})
            else:
                channels.append({"name": channel["name"], "state": "retired"})
        apps.append({"id": app["id"], "name": app["name"], "bundleIdentifier": app["bundleIdentifier"],
                     "presentation": artwork, "channels": channels})
    return PreparedSite({"siteURL": root, "basePath": base_path, "repository": repository, "apps": apps}, files)
