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

"$ROOT/flyover" --help | grep -q 'flyover export' || fail "export help is incomplete"
"$ROOT/flyover" --help | grep -q 'flyover preview' || fail "preview help is incomplete"
"$ROOT/flyover" export --help | grep -q 'phone-voiceover' \
    || fail "export help does not list the supported profiles"
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

PREVIEW_ARGUMENTS="$TEMP/preview-arguments"
PREVIEW_RUNNER="$TEMP/preview-runner"
cat >"$PREVIEW_RUNNER" <<'RUNNER'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$@" >"$FLYOVER_PREVIEW_ARGUMENTS"
RUNNER
chmod +x "$PREVIEW_RUNNER"
FLYOVER_PREVIEW_PYTHON="$PREVIEW_RUNNER" \
    FLYOVER_PREVIEW_ARGUMENTS="$PREVIEW_ARGUMENTS" \
    "$ROOT/flyover" preview --output "$OUTPUT" --lan --port 8080
python3 - "$PREVIEW_ARGUMENTS" "$ROOT" "$OUTPUT" <<'PY'
import pathlib, sys
arguments = pathlib.Path(sys.argv[1]).read_text().splitlines()
expected = [
    f'{sys.argv[2]}/Tools/flyover_preview.py',
    'serve',
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
        "$ROOT/flyover" preview --port 0
)
python3 - "$PREVIEW_ARGUMENTS" "$ROOT" "$CALLER/.build/flyover/where" <<'PY'
import pathlib, sys
arguments = pathlib.Path(sys.argv[1]).read_text().splitlines()
expected = [
    f'{sys.argv[2]}/Tools/flyover_preview.py',
    'serve',
    str(pathlib.Path(sys.argv[3]).resolve()),
    '--port',
    '0',
]
if arguments != expected:
    raise SystemExit(f'default preview arguments are wrong: {arguments}')
PY

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
deadline = time.monotonic() + 10
try:
    while time.monotonic() < deadline and b'Press Ctrl-C' not in b''.join(chunks):
        for key, _ in selector.select(timeout=max(0, deadline - time.monotonic())):
            chunk = os.read(key.fileobj.fileno(), 4096)
            if chunk:
                chunks.append(chunk)
        if process.poll() is not None:
            break
    output = b''.join(chunks).decode(errors='replace')
    match = re.search(r'^Local:\s+(http://127\.0\.0\.1:\d+/)$', output, re.MULTILINE)
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
    try:
        urllib.request.urlopen(base_url + 'assets/', timeout=5)
        raise SystemExit('preview exposed a directory listing')
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise

    port = int(base_url.rstrip('/').rsplit(':', 1)[1])
    connection = http.client.HTTPConnection('127.0.0.1', port, timeout=5)
    connection.request('GET', '/%2e%2e/manifest.json')
    response = connection.getresponse()
    if response.status != 404:
        raise SystemExit(f'preview accepted a traversal request: {response.status}')
    response.read()
    connection.close()

    connection = http.client.HTTPConnection('127.0.0.1', port, timeout=5)
    connection.request('GET', 'http://remote.example/manifest.json')
    response = connection.getresponse()
    if response.status != 404:
        raise SystemExit(f'preview accepted an absolute request target: {response.status}')
    response.read()
    connection.close()

    with socket.create_connection(('127.0.0.1', port), timeout=5) as client:
        client.sendall(
            b'GET http://[/manifest.json HTTP/1.1\r\n'
            b'Host: 127.0.0.1\r\nConnection: close\r\n\r\n'
        )
        response_data = client.recv(4096)
    if b' 404 ' not in response_data:
        raise SystemExit('preview did not reject a malformed absolute request target')

    with socket.create_connection(('127.0.0.1', port), timeout=5) as client:
        client.sendall(
            b'GET /\x1b]0;untrusted\x07 HTTP/1.1\r\n'
            b'Host: 127.0.0.1\r\nConnection: close\r\n\r\n'
        )
        response_data = client.recv(4096)
    if b' 404 ' not in response_data:
        raise SystemExit('preview did not reject the terminal-control request')
finally:
    if process.poll() is None:
        process.send_signal(signal.SIGINT)
    try:
        status = process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        status = process.wait(timeout=5)
    stderr = process.stderr.read().decode(errors='replace')
    if status != 0:
        raise SystemExit(f'preview exited with {status}:\n{output}\n{stderr}')
    if stderr:
        raise SystemExit(f'preview logged untrusted request data:\n{stderr}')
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

CLEAN_REPO="$TEMP/clean-repo"
mkdir -p "$CLEAN_REPO/Shared/Flyover/Web/assets"
mkdir -p "$CLEAN_REPO/Tools"
cp "$ROOT/flyover" "$CLEAN_REPO/flyover"
cp "$ROOT/Tools/flyover_preview.py" "$CLEAN_REPO/Tools/flyover_preview.py"
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
