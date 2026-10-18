"""Build the offline pages that ToolsSnapshotTests captures in WebKit.

Project.swift runs this module before it builds the snapshot bundle:
    python3 -m Tools.Tests.Fixtures.installer_update_site_snapshots --output <file>

The input is synthetic catalogs from installer_update_fixtures.site_scenarios(). The production
Astro renderer turns each catalog into the HTML, CSS, and artwork that Pages publishes.
This module embeds CSS and artwork so WebKit needs no server or network.

The output is a JSON array of {"name": ..., "html": ...} objects.
InstallerSiteSnapshotTests.swift uses each name as a snapshot reference identifier.
It captures each page on iPhone and iPad in light and dark appearances.
Keep these names stable unless the matching reference images also change.
"""

import argparse
import base64
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import sys
import tempfile
from urllib.parse import urlsplit

from Tools.InstallerKit.installer_update_site import render_site
from Tools.Tests.Fixtures.installer_update_fixtures import site_scenarios, FEED_URL, REPO


class OfflineAssets(HTMLParser):
    """Inline built CSS and artwork without changing the production DOM or layout."""

    def __init__(self, files):
        super().__init__()
        self.files = files
        self.replacements = {}

    def asset(self, url):
        """Resolve a published URL to bytes in render_site's output-path mapping."""
        base = urlsplit(FEED_URL).path.removesuffix("updates.json")
        if not url.startswith(base):
            raise ValueError(f"Snapshot asset is outside the site: {url}")
        return self.files[url[len(base):]]

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        original = self.get_starttag_text()
        # Replace asset tags only. Navigation and install links keep their URLs.
        if tag == "link" and attrs.get("rel") == "stylesheet":
            css = self.asset(attrs["href"]).decode()
            # Fail if CSS gains an external image/font that is not embedded.
            if "url(" in css:
                raise ValueError("Snapshot CSS assets must be inlined before capture")
            self.replacements[original] = "<style>" + css + "</style>"
        elif tag in ("img", "source"):
            key = "src" if tag == "img" else "srcset"
            url = attrs[key]
            # Base64 embeds the exact artwork bytes without changing pixels.
            data = "data:image/png;base64," + base64.b64encode(self.asset(url)).decode()
            self.replacements[original] = original.replace(url, data)


def offline_html(files, path):
    """Make one production page self-contained while preserving its DOM and CSS."""
    html = files[path].decode()
    assets = OfflineAssets(files)
    assets.feed(html)
    for original, replacement in assets.replacements.items():
        html = html.replace(original, replacement)
    return html


def pages():
    """Select seven named pages from the five shared synthetic catalog states.

    The full state covers all three navigation levels and long release notes.
    Other states cover rewritten history, retirement, an empty catalog, and
    missing build metadata. The case names also name the LFS reference images.
    """
    cases = {
        "full": [("Index", "index.html"), ("App", "apps/where/index.html"), ("Channel", "apps/where/pr-42/index.html")],
        "unavailable-history": [("UnavailableHistory", "apps/where/pr-42/index.html")],
        "retired": [("Retired", "apps/where/pr-42/index.html")],
        "empty": [("Empty", "index.html")],
        "missing-details": [("MissingDetails", "apps/example/pr-42/index.html")],
    }
    result = []
    for name, catalog in site_scenarios().items():
        # Build once per catalog, then select its relevant output paths.
        files = render_site(catalog, REPO, FEED_URL)
        result.extend({"name": title, "html": offline_html(files, path)} for title, path in cases[name])
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
