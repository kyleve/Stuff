#!/bin/bash
#
# Stamps how the app was built into the built product's Info.plist: the commit
# it came from, and how the Swift compiler was invoked. Read back by
# `WhereCore.BuildInfo` for the Settings > About screen and for the attributes
# on every Periscope logging session.
#
# Runs as a post-build script phase on the `Where` target — after "Process
# Info.plist" writes the file and before code signing seals the bundle — with
# dependency analysis off so it re-runs on every build rather than caching a
# stale SHA. Only the app is stamped; the extensions never read these keys.
#
# A checkout without git metadata (an exported tarball, a sandboxed script
# phase) is not a failure: the keys are still written, marked `unknown`, and the
# About screen says so rather than showing an invented commit. The compiler
# keys get the same treatment via `${VAR:-unknown}` — `set -u` would otherwise
# abort the build over a build setting Xcode happened not to export.

set -euo pipefail

plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"

sha=$(git -C "$SRCROOT" rev-parse --short=12 HEAD 2>/dev/null || echo "")
if [ -z "$sha" ]; then
    sha="unknown"
    status="unknown"
elif [ -n "$(git -C "$SRCROOT" status --porcelain 2>/dev/null)" ]; then
    status="dirty"
else
    status="clean"
fi

set_key() {
    /usr/libexec/PlistBuddy -c "Set :$1 $2" "$plist" 2>/dev/null ||
        /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$plist"
}

set_key WhereGitSHA "$sha"
set_key WhereGitStatus "$status"

# How the Swift compiler was invoked. `SWIFT_OPTIMIZATION_LEVEL` is the one
# that decides whether a recorded span duration says anything about a shipping
# build; the configuration alone can't answer it, since a Debug configuration
# can be compiled with `-O`.
set_key WhereConfiguration "${CONFIGURATION:-unknown}"
set_key WhereSwiftOptimizationLevel "${SWIFT_OPTIMIZATION_LEVEL:-unknown}"
set_key WhereSwiftCompilationMode "${SWIFT_COMPILATION_MODE:-unknown}"
