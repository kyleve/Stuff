#!/bin/bash
# Run after Info.plist processing and before signing, with dependency analysis off.
set -euo pipefail

plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
sha=$(git -C "$SRCROOT" rev-parse HEAD 2>/dev/null || echo unknown)
status=unknown
if [[ "$sha" != unknown ]] && porcelain=$(git -C "$SRCROOT" status --porcelain 2>/dev/null); then
    if [[ -z "$porcelain" ]]; then status=clean; else status=dirty; fi
fi

set_key() {
    /usr/libexec/PlistBuddy -c "Set :$1 $2" "$plist" 2>/dev/null ||
        /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$plist"
}

set_key InstallerAppID "${INSTALLER_APP_ID:-unknown}"
set_key InstallerChannel "${INSTALLER_CHANNEL:-unknown}"
set_key InstallerRun "${INSTALLER_RUN:-unknown}"
set_key InstallerAttempt "${INSTALLER_ATTEMPT:-unknown}"
set_key InstallerFeedURL "${INSTALLER_FEED_URL:-unknown}"
set_key InstallerRepositoryURL "${INSTALLER_REPOSITORY_URL:-unknown}"
set_key InstallerGitSHA "$sha"
set_key InstallerGitStatus "$status"
