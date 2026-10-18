"""Render the install site, OTA manifests, and catalog as one Pages deployment."""

import argparse
from datetime import datetime
import hashlib
from html import escape
import json
import os
from pathlib import Path
import re
import sys
import tempfile

from installer_apps import AppPresentation, load_apps
from installer_installation import install_url, manifest, manifest_path, site_url, validate_release
from installer_update_feed import read_catalog


SOURCE_ROOT = Path(__file__).resolve().parents[1]


def symbol(name, size=24):
    paths = {
        "apps": '<rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/>'
                '<rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/>',
        "arrow": '<path d="m9 5 7 7-7 7" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>',
        "phone": '<rect x="6" y="2" width="12" height="20" rx="3" fill="none" stroke="currentColor" stroke-width="1.5"/>'
                 '<path d="M10 18h4" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',
    }
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="currentColor" '
            f'aria-hidden="true">{paths[name]}</svg>')


def document(title, body, root, repository):
    style = Path(__file__).with_name("installer_site.css").read_text()
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width, initial-scale=1">'
            f'<meta name="color-scheme" content="light dark">'
            f'<title>{escape(title)}</title><style>{style}</style></head><body>'
            f'<header class="site-header"><div class="shell"><a class="brand" href="{escape(root, quote=True)}">'
            f'{symbol("apps")}Apps</a><span class="site-label">Development builds</span></div></header>'
            f'<main class="shell">{body}</main><footer class="site-footer"><div class="shell">'
            f'<span>Built for your registered devices.</span><a href="https://github.com/{repository}">GitHub</a>'
            '</div></footer></body></html>').encode()


def channel_page(app_id, channel):
    return f"apps/{app_id}/{channel}/"


def channel_label(name):
    return "Main" if name == "main" else f"PR #{name[3:]}"


def app_artwork(app, presentation, root, files):
    """Copy trusted source artwork once per app; missing registration uses a monogram."""
    urls = []
    for path in (presentation.icon, presentation.dark_icon):
        if path is None:
            urls.append(None)
            continue
        source = (SOURCE_ROOT / path).resolve()
        if SOURCE_ROOT not in source.parents:
            raise ValueError("App artwork must stay inside the repository")
        contents = source.read_bytes()
        if not contents.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ValueError(f"App artwork is not a PNG: {path}")
        relative = f'assets/{app["id"]}/{hashlib.sha256(contents).hexdigest()[:16]}.png'
        files[relative] = contents
        urls.append(escape(root + relative, quote=True))
    if urls[0] is None:
        return f'<span class="app-icon placeholder" aria-hidden="true">{escape(app["name"].strip()[0].upper())}</span>'
    dark = f'<source media="(prefers-color-scheme: dark)" srcset="{urls[1]}">' if urls[1] else ""
    return f'<picture class="app-icon">{dark}<img src="{urls[0]}" width="148" height="148" alt=""></picture>'


def install_button(app, channel):
    release = channel["releases"][0]
    label = f'Install {app["name"]} · {channel_label(channel["name"])}'
    return (f'<a class="install" aria-label="{escape(label, quote=True)}" '
            f'href="{escape(install_url(release["manifestURL"]), quote=True)}">Install</a>')


def published_date(release, include_year):
    date = datetime.fromisoformat(release["publishedAt"].replace("Z", "+00:00"))
    month = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")[date.month - 1]
    label = f"{month} {date.day}" + (f", {date.year}" if include_year else "")
    return f'<time datetime="{release["publishedAt"]}">{label}</time>'


def download_size(size):
    if size >= 1_000_000_000:
        return f"{size / 1_000_000_000:.1f} GB"
    if size >= 1_000_000:
        return f"{size / 1_000_000:.1f} MB"
    return f"{max(1, round(size / 1_000)):,} KB"


def quick_facts(release, expanded):
    details = release.get("buildDetails")
    entries = [("Version", escape(details["version"])) if details else ("Build", escape(release["bundleVersion"])),
               ("Download", download_size(details["sizeBytes"]) if details else "Not recorded")]
    if expanded:
        entries.append(("Requires iOS", escape(details["minimumOSVersion"]) + "+" if details else "Not recorded"))
    entries.append(("Updated", published_date(release, include_year=expanded)))
    return '<dl class="quick-facts">' + ''.join(f'<div><dt>{label}</dt><dd>{value}</dd></div>' for label, value in entries) + '</dl>'


