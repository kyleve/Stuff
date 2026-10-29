import { FrameScope } from "./frame-scope.ts";
import { InspectorPositionController } from "./inspector-position.ts";
import type { AtlasManifest, AtlasScreen } from "./manifest.ts";
import { readSelection, selectionHash } from "./navigation.ts";
import { createSession, type Panel, type ViewMode } from "./session.ts";

import { createAtlasView } from "./atlas-view.ts";
import { createCanvasController } from "./canvas-controller.ts";
import { createCatalog } from "./catalog.ts";
import { createControls } from "./controls.ts";
import { element, visibleFocusTarget } from "./dom.ts";
import { createFilterController } from "./filter-controller.ts";
import { createImageController } from "./image-controller.ts";
import { createInspector } from "./inspector.ts";
import { createPanels } from "./panels.ts";
import { createPreviews } from "./previews.ts";
import { createSearch } from "./search.ts";

export function startAtlas(manifest: AtlasManifest) {
    "use strict";
    const root = document.getElementById("app");

    if (!root) throw new Error("The atlas mount point is missing.");
    const events = new AbortController();
    const renderFrames = new FrameScope(window);
    const inspectorPosition = new InspectorPositionController();
    const selectedVariants = new Map(manifest.screens.map(screen => [screen.id, screen.variants[0]?.id]));
    const state = createSession(manifest);
    const actions = { chooseProfile, openPanel, chooseView, chooseVariant, openScreen, closeInspector, neighboringScreen, closePanel, renderOrNavigate, render };
    const catalog = createCatalog({ manifest, selectedVariants, state });
    const residency = createImageController({ state, manifest, catalog });
    const canvas = createCanvasController({ state, residency, manifest, actions, catalog });
    const controls = createControls({ manifest, state, actions, canvas, catalog, selectedVariants });
    const captures = createPreviews({ catalog, root, state });
    const filters = createFilterController({ catalog, manifest, state, residency });
    // Search uses the shared panel surface; defer this callback until all components exist.
    const panels = createPanels({ state, search: { searchPanel: () => search.searchPanel() }, actions,
        canvas, manifest, filters, catalog, renderFrames });
    const search = createSearch({ panels, state, actions, manifest, catalog, selectedVariants });
    const atlas = createAtlasView({ catalog, state, manifest, actions, canvas, panels,
        captures, controls, filters, residency });
    const inspection = createInspector({ state, catalog, manifest, actions, captures, controls });

    function parseHash() {
        const previousScreenID = state.screen;
        const selection = readSelection(location.hash, manifest);
        Object.assign(state, {
            view: selection.view, profile: selection.profile, screen: selection.screen,
            panel: null, panelTrigger: null, commandQuery: ""
        });
        for (const [screenID, variantID] of selection.variants) selectedVariants.set(screenID, variantID);
        if (!state.screen && previousScreenID) {
            state.pendingFocusKey = state.inspectorReturnFocusKey || "atlas-screen-" + previousScreenID;
        }
    }

    function writeHash() {
        const next = selectionHash({ ...state, variants: selectedVariants }, manifest);
        if (location.hash === next) return false;
        location.hash = next;
        return true;
    }

    function renderOrNavigate() {
        if (!writeHash()) render();
    }

    function chooseView(view: ViewMode) {
        state.view = view;
        state.panel = null;
        if (view === "canvas" && !state.canvas.initialized) state.pendingCanvasAction = "fit-initial";
        renderOrNavigate();
    }

    function chooseProfile(profile: string) {
        state.profile = profile;
        renderOrNavigate();
    }

    function chooseVariant(screen: AtlasScreen, variantID: string, updateHistory = false) {
        selectedVariants.set(screen.id, variantID);
        if (state.screen === screen.id || updateHistory) {
            state.screen = screen.id;
        }
        renderOrNavigate();
    }

    function openScreen(screenID: string | null | undefined, preserveVariant = false) {
        const screen = screenID ? catalog.screenByID.get(screenID) : undefined;
        if (!screen) return;
        if (!state.screen) state.inspectorReturnFocusKey = "atlas-screen-" + screenID;
        if (!preserveVariant) selectedVariants.set(screen.id, screen.variants[0]?.id);
        state.screen = screen.id;
        state.routeFocus = screen.id;
        state.inspectorScale = "fit";
        state.inspectorDetails = false;
        state.panel = null;
        renderOrNavigate();
    }

    function neighboringScreen(offset: number) {
        const index = manifest.screens.findIndex(screen => screen.id === state.screen);
        if (index < 0) return null;
        const next = (index + offset + manifest.screens.length) % manifest.screens.length;
        return manifest.screens[next];
    }

    function closeInspector() {
        state.pendingFocusKey = state.inspectorReturnFocusKey;
        state.screen = null;
        state.routeFocus = null;
        state.inspectorDetails = false;
        renderOrNavigate();
    }

    function openPanel(panel: Panel, triggerID: string) {
        state.panel = panel;
        state.panelTrigger = triggerID;
        if (panel !== "search") state.commandQuery = "";
        render();
    }

    function closePanel() {
        const triggerID = state.panelTrigger;
        state.panel = null;
        state.commandQuery = "";
        render();
        renderFrames.request(() => triggerID && document.getElementById(triggerID)?.focus());
    }
    let application: HTMLElement | null = null;
    let mountedView: ViewMode | null = null;
    let mainView: HTMLElement | null = null;
    let dock: HTMLElement | null = null;
    let overlay: HTMLDialogElement | null = null;
    let overlayKey: string | null = null;

    function render() {
        inspectorPosition.capture(document.getElementById("inspector"));
        if (!state.screen) inspectorPosition.reset();
        renderFrames.cancel();
        if (!state.pendingCanvasPosition) canvas.captureViewPosition();
        canvas.cancelCanvasWork();
        residency.cancelImageWork();
        const activeElement = document.activeElement instanceof HTMLElement ? document.activeElement : null;
        const activeFocusKey = activeElement?.dataset.focusKey;
        const canRestoreActiveFocus = !state.panel
            && (!state.screen || activeElement?.closest(".inspector"));
        const focusKey = state.pendingFocusKey || (canRestoreActiveFocus ? activeFocusKey : null);
        state.pendingFocusKey = null;
        if (!application) {
            application = element("div", "application");
            application.append(controls.appHeader());
            root!.replaceChildren(application);
        }
        const changedView = mountedView !== state.view;
        if (changedView) {
            mainView?.remove();
            dock?.remove();
            mainView = state.view === "canvas" ? atlas.canvasView() : atlas.listView();
            dock = controls.bottomDock();
            application.append(mainView, dock);
            mountedView = state.view;
        }
        captures.updatePreviews();
        renderFrames.request(() => {
            if (state.view === "canvas" && (changedView || !state.canvas.initialized
                || state.pendingCanvasAction || state.pendingCanvasPosition)) canvas.restoreCanvasView();
            if (changedView && state.view === "list" && mainView) mainView.scrollTop = state.list.scrollTop;
        });

        const nextOverlayKey = state.screen
            ? JSON.stringify([state.screen, selectedVariants.get(state.screen), state.profile])
            : state.panel;
        if (overlayKey !== nextOverlayKey) {
            inspection.disconnectInspector();
            overlay?.close();
            overlay?.remove();
            overlay = state.screen ? inspection.inspector() : panels.activePanel();
            overlayKey = nextOverlayKey;
            if (overlay) root!.append(overlay);
        }
        const activeOverlay = overlay;
        if (activeOverlay) {
            renderFrames.request(() => {
                if (!activeOverlay.open) activeOverlay.showModal();
                if (!state.screen) {
                    canvas.updateMiniMapViewport();
                    return;
                }
                inspection.syncInspectorPresentation();
                inspection.observeInspectorSize();
                inspectorPosition.restore(activeOverlay);
            });
        }
        renderFrames.request(() => {
            filters.updateSearchVisibility();
            if (focusKey) {
                (visibleFocusTarget(focusKey) || visibleFocusTarget("filters-control"))?.focus();
            }
        });
    }

    window.addEventListener("hashchange", () => {
        if (!state.pendingCanvasPosition) canvas.captureViewPosition();
        parseHash();
        render();
    }, { signal: events.signal });

    window.addEventListener("resize", () => {
        if (state.screen) renderFrames.request(() => {
            inspection.updateInspectorDetailsAccessibility();
            inspection.fitInspectorImage();
        });
        if (state.view === "canvas") canvas.scheduleCanvasNavigationUpdate();
        else residency.scheduleListImageResidencyUpdate();
    }, { signal: events.signal });

    window.addEventListener("keydown", event => {
        const target = event.target instanceof HTMLElement ? event.target : null;
        const isEditing = target instanceof HTMLInputElement
            || target instanceof HTMLSelectElement
            || target instanceof HTMLTextAreaElement
            || target?.isContentEditable;
        const isCaptureScroller = target?.closest?.("[data-capture-scroller]");
        const commandSearch = (event.metaKey || event.ctrlKey) && event.key.toLocaleLowerCase() === "k";
        if (commandSearch || (event.key === "/" && !isEditing && !event.metaKey && !event.ctrlKey && !event.altKey)) {
            event.preventDefault();
            if (!state.screen) openPanel("search", "search-trigger");
            return;
        }
        if (isEditing || isCaptureScroller || event.metaKey || event.ctrlKey || event.altKey || state.panel) return;
        if (state.screen && (event.key === "ArrowLeft" || event.key === "[")) {
            event.preventDefault();
            openScreen(neighboringScreen(-1)?.id, true);
        } else if (state.screen && (event.key === "ArrowRight" || event.key === "]")) {
            event.preventDefault();
            openScreen(neighboringScreen(1)?.id, true);
        } else if (state.screen && event.key.toLocaleLowerCase() === "i") {
            event.preventDefault();
            inspection.toggleInspectorDetails();
        } else if (!state.screen && state.view === "canvas" && event.key.toLocaleLowerCase() === "f") {
            event.preventDefault();
            canvas.fitAll();
        } else if (!state.screen && state.view === "canvas" && event.key === "0") {
            event.preventDefault();
            canvas.fitCurrentGroup();
        } else if (!state.screen && state.view === "canvas" && (event.key === "+" || event.key === "=")) {
            event.preventDefault();
            canvas.setZoom(state.zoom + 0.1);
        } else if (!state.screen && state.view === "canvas" && event.key === "-") {
            event.preventDefault();
            canvas.setZoom(state.zoom - 0.1);
        }
    }, { signal: events.signal });

    parseHash();

    render();

    return () => {
        events.abort();
        renderFrames.cancel();
        canvas.cancelCanvasWork();
        residency.cancelImageWork();
        inspection.disconnectInspector();
        inspectorPosition.reset();
        overlay?.close();
        root.replaceChildren();
    };
}
