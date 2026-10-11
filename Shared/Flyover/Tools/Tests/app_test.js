// Execute the application's private navigation code with browser-boundary doubles.
// These are logic regressions, not a substitute for browser layout/accessibility tests.
const handlers = new Map();
const screens = ["root", "detail & +?#/☃"].map(id => ({
    id,
    title: id,
    variants: [{ id: "default" }, { id: "empty & +?#/☃" }],
}));
const window = {
    FLYOVER_MANIFEST: {
        schemaVersion: 1,
        screens,
        groups: [],
        routes: [],
        profiles: [{ id: "phone-light" }, { id: "phone-dark" }],
        images: [],
    },
    addEventListener(name, callback) { handlers.set(name, callback); },
};
const document = {
    activeElement: null,
    getElementById() { return null; },
    querySelector() { return null; },
};
class HTMLInputElement {}
class HTMLSelectElement {}
class HTMLTextAreaElement {}

// JavaScriptCore does not provide this browser API. Keep the double limited to
// the URLSearchParams operations used by the app; exercise delimiter round trips.
class URLSearchParams {
    constructor(value = "") {
        const decode = text => decodeURIComponent(text.replace(/\+/g, " "));
        this.values = new Map(value.split("&").filter(Boolean).map(pair => {
            const separator = pair.indexOf("=");
            return separator < 0 ? [decode(pair), ""]
                : [decode(pair.slice(0, separator)), decode(pair.slice(separator + 1))];
        }));
    }
    get(key) { return this.values.get(key) ?? null; }
    set(key, value) { this.values.set(key, String(value)); }
    toString() {
        return [...this.values].map(([key, value]) => encodeURIComponent(key) + "=" + encodeURIComponent(value)).join("&");
    }
}

const entries = [""];
let historyIndex = 0;
let pendingHashChange = false;
const location = {
    get hash() { return entries[historyIndex]; },
    set hash(value) {
        if (value === this.hash) return;
        entries.splice(historyIndex + 1);
        entries.push(value);
        historyIndex++;
        pendingHashChange = true;
    },
};
function flushNavigation() {
    if (!pendingHashChange) return;
    pendingHashChange = false;
    handlers.get("hashchange")();
}
function traverse(offset) {
    historyIndex += offset;
    if (historyIndex < 0 || historyIndex >= entries.length) throw Error("Invalid history traversal");
    pendingHashChange = true;
    flushNavigation();
}
function scrollerNode() {
    return {
        dataset: {},
        attributes: {},
        style: { removeProperty(name) { delete this[name]; } },
        setAttribute(name, value) { this.attributes[name] = value; },
        removeAttribute(name) {
            delete this.attributes[name];
            if (name === "tabindex") delete this.tabIndex;
            if (name === "data-capture-scroller") delete this.dataset.captureScroller;
            if (name === "data-focus-key") delete this.dataset.focusKey;
        },
        closest(selector) {
            return selector === "[data-capture-scroller]" && "captureScroller" in this.dataset ? this : null;
        },
        focus() { document.activeElement = this; },
    };
}