def app_card(app, main, presentation, artwork, root):
    app_url = root + f'apps/{app["id"]}/'
    action = install_button(app, main) if main else '<p class="unavailable">No main build is available yet.</p>'
    facts = quick_facts(main["releases"][0], expanded=False) if main else ""
    return (f'<article class="app-card"><div class="app-card-top">{artwork}<div>'
            f'<h3><a class="app-name" href="{escape(app_url, quote=True)}">{escape(app["name"])}</a></h3>'
            f'<p class="subtitle">{escape(presentation.subtitle)}</p>{action}</div></div>{facts}'
            f'<div class="card-footer"><span class="tag">MAIN</span>'
            f'<a aria-label="Browse {escape(app["name"], quote=True)} builds" href="{escape(app_url, quote=True)}">'
            f'All builds {symbol("arrow", 14)}</a></div></article>')


def breadcrumbs(app, root):
    return (f'<nav class="breadcrumbs" aria-label="Breadcrumb"><a href="{escape(root, quote=True)}">All apps</a>'
            f'<span aria-hidden="true">/</span><a href="{escape(root + "apps/" + app["id"] + "/", quote=True)}">'
            f'{escape(app["name"])}</a></nav>')


def app_hero(app, channel, presentation, artwork, label):
    action = (f'<div class="hero-action">{install_button(app, channel)}<span>For registered devices</span></div>'
              if channel else "")
    return (f'<header class="app-hero">{artwork}<div><span class="tag">{escape(label)}</span>'
            f'<h1>{escape(app["name"])}</h1><p class="subtitle">{escape(presentation.subtitle)}</p>{action}</div></header>')


def build_summary(app, channel, root, repository):
    release = channel["releases"][0]
    page_url = root + channel_page(app["id"], channel["name"])
    return ('<section class="detail-panel" aria-label="Build summary">' + quick_facts(release, expanded=True)
            + f'<div class="build-footnote"><span>Build {escape(release["bundleVersion"])} · '
              f'<a href="https://github.com/{repository}/commit/{release["sha"]}"><code>{release["sha"][:7]}</code></a></span>'
              f'<a href="{escape(page_url, quote=True)}">Build details {symbol("arrow", 14)}</a></div></section>')


def branch_row(app, channel, root):
    release = channel["releases"][0]
    details = release.get("buildDetails")
    version = f'Version {details["version"]}' if details else f'Build {release["bundleVersion"]}'
    page_url = root + channel_page(app["id"], channel["name"])
    return (f'<article class="channel-row"><div><h3><a href="{escape(page_url, quote=True)}">'
            f'{channel_label(channel["name"])} {symbol("arrow", 14)}</a></h3>'
            f'<p>{escape(version)} · {published_date(release, include_year=True)}</p></div>'
            f'{install_button(app, channel)}</article>')


def release_notes(release, repository):
    if release["historyChanged"] or release["baseSHA"] is None:
        return '<p class="section-note">Complete commit history is unavailable for this build.</p>'
    items = []
    for commit in release["commits"]:
        if not re.fullmatch(r"[0-9a-f]{40}", commit["sha"]):
            raise ValueError("Invalid commit in release notes")
        items.append(f'<li><a href="https://github.com/{repository}/commit/{commit["sha"]}">'
                     f'<span>{escape(commit["subject"])}</span><code>{commit["sha"][:7]}</code></a></li>')
    return '<ul class="commit-list">' + ''.join(items) + '</ul>' if items else '<p class="section-note">No new commits.</p>'


def build_information(app, channel, repository):
    release = channel["releases"][0]
    run = release["id"]
    source = (f'https://github.com/{repository}/tree/main' if channel["name"] == "main"
              else f'https://github.com/{repository}/pull/{channel["name"][3:]}')
    rows = [("Channel", f'<a href="{source}">{channel_label(channel["name"])}</a>'),
            ("Published", f'{published_date(release, include_year=True)} at {release["publishedAt"][11:16]} UTC'),
            ("Build", escape(release["bundleVersion"])),
            ("Workflow run", f'<a href="https://github.com/{repository}/actions/runs/{run["run"]}/attempts/{run["attempt"]}">'
                             f'{run["run"]} · Attempt {run["attempt"]}</a>'),
            ("Commit", f'<a href="https://github.com/{repository}/commit/{release["sha"]}"><code>{release["sha"][:12]}</code></a>'),
            ("Bundle ID", escape(app["bundleIdentifier"]))]
    return ('<section class="information"><h2>Information</h2><dl>'
            + ''.join(f'<div><dt>{label}</dt><dd>{value}</dd></div>' for label, value in rows) + '</dl></section>')


def install_help():
    return (f'<aside class="install-help">{symbol("phone", 28)}<div><h2>Install on your iPhone or iPad</h2>'
            '<p>Open this site in Safari on a registered device. Tap Install, then confirm the iOS prompt. '
            'Your app will appear on the Home Screen.</p></div></aside>')


