#!/bin/bash
# Temporary signing material for an isolated GitHub Actions macOS runner.
set -euo pipefail
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
    [ -d "$state" ] || exit 0
    if [ ! -f "$state/owned-by-where-signing" ] || [ -L "$state" ]; then
        echo "error: refusing to clean an unowned signing directory" >&2
        exit 1
    fi
    status=0
    if [ -f "$state/original-keychains" ]; then
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
        echo "error: signing cleanup failed. Recovery files remain in $state" >&2
        exit "$status"
    fi
    rm -rf "$state"
    exit 0
fi

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

security list-keychains -d user | python3 -c 'import shlex,sys; sys.stdout.write("".join(path + "\n" for path in shlex.split(sys.stdin.read())))' \
    >"$state/original-keychains.pending"
mv "$state/original-keychains.pending" "$state/original-keychains"
security_args=(list-keychains -d user -s "$state/signing.keychain-db")
while IFS= read -r keychain; do security_args+=("$keychain"); done <"$state/original-keychains"
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
    printf '%s\n' "$destination" >>"$state/installed-profiles"
    cp "$state/profiles/$target.mobileprovision" "$destination"
done
