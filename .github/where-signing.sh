#!/bin/bash
# Prepare and remove Where's temporary signing material on an isolated macOS runner.
# Run from the repository root. Account setup is in Where/DISTRIBUTION.md.
#
# Lifecycle: prepare, run Where/archive with "$WHERE_SIGNING_DIR/profiles", cleanup.
# The caller must run cleanup even if prepare or the archive fails. In GitHub
# Actions, use an `if: always()` cleanup step with the same WHERE_SIGNING_DIR.
# Cleanup needs no signing secrets and can retry after a partial failure.
#
# Both commands require RUNNER_TEMP and WHERE_SIGNING_DIR. The state path must
# start with "$RUNNER_TEMP/where-signing-" and must not exist before prepare.
# Prepare also requires the certificate, its password, and three profile secrets
# listed below. It decodes the profiles, validates them through where_signing.py,
# imports the certificate into a temporary keychain, and installs the profiles.
#
# The state directory records the prior keychain search list and every installed
# profile path. Cleanup restores that list and removes only this run's material.
# If any cleanup step fails, the state remains available for diagnosis and retry.
# Do not enable shell tracing: commands receive certificate and keychain passwords.

# Fail on command errors, unset variables, or a failed command within a pipeline.
set -euo pipefail
# Restrict newly created files and directories to the runner's user account.
umask 077

if [ "${1:-}" != prepare ] && [ "${1:-}" != cleanup ]; then
    echo "Usage: .github/where-signing.sh prepare|cleanup" >&2
    exit 1
fi
state="${WHERE_SIGNING_DIR:?WHERE_SIGNING_DIR is required}"
case "$state" in
    "${RUNNER_TEMP:?RUNNER_TEMP is required}"/where-signing-*) ;;
    *) echo "error: signing directory must be inside RUNNER_TEMP" >&2; exit 1 ;;
esac

if [ "$1" = cleanup ]; then
    # Preparation can stop before it creates state. Missing state needs no cleanup.
    [ -d "$state" ] || exit 0
    # The marker identifies directories this helper created. Reject symlinked state.
    if [ ! -f "$state/owned-by-where-signing" ] || [ -L "$state" ]; then
        echo "error: refusing to clean an unowned signing directory" >&2
        exit 1
    fi
    status=0
    if [ -f "$state/original-keychains" ]; then
        # Bash arrays preserve paths with spaces as separate security arguments.
        security_args=(list-keychains -d user -s)
        while IFS= read -r keychain; do security_args+=("$keychain"); done <"$state/original-keychains"
        security "${security_args[@]}" || status=1
    fi
    if [ -f "$state/signing.keychain-db" ]; then
        security delete-keychain "$state/signing.keychain-db" || status=1
    fi
    if [ -f "$state/installed-profiles" ]; then
        while IFS= read -r profile; do rm -f "$profile" || status=1; done <"$state/installed-profiles"
    fi
    if [ "$status" -ne 0 ]; then
        # Keep the recovery records unless every cleanup operation succeeds.
        echo "error: signing cleanup failed. Recovery files remain in $state" >&2
        exit "$status"
    fi
    rm -rf "$state"
    exit 0
fi

# Validate all required secrets before creating files or changing keychain state.
: "${WHERE_DISTRIBUTION_CERTIFICATE_BASE64:?Missing distribution certificate}"
: "${WHERE_DISTRIBUTION_CERTIFICATE_PASSWORD:?Missing certificate password}"
: "${WHERE_APP_PROFILE_BASE64:?Missing app profile}"
: "${WHERE_WIDGET_PROFILE_BASE64:?Missing widget profile}"
: "${WHERE_SHARE_PROFILE_BASE64:?Missing share-extension profile}"
if [ -e "$state" ] || [ -L "$state" ]; then
    echo "error: signing directory already exists" >&2
    exit 1
fi
mkdir "$state"
touch "$state/owned-by-where-signing"
mkdir "$state/profiles" "$state/decoded"
printf '%s' "$WHERE_DISTRIBUTION_CERTIFICATE_BASE64" | base64 --decode >"$state/certificate.p12"
for target in Where WhereWidgets WhereShareExtension; do
    case "$target" in
        Where) encoded="$WHERE_APP_PROFILE_BASE64" ;;
        WhereWidgets) encoded="$WHERE_WIDGET_PROFILE_BASE64" ;;
        WhereShareExtension) encoded="$WHERE_SHARE_PROFILE_BASE64" ;;
    esac
    printf '%s' "$encoded" | base64 --decode >"$state/profiles/$target.mobileprovision"
    security cms -D -i "$state/profiles/$target.mobileprovision" >"$state/decoded/$target.plist"
done
python3 Tools/where_signing.py prepare --profiles "$state/decoded" --output "$state/plan"

# Publish the saved search list only after security and parsing both succeed.
# Cleanup must never restore an incomplete list from a failed pipeline.
security list-keychains -d user | python3 -c 'import shlex,sys; sys.stdout.write("".join(path + "\n" for path in shlex.split(sys.stdin.read())))' \
    >"$state/original-keychains.pending"
mv "$state/original-keychains.pending" "$state/original-keychains"
security_args=(list-keychains -d user -s "$state/signing.keychain-db")
while IFS= read -r keychain; do security_args+=("$keychain"); done <"$state/original-keychains"
# Give this run its own keychain password and allow unattended Apple signing tools.
password="$(openssl rand -hex 32)"
security create-keychain -p "$password" "$state/signing.keychain-db"
security set-keychain-settings -lut 7200 "$state/signing.keychain-db"
security unlock-keychain -p "$password" "$state/signing.keychain-db"
security import "$state/certificate.p12" -P "$WHERE_DISTRIBUTION_CERTIFICATE_PASSWORD" \
    -k "$state/signing.keychain-db" -t cert -f pkcs12 -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$password" \
    "$state/signing.keychain-db" >/dev/null
security "${security_args[@]}"

profile_root="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$profile_root"
for target in Where WhereWidgets WhereShareExtension; do
    destination="$profile_root/$(basename "$state")-$target.mobileprovision"
    if [ -e "$destination" ] || [ -L "$destination" ]; then
        echo "error: refusing to replace an existing provisioning profile" >&2
        exit 1
    fi
    # Record ownership before copying so cleanup can remove a partial copy too.
    printf '%s\n' "$destination" >>"$state/installed-profiles"
    cp "$state/profiles/$target.mobileprovision" "$destination"
done