def empty_state(title, message, link=""):
    return (f'<section class="empty-state">{symbol("apps", 36)}<h2>{escape(title)}</h2>'
            f'<p>{escape(message)}</p>{link}</section>')


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


def render_site(catalog, repository, feed_url, registered_apps=None):
    root = site_url(feed_url)
    read_catalog(catalog)
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid GitHub repository")
    registered_apps = load_apps() if registered_apps is None else registered_apps
    files = {"updates.json": json.dumps(catalog, ensure_ascii=False, separators=(",", ":")).encode(),
             ".nojekyll": b""}
    cards = []
    for app in sorted(catalog["apps"], key=lambda value: (value["name"].casefold(), value["id"])):
        registered = registered_apps.get(app["id"])
        if registered and registered.bundle_identifier != app["bundleIdentifier"]:
            raise ValueError("Catalog bundle identifier differs from its registered app")
        presentation = registered.presentation if registered else AppPresentation("Development build", None, None)
        artwork = app_artwork(app, presentation, root, files)
        app_url = root + f'apps/{app["id"]}/'
        main_channel = None
        branches = []
        for channel in app["channels"]:
            validate_channel(app, channel, repository, feed_url, files)
            name = channel["name"]
            active = channel if channel["active"] else None
            intro = breadcrumbs(app, root) + app_hero(app, active, presentation, artwork, channel_label(name))
            if active:
                release = channel["releases"][0]
                content = ('<section class="detail-panel" aria-label="Build summary">' + quick_facts(release, expanded=True)
                           + '<section class="section"><div class="notes-heading"><h2>What’s New</h2></div>'
                           '<p class="notes-subtitle">Changes since the previous build</p>'
                           + release_notes(release, repository) + '</section></section>'
                           + build_information(app, channel, repository) + install_help())
                if name == "main":
                    main_channel = channel
                else:
                    branches.append(channel)
            else:
                message = ("This PR is closed or no longer labeled installable. Historical releases remain on GitHub."
                           if name != "main" else "This build channel is no longer available.")
                content = empty_state("Channel retired", message,
                                      f'<a class="text-link" href="{escape(app_url, quote=True)}">Browse {escape(app["name"])} builds '
                                      f'{symbol("arrow", 14)}</a>')
            files[channel_page(app["id"], name) + "index.html"] = document(
                f'{app["name"]} · {channel_label(name)}', intro + content, root, repository)
        cards.append(app_card(app, main_channel, presentation, artwork, root))
        main_content = (build_summary(app, main_channel, root, repository) if main_channel
                        else empty_state("No main build yet", "The latest successful main build will appear here."))
        branch_content = ('<div class="channel-list">'
                          + ''.join(branch_row(app, channel, root) for channel in sorted(branches, key=lambda item: int(item["name"][3:]), reverse=True))
                          + '</div>' if branches else empty_state("No pull request builds", "Installable pull requests will appear here."))
        app_body = (breadcrumbs(app, root) + app_hero(app, main_channel, presentation, artwork, "LATEST MAIN BUILD")
                    + main_content + '<section class="section"><div class="section-heading"><h2>Pull Request Builds</h2>'
                    f'<p>{len(branches)} available</p></div>' + branch_content
                    + '<p class="section-note">Switching channels replaces this development app and preserves its data.</p></section>'
                    + install_help())
        files[f'apps/{app["id"]}/index.html'] = document(f'{app["name"]} builds', app_body, root, repository)
    body = ('<header class="page-heading"><p class="eyebrow">THE LATEST BUILDS</p><h1>App Library</h1>'
            '<p class="lede">Your development apps, all in one place.<br>Pick an app. Install the latest. See what’s new.</p></header>'
            '<section aria-labelledby="latest"><div class="section-heading"><h2 id="latest">Fresh from main</h2>'
            f'<p>{len(cards)} {"app" if len(cards) == 1 else "apps"}</p></div>'
            + ('<div class="catalog">' + ''.join(cards) + '</div>' if cards
               else empty_state("No builds are available yet", "Apps will appear here after their first build is published."))
            + '</section>' + install_help())
    files["index.html"] = document("App Library", body, root, repository)
    return files


def write_site(files, output):
    if output.exists():
        raise ValueError("Pages output directory must not exist")
    # The complete artifact is validated and staged before its single rename.
    with tempfile.TemporaryDirectory(prefix="installer-pages-", dir=output.parent) as temporary:
        staging = Path(temporary) / "site"
        staging.mkdir()
        for relative, contents in files.items():
            target = staging / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(contents)
        os.rename(staging, output)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--feed-url", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        files = render_site(json.loads(args.catalog.read_text()), args.repository, args.feed_url)
        write_site(files, args.output)
        print(f"Prepared {len(files)} Pages files in {args.output}")
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
