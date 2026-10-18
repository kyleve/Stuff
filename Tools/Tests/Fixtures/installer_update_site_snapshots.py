"""Generate offline HTML fixtures with the production install-site renderer."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from installer_update_site import render_site
from Fixtures.installer_update_fixtures import catalog, multiple_apps, FEED_URL, REPO


def offline_html(files, path):
    """Inline the exact generated assets so WebKit captures need no network."""
    html = files[path].decode()
    root = FEED_URL[:-len("updates.json")]
    for relative, contents in files.items():
        if relative.startswith("assets/"):
            html = html.replace(root + relative, "data:image/png;base64," + base64.b64encode(contents).decode())
    return html


def pages():
    value = multiple_apps()
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
    rendered = render_site(value, REPO, FEED_URL)
    result = [{"name": "Index", "html": offline_html(rendered, "index.html")},
              {"name": "App", "html": offline_html(rendered, "apps/where/index.html")},
              {"name": "Channel", "html": offline_html(rendered, "apps/where/pr-42/index.html")}]
    value["apps"][0]["channels"][1]["releases"][0]["historyChanged"] = True
    result.append({"name": "UnavailableHistory", "html": offline_html(render_site(value, REPO, FEED_URL),
        "apps/where/pr-42/index.html")})
    value["apps"][0]["channels"][1]["active"] = False
    result.append({"name": "Retired", "html": offline_html(render_site(value, REPO, FEED_URL),
        "apps/where/pr-42/index.html")})
    result.append({"name": "Empty", "html": render_site(
        {"schemaVersion": 3, "apps": []}, REPO, FEED_URL)["index.html"].decode()})
    legacy = catalog("example", "Example Development With a Longer Name", "com.example.development")
    legacy["apps"][0]["channels"] = legacy["apps"][0]["channels"][1:]
    for release in legacy["apps"][0]["channels"][0]["releases"]:
        del release["buildDetails"]
    result.append({"name": "MissingDetails", "html": offline_html(render_site(legacy, REPO, FEED_URL),
        "apps/example/pr-42/index.html")})
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    temporary = None
    try:
        content = json.dumps(pages(), ensure_ascii=False).encode()
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=args.output.parent, delete=False) as destination:
            temporary = Path(destination.name)
            destination.write(content)
        os.replace(temporary, args.output)
        print(f"Generated install-site snapshot fixtures: {args.output}")
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
