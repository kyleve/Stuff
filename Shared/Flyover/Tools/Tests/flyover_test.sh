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
    'build': {},
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

UNMARKED="$TEMP/unmarked"
mkdir -p "$UNMARKED"
expect_failure env FLYOVER_CAPTURE_RUNNER="$SUCCESS_RUNNER" \
    FLYOVER_XCODE_VERSION_OVERRIDE=Tests "$ROOT/flyover" export --output "$UNMARKED"
grep -q "unmarked" "$TEMP/stderr" || fail "unmarked-directory error is unclear"

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
python3 - "$OUTPUT/manifest.json" <<'PY'
import json, pathlib, sys
profiles = [item['id'] for item in json.loads(pathlib.Path(sys.argv[1]).read_text())['profiles']]
if profiles != ['phone-dark', 'phone-light']:
    raise SystemExit(f'profile order or deduplication is wrong: {profiles}')
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
