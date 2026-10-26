#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd -P)"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/flyover-command-tests.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT INT TERM

# Build the production shell once; repeated command transactions use those exact files.
mkdir -p "$TEMP/web-shell"
(cd "$ROOT" && python3 -m Tools.flyover_site build "$TEMP/web-shell")
export FLYOVER_TEST_WEB_SHELL="$TEMP/web-shell"
export FLYOVER_WEB_BUILD_RUNNER="$TEMP/web-builder"
cat >"$FLYOVER_WEB_BUILD_RUNNER" <<'BUILDER'
#!/bin/bash
set -euo pipefail
cp -R "$FLYOVER_TEST_WEB_SHELL/." "$1/"
BUILDER
chmod +x "$FLYOVER_WEB_BUILD_RUNNER"

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
    'build': {
        'commit': os.environ['FLYOVER_EXPORT_COMMIT'],
        'dirty': os.environ.get('FLYOVER_EXPORT_DIRTY') == 'true',
        'branch': os.environ.get('FLYOVER_EXPORT_BRANCH') or None,
        'generatedAt': os.environ['FLYOVER_EXPORT_GENERATED_AT'],
        'xcodeVersion': os.environ['FLYOVER_EXPORT_XCODE_VERSION'],
        'simulatorDevice': os.environ['FLYOVER_EXPORT_SIMULATOR_DEVICE'],
        'simulatorOS': os.environ['FLYOVER_EXPORT_SIMULATOR_OS'],
    },
    'profiles': [{
        'id': profile,
        'title': profile,
        'device': 'phone',
        'orientation': 'portrait',
        'colorScheme': 'dark' if profile == 'phone-dark' else 'light',
        'dynamicType': 'large',
        'contrast': 'standard',
        'layoutDirection': 'left-to-right',
        'legibilityWeight': 'regular',
        'snapshotType': 'standard',
    } for profile in profiles],
    'canvas': {
        'size': {'width': 500, 'height': 700},
        'initialFitSize': {'width': 500, 'height': 700},
        'groupFrames': [{
            'id': 'group',
            'frame': {'x': 0, 'y': 0, 'width': 500, 'height': 700},
        }],
        'depthBandFrames': [{
            'groupID': 'group',
            'kind': 'route',
            'depth': 0,
            'frame': {'x': 20, 'y': 20, 'width': 460, 'height': 660},
        }],
        'screenFrames': [{
            'id': 'screen',
            'frame': {'x': 50, 'y': 50, 'width': 300, 'height': 650},
        }],
        'connectors': [],
    },
    'groups': [{
        'id': 'group',
        'title': 'Group',
        'order': 0,
        'rootScreenID': 'screen',
        'screenIDs': ['screen'],
    }],
    'screens': [{
        'id': 'screen',
        'title': 'Screen',
        'groupID': 'group',
        'groupOrder': 0,
        'screenOrder': 0,
        'viewport': {'kind': 'device'},
        'navigationContainer': 'stack',
        'frame': {'x': 50, 'y': 50, 'width': 300, 'height': 650},
        'variants': [{
            'id': 'default',
            'title': 'Default',
            'captureExtent': 'viewport',
            'imagesByProfile': paths,
        }],
        'incomingRouteIDs': [],
        'outgoingRouteIDs': [],
    }],
    'routes': [],
    'images': images,
}
if os.environ.get('FLYOVER_INVALID_MANIFEST') == 'missing-application':
    del manifest['application']
data = json.dumps(manifest, sort_keys=True, indent=2)
(root / 'manifest.json').write_text(data)
PY
if [ -n "${FLYOVER_RACE_DESTINATION:-}" ]; then
    mkdir -p "$FLYOVER_RACE_DESTINATION"
    printf '%s\n' retained >"$FLYOVER_RACE_DESTINATION/retained"
fi
if [ -n "${FLYOVER_RACE_SYMLINK_DESTINATION:-}" ]; then
    ln -s "$FLYOVER_RACE_SYMLINK_DESTINATION.missing" "$FLYOVER_RACE_SYMLINK_DESTINATION"
fi
if [ -n "${FLYOVER_STALE_BACKUP_DESTINATION:-}" ]; then
    stale_parent="$(dirname "$FLYOVER_STALE_BACKUP_DESTINATION")"
    stale_name="$(basename "$FLYOVER_STALE_BACKUP_DESTINATION")"
    stale="$stale_parent/.flyover-previous.$stale_name.$PPID"
    mkdir -p "$stale"
    printf '%s\n' retained >"$stale/retained"
