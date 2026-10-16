#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd -P)"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/flyover-command-tests.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT INT TERM

fail() {
    echo "flyover command test failed: $*" >&2
    exit 1
}

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

factory_start = javascript.index(
    '    function screenImage(screen, className = "", eager = false, fullResolution = false) {'
)
factory_end = javascript.index('\n\n    function captureViewportSize(screen) {', factory_start)
factory = javascript[factory_start:factory_end]
if 'image.draggable = false;' not in factory:
    raise SystemExit('screen images must disable native dragging')
if 'fullResolution ? imagePath(screen) : thumbnailPath(screen)' not in factory:
    raise SystemExit('atlas images must use thumbnails while allowing full-resolution inspection')
if 'const fullImage = screenImage(screen, "", true, true);' not in javascript:
    raise SystemExit('the inspector must request the full-resolution image')
require_properties('.bottom-dock', {'justify-content': 'safe center'})
require_properties('.inspector-image.actual', {'place-items': 'start safe center'})

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
"$JSC" "$ROOT/Shared/Flyover/Tools/Tests/app_test.js" -- \
    "$ROOT/Shared/Flyover/Web/assets/app.js" \
    || fail "the web navigation and capture scrolling regressions failed"
python3 - "$ROOT/Shared/Flyover/Web/assets/app.js" "$TEMP/residency-test.js" <<'PY'
import pathlib
import sys
import textwrap

source = pathlib.Path(sys.argv[1]).read_text()
settings_start_marker = '    const targetResidentImageCount = '
settings_end_marker = '\n    let inspectorResizeObserver'
image_path_start_marker = '    function screenVariant(screen) {'
image_path_end_marker = '\n\n    function connectedRoutes(screen) {'
image_factory_start_marker = '    function screenImage(screen, className = "", eager = false, fullResolution = false) {'
image_factory_end_marker = '\n\n    function captureViewportSize(screen) {'
start_marker = '    function residentScreenIDs(candidates) {'
end_marker = '\n\n    function installCanvasPinch(viewport) {'
fit_start_marker = '    function setZoom(next) {'
fit_end_marker = '\n\n    function fitAll(behavior = "smooth") {'
fit_first_start_marker = '    function fitFirstGroup() {'
fit_first_end_marker = '\n\n    let canvasNavigationFrame'
settings_start = source.index(settings_start_marker)
settings_end = source.index(settings_end_marker, settings_start)
image_path_start = source.index(image_path_start_marker)
image_path_end = source.index(image_path_end_marker, image_path_start)
image_factory_start = source.index(image_factory_start_marker)
image_factory_end = source.index(image_factory_end_marker, image_factory_start)
start = source.index(start_marker)
end = source.index(end_marker, start)
fit_start = source.index(fit_start_marker)
fit_end = source.index(fit_end_marker, fit_start)
fit_first_start = source.index(fit_first_start_marker)
fit_first_end = source.index(fit_first_end_marker, fit_first_start)
settings = textwrap.dedent(source[settings_start:settings_end])
image_paths = textwrap.dedent(source[image_path_start:image_path_end])
image_factory = textwrap.dedent(source[image_factory_start:image_factory_end])
residency = textwrap.dedent(source[start:end])
fit_functions = textwrap.dedent(source[fit_start:fit_end])
fit_first_group = textwrap.dedent(source[fit_first_start:fit_first_end])
test = '\n'.join((
    settings,
    image_paths,
    image_factory,
    residency,
    fit_functions,
    fit_first_group,
    r'''
let document;
let manifest;
let state;
let screenByID;
let selectedVariants;
let imageByKey;
const window = {
    matchMedia: () => ({ matches: true }),
};

function requestAnimationFrame(callback) {
    callback();
    return 1;
}

function element(tag, className) {
    return {
        tag,
        className,
        dataset: {},
        getAttribute(name) { return this[name] || null; },
        removeAttribute(name) { delete this[name]; },
    };
}

function matchesFilters() {
    return true;
}

function applyZoom() {}
function captureCanvasPosition() {}

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

const imageScreen = {
    id: 'screen',
    title: 'Screen',
    variants: [{
        id: 'default',
        title: 'Default',
        captureExtent: 'viewport',
        imagesByProfile: { 'phone-light': 'images/full.png' },
    }],
};
selectedVariants = new Map([['screen', 'default']]);
state = { profile: 'phone-light' };
imageByKey = new Map([[
    imageKey('screen', 'default', 'phone-light'),
    { relativePath: 'images/full.png', thumbnailRelativePath: 'images/thumbnail.png' },
]]);
const cardImage = screenImage(imageScreen);
expect(cardImage.dataset.src === 'images/thumbnail.png', 'cards must use the generated thumbnail');
const inspectorImage = screenImage(imageScreen, '', true, true);
expect(inspectorImage.src === 'images/full.png', 'the inspector must use the full-resolution PNG');
imageByKey.get(imageKey('screen', 'default', 'phone-light')).thumbnailRelativePath = null;
expect(
    screenImage(imageScreen).dataset.src === 'images/full.png',
    'older manifests without thumbnails must fall back to the full-resolution PNG',
);
imageMetadata = screen => screen.imageMetadata;
expect(
    screenImagePixels({
        imageMetadata: {
            pixelWidth: 2_500,
            pixelHeight: 8_000,
            thumbnailRelativePath: 'images/thumbnail.png',
            thumbnailPixelWidth: 470,
            thumbnailPixelHeight: 1_024,
        },
    }) === 481_280,
    'residency budgets must use thumbnail dimensions',
);
expect(
    screenImagePixels({ imageMetadata: { pixelWidth: 2_500, pixelHeight: 8_000 } }) === 20_000_000,
    'older manifests must budget their full-resolution fallback',
);

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

setZoom(-1);
expect(state.zoom === minimumManualZoom, 'manual zoom must retain its 10% floor');
setZoom(9);
expect(state.zoom === maximumZoom, 'manual zoom must retain its 150% ceiling');

for (const width of [320, 390]) {
    fitViewport.clientWidth = width;
    fitViewport.clientHeight = 700;
    state.zoom = 1;
    fitFrame({ x: 0, y: 0, width: 8_260, height: 4_000 }, 'auto');
    const availableWidth = width - 64;
    expect(
        8_260 * state.zoom <= availableWidth + 0.001,
        'Fit All must fit the canvas at ' + width + 'px',
    );
    const fittedZoom = state.zoom;
    setZoom(state.zoom - 0.1);
    expect(
        state.zoom === fittedZoom,
        'zooming out from a sub-10% fit must not increase zoom',
    );

    manifest = { canvas: { initialFitSize: { width: 2_500 } } };
    updateCanvasNavigation = () => {};
    fitFirstGroup();
    expect(
        2_500 * state.zoom <= width - 32 + 0.001,
        'the initial group must fit at ' + width + 'px',
    );
}
''',
))
pathlib.Path(sys.argv[2]).write_text(test)
PY
"$JSC" "$TEMP/residency-test.js" \
    || fail "the web thumbnail residency policy is incorrect"
