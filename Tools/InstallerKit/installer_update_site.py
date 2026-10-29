"""Build the Astro install site, OTA manifests, and catalog as one Pages deployment."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from Tools.InstallerKit.installer_site_data import prepare_site
from Tools.InstallerKit.installer_update_feed import GitHubUpdateFeed
from Tools.repository import repository_root
from Tools.astro_site import astro_command as site_command, stage_workspace


SOURCE_ROOT = repository_root(__file__)
ASTRO_ROOT = SOURCE_ROOT / "Tools/InstallerKit/Site"
BUILD_ROOT = ASTRO_ROOT / ".build"


def stage_input(prepared, workspace):
    """Keep each build's catalog and public assets isolated from other invocations."""
    public = workspace / "public"
    public.mkdir()
    for relative, contents in prepared.files.items():
        target = public / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(contents)
    data = workspace / "site.json"
    data.write_text(json.dumps(prepared.data, ensure_ascii=False))
    # Astro's generated .astro directory follows root, independently of cacheDir.
    # Isolate it so dev previews and snapshot builds can run at the same time.
    stage_workspace(ASTRO_ROOT, workspace)
    return {
        **os.environ,
        "ASTRO_TELEMETRY_DISABLED": "1",
        "INSTALLER_SITE_DATA": str(data),
        "INSTALLER_SITE_PUBLIC": str(public),
        "INSTALLER_SITE_WORKSPACE": str(workspace),
        "INSTALLER_SITE_CACHE": str(workspace / "cache"),
    }


def build_astro(environment, output):
    result = subprocess.run(
        site_command(
            ASTRO_ROOT,
            environment["INSTALLER_SITE_WORKSPACE"],
            "build",
            "--outDir",
            str(output),
        ),
        cwd=ASTRO_ROOT,
        env=environment,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise ValueError(
            f"Astro build failed (exit {result.returncode}):\n{result.stdout}{result.stderr}"
        )


def render_site(catalog, repository, feed_url, registered_apps=None):
    prepared = prepare_site(catalog, repository, feed_url, registered_apps)
    # Astro stages prerendering in cwd/.astro when outDir is outside cwd.
    # Keep output inside the project so each invocation owns that staging too.
    BUILD_ROOT.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="render-", dir=BUILD_ROOT) as temporary:
        workspace = Path(temporary)
        environment = stage_input(prepared, workspace)
        output = workspace / "site"
        build_astro(environment, output)
        return {
            str(path.relative_to(output)): path.read_bytes()
            for path in output.rglob("*")
            if path.is_file()
        }


def write_site(files, output):
    if output.exists():
        raise ValueError("Pages output directory must not exist")
    # The complete artifact is validated and staged before its single rename.
    with tempfile.TemporaryDirectory(
        prefix="installer-pages-", dir=output.parent
    ) as temporary:
        staging = Path(temporary) / "site"
        staging.mkdir()
        for relative, contents in files.items():
            target = staging / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(contents)
        os.rename(staging, output)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--catalog", type=Path, help="Read a local catalog")
    source.add_argument(
        "--published-catalog",
        action="store_true",
        help="Read the GitHub catalog, or use an empty catalog before the first publication",
    )
    parser.add_argument("--repository", required=True)
    parser.add_argument("--feed-url", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.output.exists():
            raise ValueError("Pages output directory must not exist")
        if args.published_catalog:
            feed = GitHubUpdateFeed(args.repository, os.environ.get("GH_TOKEN", ""))
            catalog = feed.load_for_deployment()
        else:
            catalog = json.loads(args.catalog.read_text())
        files = render_site(catalog, args.repository, args.feed_url)
        write_site(files, args.output)
        print(f"Prepared {len(files)} Pages files in {args.output}")
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
