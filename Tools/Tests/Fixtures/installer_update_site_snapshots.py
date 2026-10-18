"""Build the offline pages that ToolsSnapshotTests captures in WebKit.

Project.swift runs this module before it builds the snapshot bundle:
    python3 -m Tools.Tests.Fixtures.installer_update_site_snapshots --output <file>

The input is synthetic catalog data from installer_update_fixtures. The production
renderer turns each catalog into the same HTML and artwork that Pages publishes.
This module embeds that artwork in the HTML so WebKit needs no server or network.

The output is a JSON array of {"name": ..., "html": ...} objects.
InstallerSiteSnapshotTests.swift uses each name as a snapshot reference identifier.
It captures each page on iPhone and iPad in light and dark appearances.
Keep these names stable unless the matching reference images also change.
"""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

from Tools.InstallerKit.installer_update_site import render_site
from Tools.Tests.Fixtures.installer_update_fixtures import catalog, multiple_apps, FEED_URL, REPO


def offline_html(files, path):
    """Replace published artwork URLs with data URLs that contain the same bytes.

    The renderer already embeds CSS. Only its assets/ URLs need replacement here.
    Base64 represents each PNG as text inside the HTML without changing its pixels.
    """
    html = files[path].decode()
    root = FEED_URL[:-len("updates.json")]
    for relative, contents in files.items():
        if relative.startswith("assets/"):
            html = html.replace(root + relative, "data:image/png;base64," + base64.b64encode(contents).decode())
    return html


def pages():
    """Return the named pages for the website snapshot matrix.

    Each call creates a fresh catalog. The sequential changes below derive failure
    and retirement states from the full catalog without changing shared fixtures.
    """
    # Two apps and both main/PR channels exercise app grouping and navigation.
    value = multiple_apps()
    # Long release notes exercise scrolling and wrapping. These hashes give the
    # synthetic commits stable, valid identities. They are not repository commits.
    for channel in value["apps"][0]["channels"]:
        channel["releases"][0]["commits"] = [
            {"sha": hashlib.sha1(subject.encode()).hexdigest(), "subject": subject}
            for subject in [
                "Install development updates directly from Settings",
                "Keep the update badge visible until the newer build is installed",
                "Show every incoming commit, including changes from skipped builds",
                "Improve long region names on narrow screens and large displays",
                "Preserve the last successful update check while offline",
                "Keep main and pull request builds available from the install site",
                "Clarify installation confirmation and preserve existing Where Dev data",
                "Retain complete release notes when several builds arrive between checks",
            ]
        ]
    # Render the complete catalog once and select its three navigation levels.
    # render_site returns a mapping from output paths to file bytes.
    rendered = render_site(value, REPO, FEED_URL)
    result = [{"name": "Index", "html": offline_html(rendered, "index.html")},
              {"name": "App", "html": offline_html(rendered, "apps/where/index.html")},
              {"name": "Channel", "html": offline_html(rendered, "apps/where/pr-42/index.html")}]
    # A rewritten branch cannot provide complete incoming commit history.
    value["apps"][0]["channels"][1]["releases"][0]["historyChanged"] = True
    result.append({"name": "UnavailableHistory", "html": offline_html(render_site(value, REPO, FEED_URL),
        "apps/where/pr-42/index.html")})
    # Retirement keeps the channel page but removes its install action.
    value["apps"][0]["channels"][1]["active"] = False
    result.append({"name": "Retired", "html": offline_html(render_site(value, REPO, FEED_URL),
        "apps/where/pr-42/index.html")})
    # A catalog without apps has no artwork URLs to inline.
    result.append({"name": "Empty", "html": render_site(
        {"schemaVersion": 3, "apps": []}, REPO, FEED_URL)["index.html"].decode()})
    # An unregistered app supplies the placeholder icon. Its long name and older
    # release metadata exercise wrapping and explicit "Not recorded" values.
    legacy = catalog("example", "Example Development With a Longer Name", "com.example.development")
    legacy["apps"][0]["channels"] = legacy["apps"][0]["channels"][1:]
    for release in legacy["apps"][0]["channels"][0]["releases"]:
        del release["buildDetails"]
    result.append({"name": "MissingDetails", "html": offline_html(render_site(legacy, REPO, FEED_URL),
        "apps/example/pr-42/index.html")})
    return result


def main(argv=None):
    """Generate all pages, then replace the bundle resource as one complete file."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    temporary = None
    try:
        # Finish rendering before touching the previous bundle resource.
        content = json.dumps(pages(), ensure_ascii=False).encode()
        args.output.parent.mkdir(parents=True, exist_ok=True)
        # A sibling temporary file stays on the same filesystem as the output.
        # os.replace makes the complete new JSON visible in one operation.
        with tempfile.NamedTemporaryFile(dir=args.output.parent, delete=False) as destination:
            temporary = Path(destination.name)
            destination.write(content)
        os.replace(temporary, args.output)
        print(f"Generated install-site snapshot fixtures: {args.output}")
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    finally:
        # On failure, remove the staged file and preserve the previous output.
        # After a successful replacement, this path no longer exists.
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
