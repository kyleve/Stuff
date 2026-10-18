#!/bin/bash
# CircleCI always runs cleanup, including after a partial prepare failure.
set -euo pipefail
umask 077
root="$(cd "$(dirname "$0")/.." && pwd)"
exec /usr/bin/ruby "$root/Tools/InstallerKit/signing_state.rb" "$@"