fi
RUNNER
chmod +x "$SUCCESS_RUNNER"

FAILURE_RUNNER="$TEMP/failure-runner"
cat >"$FAILURE_RUNNER" <<'RUNNER'
#!/bin/bash
exit 19
RUNNER
chmod +x "$FAILURE_RUNNER"

"$ROOT/flyover" --help | grep -q 'flyover export' || fail "export help is incomplete"
"$ROOT/flyover" --help | grep -q 'flyover preview' || fail "preview help is incomplete"
"$ROOT/flyover" export --help | grep -q 'phone-voiceover' \
    || fail "export help does not list the supported profiles"
"$ROOT/flyover" export --help | grep -q 'defaults are phone-light and phone-dark' \
    || fail "export help does not list both default profiles"
"$ROOT/flyover" preview --help | grep -q 'no authentication or TLS' \
    || fail "preview help does not explain LAN exposure"
expect_failure "$ROOT/flyover" export --profile system
grep -q "unknown profile" "$TEMP/stderr" || fail "unknown profile error is unclear"
expect_failure "$ROOT/flyover" export --output
expect_failure "$ROOT/flyover" export --profile
expect_failure "$ROOT/flyover" export --output /
expect_failure "$ROOT/flyover" export --output "$HOME"
expect_failure "$ROOT/flyover" export --output "$ROOT"
expect_failure "$ROOT/flyover" preview --output
expect_failure "$ROOT/flyover" preview --port
expect_failure "$ROOT/flyover" preview --port nope
expect_failure "$ROOT/flyover" preview --port -1
expect_failure "$ROOT/flyover" preview --port 65536
expect_failure "$ROOT/flyover" preview --profile phone-light
expect_failure "$ROOT/flyover" preview --output "$TEMP/missing"
grep -q "Run ./flyover export first" "$TEMP/stderr" \
    || fail "missing-preview error does not name the next action"
printf '%s\n' not-a-directory >"$TEMP/preview-file"
expect_failure "$ROOT/flyover" preview --output "$TEMP/preview-file"
grep -q "not a directory" "$TEMP/stderr" \
    || fail "preview-file error is unclear"

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

UNSUPPORTED_MARKER="$TEMP/unsupported-marker"
mkdir -p "$UNSUPPORTED_MARKER"
printf '%s\n' schemaVersion=2 >"$UNSUPPORTED_MARKER/.flyover-generated"
expect_failure env FLYOVER_CAPTURE_RUNNER="$SUCCESS_RUNNER" \
    FLYOVER_XCODE_VERSION_OVERRIDE=Tests \
    "$ROOT/flyover" export --output "$UNSUPPORTED_MARKER"
grep -q "unsupported marker" "$TEMP/stderr" \
    || fail "unsupported generated marker was not rejected"

SYMLINK_MARKER="$TEMP/symlink-marker"
mkdir -p "$SYMLINK_MARKER"
printf '%s\n' schemaVersion=1 >"$TEMP/marker-target"
ln -s "$TEMP/marker-target" "$SYMLINK_MARKER/.flyover-generated"
expect_failure env FLYOVER_CAPTURE_RUNNER="$SUCCESS_RUNNER" \
    FLYOVER_XCODE_VERSION_OVERRIDE=Tests "$ROOT/flyover" export --output "$SYMLINK_MARKER"
grep -q "symbolic-link marker" "$TEMP/stderr" \
    || fail "symbolic-link generated marker was not rejected"

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
python3 - "$CALLER/.build/flyover/where/manifest.json" <<'PY'
import json, pathlib, sys
manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
profiles = [item['id'] for item in manifest['profiles']]
if profiles != ['phone-light', 'phone-dark']:
    raise SystemExit(f'default profiles are wrong: {profiles}')
if len(manifest['images']) != 2:
    raise SystemExit(f'default image count is wrong: {len(manifest["images"])}')
PY

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

INTERRUPT_RUNNER="$TEMP/interrupt-runner"
cat >"$INTERRUPT_RUNNER" <<'RUNNER'
#!/bin/bash
set -euo pipefail
"$FLYOVER_SUCCESS_RUNNER" "$@"
kill -"$FLYOVER_TEST_SIGNAL" "$PPID"
RUNNER
chmod +x "$INTERRUPT_RUNNER"

