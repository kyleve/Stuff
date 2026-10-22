"""Run Astro with the deterministic catalogs used by the install-site snapshots."""

import argparse
from pathlib import Path
import subprocess
import sys
import tempfile

from Tools.InstallerKit.installer_site_data import prepare_site
from Tools.InstallerKit.installer_update_site import ASTRO_ROOT, BUILD_ROOT, build_astro, stage_input
from Tools.astro_site import astro_command

from Tools.Tests.Fixtures.installer_update_fixtures import site_scenarios, FEED_URL, REPO


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("dev", "preview"))
    parser.add_argument("--fixture", choices=site_scenarios(), default="full")
    parser.add_argument("--port", type=int, default=4321)
    args = parser.parse_args(argv)
    if not 1 <= args.port <= 65535:
        parser.error("--port must be between 1 and 65535")
    try:
        prepared = prepare_site(site_scenarios()[args.fixture], REPO, FEED_URL)
        BUILD_ROOT.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="preview-", dir=BUILD_ROOT) as temporary:
            workspace = Path(temporary)
            environment = stage_input(prepared, workspace)
            output = workspace / "site"
            if args.mode == "preview":
                build_astro(environment, output)
            print(f"Fixture: {args.fixture}. Preview: http://localhost:{args.port}{prepared.data['basePath']}", flush=True)
            print("Install links use synthetic fixture releases.", flush=True)
            # Keep the server in the foreground: these inputs live only for this process.
            # Each invocation already has an isolated root, so no shared lock is needed.
            result = subprocess.run(astro_command(ASTRO_ROOT, workspace, args.mode, "--ignore-lock", "--port", str(args.port),
                                                 "--outDir", str(output)),
                                    cwd=ASTRO_ROOT, env=environment)
            return result.returncode if result.returncode >= 0 else 128 - result.returncode
    except KeyboardInterrupt:
        return 130
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
