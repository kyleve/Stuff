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

python3 - "$ROOT/Shared/Flyover/Web/assets/styles.css" \
    "$ROOT/Shared/Flyover/Web/assets/app.js" <<'PY'
import pathlib
import re
import sys

styles = pathlib.Path(sys.argv[1]).read_text()
javascript = pathlib.Path(sys.argv[2]).read_text()
properties_by_selector = {}
for selector_group, declaration_group in re.findall(r'([^{}]+)\{([^{}]*)\}', styles):
    declarations = {}
    for declaration in declaration_group.split(';'):
        if ':' not in declaration:
            continue
        name, value = declaration.split(':', 1)
        declarations[name.strip()] = value.strip()
    for selector in selector_group.split(','):
        properties_by_selector.setdefault(selector.strip(), {}).update(declarations)

def require_properties(selector, expected):
    actual = properties_by_selector.get(selector, {})
    for name, value in expected.items():
        if actual.get(name) != value:
            raise SystemExit(f'{selector} must set {name}: {value}')

for selector in ('#app', '#app > dialog'):
    require_properties(selector, {
        '-webkit-user-select': 'none',
        'user-select': 'none',
    })
for selector in (
    '#app input',
    '#app textarea',
    '#app [contenteditable="true"]',
    '#app .selectable-text',
):
    require_properties(selector, {
        '-webkit-user-select': 'text',
        'user-select': 'text',
    })
require_properties('#app img', {'-webkit-user-drag': 'none'})

factory_start = javascript.index('    function screenImage(screen, className = "", eager = false) {')
factory_end = javascript.index('\n\n    function captureViewportSize(screen) {', factory_start)
factory = javascript[factory_start:factory_end]
if 'image.draggable = false;' not in factory:
    raise SystemExit('screen images must disable native dragging')

for fragment in (
    'class="error selectable-text"',
    'element("dd", "selectable-text", value)',
    'element("h2", "selectable-text", screen.title)',
    'element("h3", "selectable-text", screen.title)',
):
    if fragment not in javascript:
        raise SystemExit('missing intentional text-selection surface: ' + fragment)
PY

JSC="/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc"
[ -x "$JSC" ] || fail "JavaScriptCore is unavailable"
python3 - "$ROOT/Shared/Flyover/Web/assets/app.js" "$TEMP/residency-test.js" <<'PY'
import pathlib
import sys
import textwrap

