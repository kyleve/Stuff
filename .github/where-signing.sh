#!/bin/bash
# CircleCI always runs cleanup, including after a partial prepare failure.
set -euo pipefail
umask 077
root="$(cd "$(dirname "$0")/.." && pwd)"
# Usage and runner guards must also work when tool setup failed.
if [ "$#" -ne 1 ] || { [ "$1" != prepare ] && [ "$1" != cleanup ]; }; then
    echo 'Usage: .github/where-signing.sh prepare|cleanup' >&2
    exit 1
fi
if [ "${CIRCLECI:-}" != true ]; then
    echo 'error: Temporary signing is restricted to CircleCI isolated runners' >&2
    exit 1
fi
# No material exists when setup failed before prepare; cleanup needs no runtime.
if [ "$1" = cleanup ] && [ -n "${WHERE_SIGNING_DIR:-}" ] &&
    [ ! -e "$WHERE_SIGNING_DIR" ] && [ ! -L "$WHERE_SIGNING_DIR" ]; then
    exit 0
fi
cd "$root"
# The lifecycle helper uses only the standard library, so Bundler is unnecessary.
exec mise exec -- ruby "$root/Tools/InstallerKit/signing_state.rb" "$@"