# Replacement interruption is injected at os.rename in test_flyover_publication.
for signal_name in INT TERM; do
    expected_status=130
    [ "$signal_name" != TERM ] || expected_status=143
    phase=capture
    interrupted_parent="$TEMP/interrupted-$signal_name-$phase"
    mkdir -p "$interrupted_parent"
    interrupted_output="$interrupted_parent/atlas"
    cp -R "$OUTPUT" "$interrupted_output"
    if env FLYOVER_CAPTURE_RUNNER="$INTERRUPT_RUNNER" \
        FLYOVER_SUCCESS_RUNNER="$SUCCESS_RUNNER" FLYOVER_XCODE_VERSION_OVERRIDE=Tests \
        FLYOVER_TEST_SIGNAL="$signal_name" \
        "$ROOT/flyover" export --output "$interrupted_output" --profile phone-light \
        >"$TEMP/stdout" 2>"$TEMP/stderr"; then
        fail "$signal_name during $phase returned success"
    else
        actual_status=$?
    fi
    [ "$actual_status" -eq "$expected_status" ] \
        || fail "$signal_name during $phase returned $actual_status instead of $expected_status: $(< "$TEMP/stderr")"
    diff -r "$OUTPUT" "$interrupted_output" \
        || fail "$signal_name during $phase changed the previous artifact"
    [ "$(find "$interrupted_parent" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = 1 ] \
        || fail "$signal_name during $phase left staging or replacement output"
done

PREVIEW_ARGUMENTS="$TEMP/preview-arguments"
PREVIEW_ENVIRONMENT="$TEMP/preview-environment"
PREVIEW_RUNNER="$TEMP/preview-runner"
cat >"$PREVIEW_RUNNER" <<'RUNNER'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$@" >"$FLYOVER_PREVIEW_ARGUMENTS"
printf '%s\n' "${PYTHONDONTWRITEBYTECODE-}" >"$FLYOVER_PREVIEW_ENVIRONMENT"
RUNNER
chmod +x "$PREVIEW_RUNNER"
FLYOVER_PREVIEW_PYTHON="$PREVIEW_RUNNER" \
    FLYOVER_PREVIEW_ARGUMENTS="$PREVIEW_ARGUMENTS" \
    FLYOVER_PREVIEW_ENVIRONMENT="$PREVIEW_ENVIRONMENT" \
    "$ROOT/flyover" preview --output "$OUTPUT" --lan --port 8080
python3 - "$PREVIEW_ARGUMENTS" "$ROOT" "$OUTPUT" <<'PY'
import pathlib, sys
arguments = pathlib.Path(sys.argv[1]).read_text().splitlines()
expected = [
    '-m', 'Tools.flyover_site',
    'preview',
    str(pathlib.Path(sys.argv[3]).resolve()),
    '--port',
    '8080',
    '--lan',
]
if arguments != expected:
    raise SystemExit(f'preview runner arguments are wrong: {arguments}')
PY

(
    cd "$CALLER"
    FLYOVER_PREVIEW_PYTHON="$PREVIEW_RUNNER" \
        FLYOVER_PREVIEW_ARGUMENTS="$PREVIEW_ARGUMENTS" \
        FLYOVER_PREVIEW_ENVIRONMENT="$PREVIEW_ENVIRONMENT" \
        "$ROOT/flyover" preview --port 0
)
python3 - "$PREVIEW_ARGUMENTS" "$ROOT" "$CALLER/.build/flyover/where" <<'PY'
import pathlib, sys
arguments = pathlib.Path(sys.argv[1]).read_text().splitlines()
expected = [
    '-m', 'Tools.flyover_site',
    'preview',
    str(pathlib.Path(sys.argv[3]).resolve()),
    '--port',
    '0',
]
if arguments != expected:
    raise SystemExit(f'default preview arguments are wrong: {arguments}')
PY
[ "$(< "$PREVIEW_ENVIRONMENT")" = 1 ] \
    || fail "preview Python can write bytecode into the source tree"

expect_failure "$ROOT/flyover" preview --output "$UNMARKED"
grep -q "not a generated Flyover atlas" "$TEMP/stderr" \
    || fail "preview accepted an unmarked directory"

PREVIEW_WITH_SPACES="$TEMP/preview output"
cp -R "$OUTPUT" "$PREVIEW_WITH_SPACES"
python3 - "$ROOT/flyover" "$PREVIEW_WITH_SPACES" <<'PY'
import http.client
import os
import pathlib
import re
import selectors
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

command, directory = sys.argv[1:]
(pathlib.Path(directory) / 'http:' / 'remote.example').mkdir(parents=True)
(pathlib.Path(directory) / 'http:' / 'remote.example' / 'manifest.json').write_text(
    'not the atlas manifest'
)
process = subprocess.Popen(
    [command, 'preview', '--output', directory, '--port', '0'],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
assert process.stdout is not None
assert process.stderr is not None
selector = selectors.DefaultSelector()
selector.register(process.stdout, selectors.EVENT_READ)
selector.register(process.stderr, selectors.EVENT_READ)
chunks = []
deadline = time.monotonic() + 30
try:
    while time.monotonic() < deadline and b'http://127.0.0.1:' not in b''.join(chunks):
        for key, _ in selector.select(timeout=max(0, deadline - time.monotonic())):
            chunk = os.read(key.fileobj.fileno(), 4096)
            if chunk:
                chunks.append(chunk)
        if process.poll() is not None:
            break
    output = re.sub(r'\x1b\[[0-9;]*m', '', b''.join(chunks).decode(errors='replace'))
    match = re.search(r'Local\s+(http://127\.0\.0\.1:\d+/)', output, re.MULTILINE)
    if match is None:
        raise SystemExit(f'preview did not print a usable local URL:\n{output}')
    if f'Flyover preview: {pathlib.Path(directory).resolve()}' not in output:
        raise SystemExit(f'preview did not print the resolved directory:\n{output}')

    base_url = match.group(1)
    if urllib.request.urlopen(base_url, timeout=5).status != 200:
        raise SystemExit('preview index request failed')
    manifest = urllib.request.urlopen(base_url + 'manifest.json', timeout=5).read()
    if b'"schemaVersion": 1' not in manifest:
        raise SystemExit('preview served an unexpected manifest')
    image = urllib.request.urlopen(
        base_url + 'images/screen-0001/variant-0001/phone-dark.png',
        timeout=5,
    ).read()
    if image != b'PNG':
        raise SystemExit('preview served unexpected image data')

    outside_file = pathlib.Path(directory).parent / 'outside-preview-file'
    outside_file.write_bytes(b'SECRET')
    image_path = (
        pathlib.Path(directory)
        / 'images/screen-0001/variant-0001/phone-dark.png'
    )
    image_path.unlink()
    image_path.symlink_to(outside_file)
    # Astro serves an immutable private copy, never the replaced source.
    assert urllib.request.urlopen(base_url + 'images/screen-0001/variant-0001/phone-dark.png').read() == b'PNG'
    image_path.unlink()
    os.mkfifo(image_path)
    assert urllib.request.urlopen(base_url + 'images/screen-0001/variant-0001/phone-dark.png').read() == b'PNG'

    original_root = pathlib.Path(directory)
    moved_root = original_root.with_name(original_root.name + '-moved')
    replacement_root = original_root.with_name(original_root.name + '-replacement')
    original_root.rename(moved_root)
    replacement_root.mkdir()
    (replacement_root / 'manifest.json').write_bytes(b'SECRET')
    original_root.symlink_to(replacement_root, target_is_directory=True)
    pinned_manifest = urllib.request.urlopen(
        base_url + 'manifest.json',
        timeout=5,
    ).read()
    if b'"schemaVersion": 1' not in pinned_manifest or pinned_manifest == b'SECRET':
        raise SystemExit('preview changed roots after server startup')

    try:
        urllib.request.urlopen(base_url + 'assets/', timeout=5)
        raise SystemExit('preview exposed a directory listing')
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise

    for path in ('.git/config', 'package.json', 'http:/remote.example/manifest.json', '@fs/etc/passwd'):
        try:
            leaked = urllib.request.urlopen(base_url + path, timeout=5).read()
            assert b'SECRET' not in leaked and b'not the atlas manifest' not in leaked
        except urllib.error.HTTPError:
            pass

finally:
    if process.poll() is None:
        process.send_signal(signal.SIGINT)
    try:
        status = process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        status = process.wait(timeout=5)
    stderr = process.stderr.read().decode(errors='replace')
    if status != 130:
        raise SystemExit(f'preview exited with {status}:\n{output}\n{stderr}')
PY

INVALID_PREVIEW="$TEMP/invalid-preview"
cp -R "$OUTPUT" "$INVALID_PREVIEW"
printf '%s\n' schemaVersion=2 >"$INVALID_PREVIEW/.flyover-generated"
expect_failure "$ROOT/flyover" preview --output "$INVALID_PREVIEW"
grep -q "generated marker is unsupported" "$TEMP/stderr" \
    || fail "preview accepted an unsupported marker"

INVALID_UTF8_PREVIEW="$TEMP/invalid-utf8-preview"
cp -R "$OUTPUT" "$INVALID_UTF8_PREVIEW"
printf '\377' >"$INVALID_UTF8_PREVIEW/.flyover-generated"
expect_failure "$ROOT/flyover" preview --output "$INVALID_UTF8_PREVIEW"
grep -q "could not read" "$TEMP/stderr" \
    || fail "preview did not report an invalid marker encoding"
if grep -q "Traceback" "$TEMP/stderr"; then
    fail "preview printed a traceback for an invalid marker encoding"
fi

SYMLINK_PREVIEW="$TEMP/symlink-preview"
cp -R "$OUTPUT" "$SYMLINK_PREVIEW"
ln -s "$TEMP/marker-target" "$SYMLINK_PREVIEW/leak"
expect_failure "$ROOT/flyover" preview --output "$SYMLINK_PREVIEW"
grep -q "contains a symbolic link" "$TEMP/stderr" \
    || fail "preview accepted a symbolic link"

STANDARD_CACHE_PYTHON_BIN="$TEMP/standard-cache-python-bin"
mkdir -p "$STANDARD_CACHE_PYTHON_BIN"
cat >"$STANDARD_CACHE_PYTHON_BIN/python3" <<'PYTHON'
#!/bin/bash
set -euo pipefail
exec "$FLYOVER_REAL_PYTHON" -X pycache_prefix= "$@"
PYTHON
chmod +x "$STANDARD_CACHE_PYTHON_BIN/python3"
REAL_PYTHON="$(command -v python3)"

CLEAN_REPO="$TEMP/clean-repo"
mkdir -p "$CLEAN_REPO/Shared/Flyover/Web/src/scripts" "$CLEAN_REPO/Shared/Flyover/Web/src/styles"
mkdir -p "$CLEAN_REPO/Tools"
mkdir -p "$CLEAN_REPO/.github"
cp "$ROOT/.github/flyover-apps.json" "$CLEAN_REPO/.github/flyover-apps.json"
cp "$ROOT/flyover" "$CLEAN_REPO/flyover"
cp "$ROOT"/Tools/flyover_*.py "$CLEAN_REPO/Tools/"
cp "$ROOT/Tools/repository.py" "$CLEAN_REPO/Tools/"
cp "$ROOT/Shared/Flyover/Web/src/scripts/viewer.ts" "$CLEAN_REPO/Shared/Flyover/Web/src/scripts/viewer.ts"
cp "$ROOT/Shared/Flyover/Web/src/styles/styles.css" "$CLEAN_REPO/Shared/Flyover/Web/src/styles/styles.css"
chmod +x "$CLEAN_REPO/flyover"
git -C "$CLEAN_REPO" init -q
git -C "$CLEAN_REPO" add .
git -C "$CLEAN_REPO" -c user.name=Flyover -c user.email=flyover@example.com \
    -c commit.gpgsign=false commit -qm fixture
PATH="$STANDARD_CACHE_PYTHON_BIN:$PATH" FLYOVER_REAL_PYTHON="$REAL_PYTHON" \
    FLYOVER_CAPTURE_RUNNER="$SUCCESS_RUNNER" FLYOVER_XCODE_VERSION_OVERRIDE=Tests \
    "$CLEAN_REPO/flyover" export --output "$CLEAN_REPO/site" >/dev/null
PATH="$STANDARD_CACHE_PYTHON_BIN:$PATH" FLYOVER_REAL_PYTHON="$REAL_PYTHON" \
    FLYOVER_CAPTURE_RUNNER="$SUCCESS_RUNNER" FLYOVER_XCODE_VERSION_OVERRIDE=Tests \
    "$CLEAN_REPO/flyover" export --output "$CLEAN_REPO/site" >/dev/null
python3 - "$CLEAN_REPO/site/manifest.json" <<'PY'
import json, pathlib, sys
dirty = json.loads(pathlib.Path(sys.argv[1]).read_text())['build']['dirty']
if dirty:
    import subprocess
    subprocess.run(['git', '-C', str(pathlib.Path(sys.argv[1]).parent.parent), 'status', '--porcelain'])
    raise SystemExit('staging a clean in-repository export marked the source dirty')
PY
[ ! -e "$CLEAN_REPO/Tools/__pycache__" ] \
    || fail "Flyover Python tooling wrote bytecode into the source tree"

FAILING_GIT_BIN="$TEMP/failing-git-bin"
mkdir -p "$FAILING_GIT_BIN"
cat >"$FAILING_GIT_BIN/git" <<'GIT'
#!/bin/bash
for argument in "$@"; do
    if [ "$argument" = status ]; then
        exit 71
    fi
done
exec "$FLYOVER_REAL_GIT" "$@"
GIT
chmod +x "$FAILING_GIT_BIN/git"
expect_failure env PATH="$FAILING_GIT_BIN:$PATH" FLYOVER_REAL_GIT="$(command -v git)" \
    FLYOVER_CAPTURE_RUNNER="$SUCCESS_RUNNER" FLYOVER_XCODE_VERSION_OVERRIDE=Tests \
    "$CLEAN_REPO/flyover" export --output "$CLEAN_REPO/status-failure"
grep -q "could not read the Git working-tree status" "$TEMP/stderr" \
    || fail "a Git status failure was treated as a clean source tree"

printf '%s\n' retained-before-invalid >"$OUTPUT/retained-before-invalid"
expect_failure env FLYOVER_CAPTURE_RUNNER="$SUCCESS_RUNNER" \
    FLYOVER_XCODE_VERSION_OVERRIDE=Tests FLYOVER_INVALID_MANIFEST=missing-application \
    "$ROOT/flyover" export --output "$OUTPUT"
grep -q "manifest.application is not an object" "$TEMP/stderr" \
    || fail "an incomplete browser manifest did not report its missing section"
[ -f "$OUTPUT/retained-before-invalid" ] \
    || fail "an incomplete browser manifest replaced the last successful output"

FLYOVER_CAPTURE_RUNNER="$SUCCESS_RUNNER" FLYOVER_XCODE_VERSION_OVERRIDE=Tests \
    FLYOVER_STALE_BACKUP_DESTINATION="$OUTPUT" \
    "$ROOT/flyover" export --output "$OUTPUT" >/dev/null
STALE_BACKUP="$(find "$TEMP" -maxdepth 1 -type d \
    -name '.flyover-previous.output.*' -print -quit)"
[ -n "$STALE_BACKUP" ] && [ -f "$STALE_BACKUP/retained" ] \
    || fail "replacement removed a backup directory that it did not create"
rm -rf "$STALE_BACKUP"
if find "$TEMP" -maxdepth 1 -name '.flyover-replacement.*' | grep -q .; then
    fail "a successful export left its replacement directory"
fi

printf '%s\n' old >"$OUTPUT/old-file"
FLYOVER_CAPTURE_RUNNER="$SUCCESS_RUNNER" FLYOVER_XCODE_VERSION_OVERRIDE=Tests \
    "$ROOT/flyover" export --output "$OUTPUT" >/dev/null
[ ! -e "$OUTPUT/old-file" ] || fail "a marked directory was not replaced"

printf '%s\n' retained >"$OUTPUT/retained"
expect_failure env FLYOVER_CAPTURE_RUNNER="$FAILURE_RUNNER" \
    FLYOVER_XCODE_VERSION_OVERRIDE=Tests "$ROOT/flyover" export --output "$OUTPUT"
[ -f "$OUTPUT/retained" ] || fail "a failed export replaced the last successful output"
expect_failure env FLYOVER_WEB_BUILD_RUNNER="$FAILURE_RUNNER" \
    FLYOVER_CAPTURE_RUNNER="$SUCCESS_RUNNER" FLYOVER_XCODE_VERSION_OVERRIDE=Tests \
    "$ROOT/flyover" export --output "$OUTPUT"
[ -f "$OUTPUT/retained" ] || fail "a failed Astro build replaced the last successful output"
if find "$TEMP" -maxdepth 1 -name '.flyover-staging.*' | grep -q .; then
    fail "a failed export left a staging directory"
fi

mise exec node -- node --test "$ROOT/Shared/Flyover/Tools/Tests/load_atlas_test.js" \
    || fail "the manifest loading regressions failed"
mise exec -- npm run test:unit --workspace stuff-flyover-site --prefix "$ROOT" \
    || fail "the viewer policy regressions failed"
