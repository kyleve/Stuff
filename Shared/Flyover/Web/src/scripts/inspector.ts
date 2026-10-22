import type { Actions } from "./actions.ts";
import { updateCaptureScroller as configureCaptureScroller } from "./capture-scroller.ts";
import type { Catalog } from "./catalog.ts";
import type { Controls } from "./controls.ts";
import { captureLabel, element, icon, iconButton, imageDimensions, metadataRow } from "./dom.ts";
import type { AtlasImage, AtlasManifest, AtlasScreen, AtlasVariant } from "./manifest.ts";
import type { Previews } from "./previews.ts";
import type { RouteDirection, Session } from "./session.ts";

interface Dependencies {
    state: Session;
    manifest: AtlasManifest;
    catalog: Pick<Catalog, "screenByID" | "screenVariant" | "imageMetadata" | "groupByID" | "imagePath" | "captureViewportSize" | "profileByID">;
    captures: Pick<Previews, "screenImage">;
    controls: Pick<Controls, "variantSelector" | "profileSelect" | "routeButtons">;
    actions: Pick<Actions, "closeInspector" | "openScreen" | "neighboringScreen">;
}

export interface Inspector {
    disconnectInspector: () => void;
    inspector: () => HTMLDialogElement | null;
    updateInspectorDetailsAccessibility: () => void;
    fitInspectorImage: () => void;
    observeInspectorSize: () => void;
    toggleInspectorDetails: () => void;
    syncInspectorPresentation: () => void;
}