function runTests() {
    let assertions = 0;
    function expect(condition, message) {
        assertions++;
        if (!condition) throw Error(message);
    }
    // Leave the real navigation and keyboard handlers installed. Stub only DOM rendering.
    render = () => {};
    parseHash();
    const first = manifest.screens[0];
    const second = manifest.screens[1];
    const alternate = first.variants[1].id;
    chooseVariant(first, alternate);
    flushNavigation();
    expect(state.screen === null, "canvas selection must not open the inspector");
    expect(selectedVariants.get(first.id) === alternate, "canvas selection must survive hash parsing");
    expect(historyIndex === 1, "canvas selection must add a history entry");
    traverse(-1);
    expect(selectedVariants.get(first.id) === "default", "Back must restore omitted default selections");
    traverse(1);
    expect(selectedVariants.get(first.id) === alternate, "Forward must restore canvas selections");
    chooseView("list");
    flushNavigation();
    chooseVariant(second, alternate);
    flushNavigation();
    expect(state.view === "list" && state.screen === null, "list selection must remain in the list");
    const savedHash = location.hash;
    for (const screen of manifest.screens) selectedVariants.set(screen.id, "default");
    parseHash();
    expect(selectedVariants.get(first.id) === alternate && selectedVariants.get(second.id) === alternate,
        "reload must restore every selection, including escaped identifiers");
    chooseProfile("phone-dark");
    flushNavigation();
    expect(selectedVariants.get(second.id) === alternate, "profile changes must preserve states");
    traverse(-1);
    expect(state.profile === "phone-light" && location.hash === savedHash, "Back must restore the profile and states");
    chooseVariant(second, "default");
    flushNavigation();
    expect(new URLSearchParams(location.hash.slice(1)).get("state." + second.id) === null,
        "default states must be omitted from the URL");
    traverse(-1);
    expect(selectedVariants.get(second.id) === alternate, "Back must undo a change to the default state");

    location.hash = "#view=canvas&screen=root&variant=" + encodeURIComponent(alternate);
    flushNavigation();
    expect(state.screen === first.id && selectedVariants.get(first.id) === alternate,
        "legacy inspector deep links must remain valid");
    expect(selectedVariants.get(second.id) === "default", "unlisted screen states must reset");
    chooseVariant(first, "default", true);
    flushNavigation();
    expect(state.screen === first.id && selectedVariants.get(first.id) === "default",
        "inspector state selection must preserve the inspector");
    closeInspector();
    flushNavigation();
    for (const panel of ["filters", "groups", "search", "build"]) {
        openPanel(panel, panel + "-trigger");
        state.commandQuery = "stale search";
        traverse(-1);
        expect(state.screen === first.id && state.panel === null, "Back must dismiss " + panel);
        expect(state.panelTrigger === null && state.commandQuery === "", "history must clear transient panel data");
        traverse(1);
        expect(state.screen === null && state.panel === null, "Forward must not resurrect " + panel);
    }
    location.hash = "#state.root=unknown&screen=missing&profile=missing";
    flushNavigation();
    expect(state.screen === null && state.profile === "phone-light"
        && selectedVariants.get(first.id) === "default", "unknown URL values must resolve to catalog defaults");

    state.screen = first.id;
    const frame = scrollerNode();
    const device = scrollerNode();
    frame.clientWidth = 390;
    frame.clientHeight = 700;
    frame.querySelector = () => device;
    document.getElementById = id => id === "inspector-image" ? frame : null;
    imageByKey.set(imageKey(first.id, "default", "phone-light"), { pointWidth: 402, pointHeight: 874 });
    function layoutCapture(variant) {
        first.variants[0].captureExtent = variant.captureExtent;
        fitInspectorImage();
    }
    function arrow(target) {
        let prevented = false;
        handlers.get("keydown")({ target, key: "ArrowRight", preventDefault() { prevented = true; } });
        return prevented;
    }
    for (const captureExtent of ["viewport", "intrinsic", "fullContent", "fullContent2D"]) {
        const variant = { captureExtent };
        state.inspectorScale = "actual";
        layoutCapture(variant);
        expect(frame.tabIndex === 0 && device.tabIndex === undefined, "100% must focus the outer scroll area: " + captureExtent);
        expect(frame.attributes["aria-label"] === "root scrollable capture", "scroll area needs an accessible name");
        expect(!arrow(frame) && state.screen === first.id, "100% arrows must scroll rather than navigate: " + captureExtent);
        frame.focus();
        state.inspectorScale = "fit";
        layoutCapture(variant);
        expect(frame.tabIndex === undefined && !("captureScroller" in frame.dataset), "Fit must retire the outer scroll target");
        if (captureExtent.startsWith("fullContent")) {
            expect(device.tabIndex === 0 && document.activeElement === device, "Fit must transfer focus to the full-content scroller");
            expect(!arrow(device), "full-content arrows must retain native scrolling");
            state.inspectorScale = "actual";
            layoutCapture(variant);
            expect(document.activeElement === frame, "100% must transfer focus back to the outer scroll area");
        } else {
            expect(device.tabIndex === undefined, "fitted viewport/intrinsic images need no extra tab stop");
        }
        document.activeElement = null;
    }
    expect(arrow(scrollerNode()), "arrows outside the capture must still navigate screens");
    flushNavigation();
    expect(state.screen === second.id, "normal keyboard navigation must open the next screen");
    print("Flyover web navigation: " + assertions + " assertions passed");
}

const source = readFile(arguments[0]);
const startup = "    parseHash();\n    render();\n})();";
if (!source.includes(startup)) throw Error("Application startup boundary changed");
eval(source.replace(startup, "(" + runTests.toString() + ")();\n})();"));
