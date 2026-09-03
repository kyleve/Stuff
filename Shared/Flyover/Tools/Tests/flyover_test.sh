#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd -P)"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/flyover-command-tests.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT INT TERM

fail() {
    echo "flyover command test failed: $*" >&2
    exit 1
}

expect_failure() {
    if "$@" >"$TEMP/stdout" 2>"$TEMP/stderr"; then
        fail "command unexpectedly succeeded: $*"
    fi
}

SUCCESS_RUNNER="$TEMP/success-runner"
cat >"$SUCCESS_RUNNER" <<'RUNNER'
#!/bin/bash
set -euo pipefail
expected='WhereUISnapshotTests/WhereFlyoverWebExportTests/exportsRequestedAtlas()'
if [ "$#" -ne 2 ] || [ "${1-}" != --only ] || [ "${2-}" != "$expected" ]; then
    echo "unexpected capture runner arguments: $*" >&2
    exit 64
fi
python3 - <<'PY'
import json, os, pathlib
root = pathlib.Path(os.environ['FLYOVER_EXPORT_DIRECTORY'])
profiles = os.environ['FLYOVER_EXPORT_PROFILES'].split(',')
images = []
paths = {}
for index, profile in enumerate(profiles, 1):
    relative = f'images/screen-0001/variant-0001/{profile}.png'
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b'PNG')
    paths[profile] = relative
    images.append({'screenID': 'screen', 'variantID': 'default', 'profileID': profile,
                   'relativePath': relative, 'pointWidth': 1, 'pointHeight': 1,
                   'pixelWidth': 3, 'pixelHeight': 3, 'scale': 3,
                   'captureExtent': 'viewport'})
manifest = {
    'schemaVersion': 1,
    'application': {'id': 'where', 'title': 'Where'},
    'build': {'dirty': os.environ.get('FLYOVER_EXPORT_DIRTY') == 'true'},
    'profiles': [{'id': profile} for profile in profiles],
    'canvas': {},
    'groups': [],
    'screens': [{'id': 'screen', 'variants': [{'id': 'default', 'imagesByProfile': paths}]}],
    'routes': [],
    'images': images,
}
data = json.dumps(manifest, sort_keys=True, indent=2)
(root / 'manifest.json').write_text(data)
(root / 'manifest.js').write_text('window.FLYOVER_MANIFEST = ' + data + ';\n')
PY
if [ -n "${FLYOVER_RACE_DESTINATION:-}" ]; then
    mkdir -p "$FLYOVER_RACE_DESTINATION"
    printf '%s\n' retained >"$FLYOVER_RACE_DESTINATION/retained"
fi
if [ -n "${FLYOVER_RACE_SYMLINK_DESTINATION:-}" ]; then
    ln -s "$FLYOVER_RACE_SYMLINK_DESTINATION.missing" "$FLYOVER_RACE_SYMLINK_DESTINATION"
fi
RUNNER
chmod +x "$SUCCESS_RUNNER"

FAILURE_RUNNER="$TEMP/failure-runner"
cat >"$FAILURE_RUNNER" <<'RUNNER'
#!/bin/bash
exit 19
RUNNER
chmod +x "$FAILURE_RUNNER"

"$ROOT/flyover" --help | grep -q 'flyover export' || fail "help text is incomplete"
expect_failure "$ROOT/flyover" export --profile system
grep -q "unknown profile" "$TEMP/stderr" || fail "unknown profile error is unclear"
expect_failure "$ROOT/flyover" export --output
expect_failure "$ROOT/flyover" export --profile
expect_failure "$ROOT/flyover" export --output /
expect_failure "$ROOT/flyover" export --output "$HOME"
expect_failure "$ROOT/flyover" export --output "$ROOT"

ln -s / "$TEMP/root-alias"
expect_failure "$ROOT/flyover" export --output "$TEMP/root-alias"
grep -q "filesystem root" "$TEMP/stderr" || fail "root alias was not rejected as root"
ln -s "$HOME" "$TEMP/home-alias"
expect_failure "$ROOT/flyover" export --output "$TEMP/home-alias"
grep -q "home directory" "$TEMP/stderr" || fail "home alias was not rejected as home"
ln -s "$ROOT" "$TEMP/workspace-alias"
expect_failure "$ROOT/flyover" export --output "$TEMP/workspace-alias"
grep -q "workspace root" "$TEMP/stderr" || fail "workspace alias was not rejected as workspace"

UNMARKED="$TEMP/unmarked"
mkdir -p "$UNMARKED"
expect_failure env FLYOVER_CAPTURE_RUNNER="$SUCCESS_RUNNER" \
    FLYOVER_XCODE_VERSION_OVERRIDE=Tests "$ROOT/flyover" export --output "$UNMARKED"
grep -q "unmarked" "$TEMP/stderr" || fail "unmarked-directory error is unclear"

RACED="$TEMP/raced"
expect_failure env FLYOVER_CAPTURE_RUNNER="$SUCCESS_RUNNER" \
    FLYOVER_XCODE_VERSION_OVERRIDE=Tests FLYOVER_RACE_DESTINATION="$RACED" \
    "$ROOT/flyover" export --output "$RACED"