export function createInspector(deps: Dependencies): Inspector {
    let inspectorResizeObserver: ResizeObserver | null = null;

    function inspector() {
        const screen = deps.state.screen ? deps.catalog.screenByID.get(deps.state.screen) : undefined;
        if (!screen) return null;
        const variant = deps.catalog.screenVariant(screen);
        const metadata = deps.catalog.imageMetadata(screen);
        const group = deps.catalog.groupByID.get(screen.groupID);
        const screenIndex = deps.manifest.screens.findIndex(item => item.id === screen.id);
        const dialog = element("dialog", "inspector");
        dialog.id = "inspector";
        dialog.dataset.screenId = screen.id;
        dialog.dataset.details = String(deps.state.inspectorDetails);
        dialog.setAttribute("aria-labelledby", "inspector-title");

        const header = element("header", "inspector-header");
        const heading = element("div", "inspector-heading");
        heading.append(
            element("p", "eyebrow", (group?.title || "Ungrouped") + " · "
                + (screenIndex + 1) + " of " + deps.manifest.screens.length),
            element("h2", "selectable-text", screen.title),
        );
        heading.querySelector("h2")!.id = "inspector-title";
        const actions = element("div", "inspector-header-actions");
        const raw = element("a", "inspector-action", "PNG");
        raw.href = deps.catalog.imagePath(screen);
        raw.target = "_blank";
        raw.rel = "noopener";
        raw.setAttribute("aria-label", "Open raw PNG");
        raw.append(icon("external"));
        const details = iconButton("info", "Capture details", "inspector-action", true);
        details.id = "details-trigger";
        details.setAttribute("aria-controls", "inspector-details");
        details.setAttribute("aria-expanded", String(deps.state.inspectorDetails));
        details.addEventListener("click", toggleInspectorDetails);
        const close = iconButton("close", "Close inspector", "inspector-action close-inspector");
        close.autofocus = true;
        close.addEventListener("click", deps.actions.closeInspector);
        actions.append(raw, details, close);
        header.append(heading, actions);

        const canvas = element("section", "inspection-canvas");
        const extentClass = variant.captureExtent === "fullContent2D"
            ? " full-content full-content-2d"
            : (variant.captureExtent === "fullContent" ? " full-content" : "");
        const imageFrame = element("div", "inspector-image " + deps.state.inspectorScale + extentClass);
        imageFrame.id = "inspector-image";
        const device = element("div", "inspector-device");
        const fullImage = deps.captures.screenImage(screen, "", true, true);
        if (metadata) {
            const viewportSize = deps.catalog.captureViewportSize(screen);
            device.style.setProperty("--point-width", metadata.pointWidth + "px");
            device.style.setProperty("--point-height", metadata.pointHeight + "px");
            device.style.setProperty("--viewport-width", viewportSize.width + "px");
            device.style.setProperty("--viewport-height", viewportSize.height + "px");
            device.style.setProperty("--aspect-ratio", String(metadata.pointWidth / metadata.pointHeight));
        }
        device.append(fullImage);
        imageFrame.append(device);
        const caption = element("div", "image-caption");
        caption.append(element("span", "capture-badge", captureLabel(variant.captureExtent)), element("span", "", imageDimensions(metadata)));
        canvas.append(imageFrame, caption);

        const drawer = element("aside", "inspector-details");
        drawer.id = "inspector-details";
        drawer.setAttribute("aria-hidden", String(!deps.state.inspectorDetails));
        drawer.inert = !deps.state.inspectorDetails;
        const drawerHeader = element("header", "details-header");
        drawerHeader.append(
            element("p", "eyebrow", "Screen details"),
            element("h3", "selectable-text", screen.title),
        );
        const drawerClose = iconButton("close", "Close details", "icon-button details-close");
        drawerClose.addEventListener("click", toggleInspectorDetails);
        drawerHeader.append(drawerClose);
        drawer.append(drawerHeader, inspectorMetadata(screen, variant, metadata));
        drawer.append(routeSection("Outgoing", screen, "outgoing"));
        drawer.append(routeSection("Incoming", screen, "incoming"));

        dialog.append(header, canvas, drawer, inspectorDock(screen));
        dialog.addEventListener("cancel", event => {
            event.preventDefault();
            if (deps.state.inspectorDetails) toggleInspectorDetails();
            else deps.actions.closeInspector();
        });
        return dialog;
    }

    function inspectorDock(screen: AtlasScreen) {
        const dock = element("nav", "inspector-dock");
        dock.setAttribute("aria-label", "Inspector controls");
        const previous = iconButton("left", "Previous screen", "icon-button inspector-previous");
        previous.setAttribute("aria-keyshortcuts", "ArrowLeft [");
        previous.dataset.focusKey = "inspector-previous";
        previous.addEventListener("click", () => deps.actions.openScreen(deps.actions.neighboringScreen(-1)?.id, true));
        dock.append(previous, element("span", "dock-separator"));

        const stateField = element("label", "inspector-field");
        stateField.append(element("span", "field-label", "State"), deps.controls.variantSelector(screen, true));
        const profileField = element("label", "inspector-field profile-field");
        profileField.append(
            element("span", "field-label", "Profile"),
            deps.controls.profileSelect("", "inspector-profile"),
        );
        dock.append(stateField, profileField, element("span", "dock-separator"));

        const scale = element("div", "segmented-control scale-tabs");
        scale.setAttribute("aria-label", "Image scale");
        for (const option of ([["fit", "Fit"], ["actual", "100%"]] as const)) {
            const button = element("button", "segment", option[1]);
            button.type = "button";
            button.setAttribute("aria-pressed", String(deps.state.inspectorScale === option[0]));
            button.addEventListener("click", () => {
                deps.state.inspectorScale = option[0];
                updateInspectorScale();
            });
            scale.append(button);
        }
        dock.append(scale, element("span", "dock-separator"));

        const next = iconButton("right", "Next screen", "icon-button inspector-next");
        next.setAttribute("aria-keyshortcuts", "ArrowRight ]");
        next.dataset.focusKey = "inspector-next";
        next.addEventListener("click", () => deps.actions.openScreen(deps.actions.neighboringScreen(1)?.id, true));
        dock.append(next);
        return dock;
    }

    function inspectorMetadata(screen: AtlasScreen, variant: AtlasVariant, metadata: AtlasImage | undefined) {
        const section = element("section", "detail-section");
        section.append(element("p", "eyebrow", "Capture"));
        const list = element("dl", "detail-list");
        list.append(
            metadataRow("State", variant.title),
            metadataRow("Extent", captureLabel(variant.captureExtent)),
            metadataRow("Profile", deps.catalog.profileByID.get(deps.state.profile)?.title || deps.state.profile),
            metadataRow("Viewport", screen.viewport.kind === "fixed" && screen.viewport.fixedSize
                ? Math.round(screen.viewport.fixedSize.width) + " × " + Math.round(screen.viewport.fixedSize.height)
                : "Profile device"),
            metadataRow("Scale", metadata ? metadata.scale + "×" : "Unknown"),
        );
        section.append(list);
        return section;
    }

    function routeSection(title: string, screen: AtlasScreen, direction: RouteDirection) {
        const section = element("section", "detail-section");
        const ids = direction === "incoming" ? screen.incomingRouteIDs : screen.outgoingRouteIDs;
        section.append(element("p", "eyebrow", title + " · " + ids.length));
        section.append(deps.controls.routeButtons(screen, direction));
        return section;
    }

    function toggleInspectorDetails() {
        deps.state.inspectorDetails = !deps.state.inspectorDetails;
        syncInspectorPresentation();
        // The drawer is still transformed when focus moves. WebKit otherwise scrolls the
        // entire dialog to its offscreen position before the transition completes.
        if (deps.state.inspectorDetails) document.querySelector<HTMLButtonElement>(".details-close")?.focus({ preventScroll: true });
        else document.getElementById("details-trigger")?.focus({ preventScroll: true });
    }

    function syncInspectorPresentation() {
        const dialog = document.getElementById("inspector");
        const drawer = document.getElementById("inspector-details");
        const trigger = document.getElementById("details-trigger");
        if (dialog) dialog.dataset.details = String(deps.state.inspectorDetails);
        if (drawer) {
            drawer.setAttribute("aria-hidden", String(!deps.state.inspectorDetails));
            drawer.inert = !deps.state.inspectorDetails;
        }
        if (trigger) trigger.setAttribute("aria-expanded", String(deps.state.inspectorDetails));
        updateInspectorDetailsAccessibility();
        updateInspectorScale();
    }

    function updateInspectorDetailsAccessibility() {
        const detailsCoverContent = Boolean(
            deps.state.inspectorDetails
            && window.matchMedia?.("(max-width: 760px), (max-height: 520px)")?.matches,
        );
        for (const selector of [".inspection-canvas", ".inspector-dock"]) {
            const content = document.querySelector<HTMLElement>(selector);
            if (!content) continue;
            content.inert = detailsCoverContent;
            content.setAttribute("aria-hidden", String(detailsCoverContent));
        }
    }

    function updateInspectorScale() {
        const image = document.getElementById("inspector-image");
        if (image) image.className = image.className.replace(/ fit| actual/g, "") + " " + deps.state.inspectorScale;
        fitInspectorImage();
        for (const button of document.querySelectorAll(".scale-tabs button")) {
            button.setAttribute("aria-pressed", String(
                (button.textContent === "Fit" && deps.state.inspectorScale === "fit")
                || (button.textContent === "100%" && deps.state.inspectorScale === "actual"),
            ));
        }
    }

    function fitInspectorImage() {
        const frame = document.getElementById("inspector-image");
        const device = frame?.querySelector<HTMLElement>(".inspector-device");
        const screen = deps.state.screen ? deps.catalog.screenByID.get(deps.state.screen) : undefined;
        const variant = screen ? deps.catalog.screenVariant(screen) : null;
        const metadata = screen ? deps.catalog.imageMetadata(screen) : null;
        if (!frame || !device || !metadata || !variant || !screen) return;
        updateCaptureScroller(frame, device, screen, variant);
        if (deps.state.inspectorScale !== "fit"
            || variant.captureExtent === "fullContent"
            || variant.captureExtent === "fullContent2D") {
            device.style.removeProperty("width");
            device.style.removeProperty("height");
            return;
        }
        const aspect = metadata.pointWidth / metadata.pointHeight;
        const width = Math.min(metadata.pointWidth, frame.clientWidth, frame.clientHeight * aspect);
        device.style.width = Math.max(width, 1) + "px";
        device.style.height = Math.max(width / aspect, 1) + "px";
    }

    function updateCaptureScroller(frame: HTMLElement, device: HTMLElement, screen: AtlasScreen, variant: AtlasVariant) {
        configureCaptureScroller(frame, device, screen.title, variant.captureExtent, deps.state.inspectorScale);
    }

    function observeInspectorSize() {
        disconnectInspector();
        const frame = document.getElementById("inspector-image");
        if (!frame || typeof ResizeObserver === "undefined") return;
        inspectorResizeObserver = new ResizeObserver(fitInspectorImage);
        inspectorResizeObserver.observe(frame);
    }

    function disconnectInspector() {
        inspectorResizeObserver?.disconnect();
        inspectorResizeObserver = null;
    }

    return { disconnectInspector, inspector, updateInspectorDetailsAccessibility, fitInspectorImage, observeInspectorSize, toggleInspectorDetails, syncInspectorPresentation };
}