source = pathlib.Path(sys.argv[1]).read_text()
settings_start_marker = '    const targetResidentImageCount = '
settings_end_marker = '\n    let inspectorResizeObserver'
start_marker = '    function residentScreenIDs(candidates) {'
end_marker = '\n\n    function installCanvasPinch(viewport) {'
fit_start_marker = '    function fitFrame(frame, behavior = "smooth") {'
fit_end_marker = '\n\n    function fitAll(behavior = "smooth") {'
settings_start = source.index(settings_start_marker)
settings_end = source.index(settings_end_marker, settings_start)
start = source.index(start_marker)
end = source.index(end_marker, start)
fit_start = source.index(fit_start_marker)
fit_end = source.index(fit_end_marker, fit_start)
settings = textwrap.dedent(source[settings_start:settings_end])
residency = textwrap.dedent(source[start:end])
fit_frame = textwrap.dedent(source[fit_start:fit_end])
test = '''
%s
%s
%s

let document;
let manifest;
let state;
let screenByID;
const window = {
    matchMedia: () => ({ matches: true }),
};

function requestAnimationFrame(callback) {
    callback();
    return 1;
}

function matchesFilters() {
    return true;
}

function imageMetadata(screen) {
    return screen.imageMetadata;
}

function applyZoom() {}

function candidate(id, isVisible, imagePixels) {
    return { screen: { id }, isVisible, imagePixels };
}

function expect(condition, message) {
    if (!condition) throw new Error(message);
}

function expectIDs(actual, expected, message) {
    const actualIDs = Array.from(actual);
    if (JSON.stringify(actualIDs) !== JSON.stringify(expected)) {
        throw new Error(message + ': ' + JSON.stringify(actualIDs));
    }
}

const visible = Array.from(
    { length: 20 },
    (_, index) => candidate('visible-' + index, true, 5_000_000),
);
expectIDs(
    residentScreenIDs(visible),
    visible.map(item => item.screen.id),
    'all visible screens must remain resident above both budgets',
);

const mixed = [
    ...Array.from({ length: 10 }, (_, index) => candidate('nearby-' + index, false, 1_000_000)),
    candidate('visible-a', true, 1_000_000),
    candidate('visible-b', true, 1_000_000),
];
expectIDs(
    residentScreenIDs(mixed),
    ['visible-a', 'visible-b', 'nearby-0', 'nearby-1', 'nearby-2', 'nearby-3'],
    'offscreen prefetch must stop at the resident count budget',
);

const largeNearby = Array.from(
    { length: 8 },
    (_, index) => candidate('large-' + index, false, 5_000_000),
);
expectIDs(
    residentScreenIDs(largeNearby),
    ['large-0', 'large-1', 'large-2', 'large-3'],
    'offscreen prefetch must stop at the resident pixel budget',
);

function imageContainer(screenID, initiallyResident = false) {
    const attributes = new Map();
    if (initiallyResident) attributes.set('src', screenID + '.png');
    const image = {
        dataset: { src: screenID + '.png' },
        loading: 'lazy',
        getAttribute: name => attributes.get(name) || null,
        removeAttribute: name => attributes.delete(name),
        set src(value) { attributes.set('src', value); },
        get src() { return attributes.get('src'); },
    };
    return {
        dataset: { screenId: screenID },
        image,
        querySelector: () => image,
    };
}

const canvasScreens = Array.from({ length: 20 }, (_, index) => ({
    id: 'canvas-' + index,
    frame: { x: 10, y: 10, width: 20, height: 20 },
    imageMetadata: { pixelWidth: 2_500, pixelHeight: 2_000 },
}));
const canvasContainers = canvasScreens.map(screen => imageContainer(screen.id));
const canvasViewport = {
    clientHeight: 100,
    clientWidth: 100,
    scrollLeft: 0,
    scrollTop: 0,
};
manifest = { screens: canvasScreens };
state = { screen: null, view: 'canvas', zoom: 1 };
document = {
    getElementById: id => id === 'canvas-viewport' ? canvasViewport : null,
    querySelectorAll: selector => selector === '.screen-card' ? canvasContainers : [],
};
updateCanvasImageResidency();
expect(
    canvasContainers.every(container => container.image.getAttribute('src') !== null),
    'all 20 visible canvas cards must receive an image source',
);
expect(
    canvasContainers.every(container => container.image.loading === 'eager'),
    'visible canvas images must load eagerly',
);

const visibleListScreens = Array.from({ length: 20 }, (_, index) => ({
    id: 'list-visible-' + index,
    imageMetadata: { pixelWidth: 2_500, pixelHeight: 2_000 },
    screenOrder: index,
}));
const nearbyListScreens = Array.from({ length: 10 }, (_, index) => ({
    id: 'list-nearby-' + index,
    imageMetadata: { pixelWidth: 1_000, pixelHeight: 1_000 },
    screenOrder: visibleListScreens.length + index,
}));
const listRows = [
    ...visibleListScreens.map(screen => ({
        ...imageContainer(screen.id),
        getBoundingClientRect: () => ({ top: 10, bottom: 90 }),
    })),
    ...nearbyListScreens.map((screen, index) => ({
        ...imageContainer(screen.id, true),
        getBoundingClientRect: () => ({ top: 101 + index, bottom: 111 + index }),
    })),
];
const listViewport = {
    getBoundingClientRect: () => ({ top: 0, bottom: 100 }),
};
screenByID = new Map(
    [...visibleListScreens, ...nearbyListScreens].map(screen => [screen.id, screen]),
);
state = { screen: null, view: 'list' };
document = {
    querySelector: selector => selector === '.list-view' ? listViewport : null,
    querySelectorAll: selector => selector === '.list-row' ? listRows : [],
};
updateListImageResidency();
expect(
    listRows.slice(0, 20).every(row => row.image.getAttribute('src') !== null),
    'all 20 visible list rows must receive an image source',
);
expect(
    listRows.slice(20).every(row => row.image.getAttribute('src') === null),
    'offscreen list preloads must yield when visible rows exceed the targets',
);

let residencyRefreshCount = 0;
const fitViewport = {
    clientHeight: 600,
    clientWidth: 800,
    scrollTo: () => {},
};
state = { canvas: {}, zoom: 1 };
document = {
    getElementById: id => id === 'canvas-viewport' ? fitViewport : null,
};
updateCanvasImageResidency = () => { residencyRefreshCount += 1; };
fitFrame({ x: 0, y: 0, width: 1_600, height: 1_200 }, 'auto');
expect(
    residencyRefreshCount === 1,
    'fitting the canvas must refresh image residency after changing zoom',
);
''' % (settings, residency, fit_frame)
pathlib.Path(sys.argv[2]).write_text(test)
PY
"$JSC" "$TEMP/residency-test.js" \
    || fail "the web thumbnail residency policy is incorrect"
