#!/bin/bash
# CircleCI always runs cleanup, including after a partial prepare failure.
set -euo pipefail
umask 077
root="$(cd "$(dirname "$0")/.." && pwd)"
# Usage and runner guards must also work when tool setup failed.
if [ "$#" -ne 1 ] || { [ "$1" != prepare ] && [ "$1" != cleanup ]; }; then
    echo 'Usage: .github/installer-signing.sh prepare|cleanup' >&2
    exit 1
fi
if [ "${CIRCLECI:-}" != true ]; then
    echo 'error: Temporary signing is restricted to CircleCI isolated runners' >&2
    exit 1
fi
# No material exists when setup failed before prepare; cleanup needs no runtime.
if [ "$1" = cleanup ] && [ -n "${INSTALLER_SIGNING_DIR:-}" ] &&
    [ ! -e "$INSTALLER_SIGNING_DIR" ] && [ ! -L "$INSTALLER_SIGNING_DIR" ]; then
    exit 0
fi
cd "$root"
# Use the same locked bundle as the trusted archive workflow.
export BUNDLE_GEMFILE="$root/Gemfile"
export BUNDLE_PATH="$root/vendor/bundle"
export BUNDLE_FROZEN=true
exec mise exec -- bundle exec ruby "$root/Tools/InstallerKit/signing_state.rb" "$@"