grep -q "unmarked" "$TEMP/stderr" || fail "publish-time destination change was not rejected"
[ -f "$RACED/retained" ] || fail "publish-time destination change was deleted"

RACED_SYMLINK="$TEMP/raced-symlink"
expect_failure env FLYOVER_CAPTURE_RUNNER="$SUCCESS_RUNNER" \
    FLYOVER_XCODE_VERSION_OVERRIDE=Tests \
    FLYOVER_RACE_SYMLINK_DESTINATION="$RACED_SYMLINK" \
    "$ROOT/flyover" export --output "$RACED_SYMLINK"
grep -q "non-directory" "$TEMP/stderr" \
    || fail "publish-time dangling symlink was not rejected"
[ -L "$RACED_SYMLINK" ] || fail "publish-time dangling symlink was deleted"

CALLER="$TEMP/caller"
mkdir -p "$CALLER"
(
    cd "$CALLER"
    FLYOVER_CAPTURE_RUNNER="$SUCCESS_RUNNER" FLYOVER_XCODE_VERSION_OVERRIDE=Tests \
        "$ROOT/flyover" export >/dev/null
)
[ -f "$CALLER/.build/flyover/where/.flyover-generated" ] \
    || fail "default output path did not resolve from the caller directory"

OUTPUT="$TEMP/output"
FLYOVER_CAPTURE_RUNNER="$SUCCESS_RUNNER" FLYOVER_XCODE_VERSION_OVERRIDE=Tests \
    "$ROOT/flyover" export --output "$OUTPUT" \
    --profile phone-dark --profile phone-light --profile phone-dark >/dev/null
python3 - "$OUTPUT" <<'PY'
import json, pathlib, stat, sys
root = pathlib.Path(sys.argv[1])
profiles = [item['id'] for item in json.loads((root / 'manifest.json').read_text())['profiles']]
if profiles != ['phone-dark', 'phone-light']:
    raise SystemExit(f'profile order or deduplication is wrong: {profiles}')
bad_directories = [path for path in [root, *root.rglob('*')]
                   if path.is_dir() and stat.S_IMODE(path.stat().st_mode) != 0o755]
bad_files = [path for path in root.rglob('*')
             if path.is_file() and stat.S_IMODE(path.stat().st_mode) != 0o644]
if bad_directories or bad_files:
    raise SystemExit(f'unsafe published modes: directories={bad_directories}, files={bad_files}')
PY

CLEAN_REPO="$TEMP/clean-repo"
mkdir -p "$CLEAN_REPO/Shared/Flyover/Web/assets"
cp "$ROOT/flyover" "$CLEAN_REPO/flyover"
cp "$ROOT/Shared/Flyover/Web/index.html" "$CLEAN_REPO/Shared/Flyover/Web/index.html"
cp "$ROOT/Shared/Flyover/Web/assets/app.js" "$CLEAN_REPO/Shared/Flyover/Web/assets/app.js"
cp "$ROOT/Shared/Flyover/Web/assets/styles.css" "$CLEAN_REPO/Shared/Flyover/Web/assets/styles.css"
chmod +x "$CLEAN_REPO/flyover"
git -C "$CLEAN_REPO" init -q
git -C "$CLEAN_REPO" add .
git -C "$CLEAN_REPO" -c user.name=Flyover -c user.email=flyover@example.com \
    -c commit.gpgsign=false commit -qm fixture
FLYOVER_CAPTURE_RUNNER="$SUCCESS_RUNNER" FLYOVER_XCODE_VERSION_OVERRIDE=Tests \
    "$CLEAN_REPO/flyover" export --output "$CLEAN_REPO/site" >/dev/null
python3 - "$CLEAN_REPO/site/manifest.json" <<'PY'
import json, pathlib, sys
dirty = json.loads(pathlib.Path(sys.argv[1]).read_text())['build']['dirty']
if dirty:
    raise SystemExit('staging a clean in-repository export marked the source dirty')
PY

printf '%s\n' old >"$OUTPUT/old-file"
FLYOVER_CAPTURE_RUNNER="$SUCCESS_RUNNER" FLYOVER_XCODE_VERSION_OVERRIDE=Tests \
    "$ROOT/flyover" export --output "$OUTPUT" >/dev/null
[ ! -e "$OUTPUT/old-file" ] || fail "a marked directory was not replaced"

printf '%s\n' retained >"$OUTPUT/retained"
expect_failure env FLYOVER_CAPTURE_RUNNER="$FAILURE_RUNNER" \
    FLYOVER_XCODE_VERSION_OVERRIDE=Tests "$ROOT/flyover" export --output "$OUTPUT"
[ -f "$OUTPUT/retained" ] || fail "a failed export replaced the last successful output"
if find "$TEMP" -maxdepth 1 -name '.flyover-staging.*' | grep -q .; then
    fail "a failed export left a staging directory"
fi

if grep -R -E 'fetch\(|https?://' "$ROOT/Shared/Flyover/Web" \
    | grep -v 'http://www.w3.org/2000/svg' >/dev/null; then
    fail "the web shell contains a network dependency"
fi
