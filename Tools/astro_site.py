"""Pinned Astro execution shared by repository websites; no publication policy."""

import os
from pathlib import Path
import shutil

from Tools.repository import repository_root

SOURCE_ROOT = repository_root(__file__)
SYSTEM_MISE_PATHS = (Path("/opt/homebrew/bin/mise"), Path("/usr/local/bin/mise"))


def resolve_mise():
    """Find executable mise installations without requiring an interactive shell."""
    mise = shutil.which("mise")
    if mise is not None:
        return mise
    home = Path.home()
    data_home = Path(os.environ.get("XDG_DATA_HOME") or home / ".local/share")
    data_directory = Path(os.environ.get("MISE_DATA_DIR") or data_home / "mise")
    # mise-action installs its executable alongside the managed tools.
    candidates = (data_directory / "bin/mise", home / ".local/bin/mise", *SYSTEM_MISE_PATHS)
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    raise ValueError("mise is required to build static websites. Run ./ide --bootstrap --no-open.")


def astro_command(site, workspace, *arguments):
    """Run a site's Astro configuration with the repository's locked toolchain."""
    entry = SOURCE_ROOT / "node_modules/.bin/astro"
    if not entry.is_file():
        raise ValueError("Install the web dependencies: mise exec -- npm ci")
    return [resolve_mise(), "exec", "node", "--", "node", str(entry), *arguments,
            "--root", str(workspace), "--config", os.path.relpath(site / "astro.config.mjs", workspace)]


def stage_workspace(site, workspace):
    """Isolate generated Astro state while sharing read-only installed dependencies."""
    (workspace / "node_modules").symlink_to(SOURCE_ROOT / "node_modules")
    for name in ("package.json", "tsconfig.json"):
        (workspace / name).symlink_to(site / name)
