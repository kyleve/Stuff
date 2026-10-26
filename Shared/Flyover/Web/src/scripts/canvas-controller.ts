import type { Actions } from "./actions.ts";
import type { Catalog } from "./catalog.ts";
import { element, rectAttributes } from "./dom.ts";
import { fittedZoom, initialZoom, manualZoom, touchDistance, touchMidpoint } from "./geometry.ts";
import type { ImageController } from "./image-controller.ts";
import type { AtlasManifest, Rect } from "./manifest.ts";
import type { Session } from "./session.ts";

interface Dependencies {
    state: Session;
    manifest: AtlasManifest;
    residency: Pick<ImageController, "updateCanvasImageResidency">;
    catalog: Pick<Catalog, "groupByID">;
    actions: Pick<Actions, "renderOrNavigate">;
}

export interface CanvasController {
    setZoom: (next: number) => void;
    fitCurrentGroup: (behavior?: ScrollBehavior) => void;
    fitAll: (behavior?: ScrollBehavior) => void;
    scheduleCanvasNavigationUpdate: () => void;
    installCanvasPinch: (viewport: HTMLElement) => void;
    miniMap: () => HTMLDivElement;
    captureViewPosition: () => void;
    cancelCanvasWork: () => void;
    restoreCanvasView: () => void;
    updateMiniMapViewport: () => void;
}

export function createCanvasController(deps: Dependencies): CanvasController {
    const minimumManualZoom = 0.1;

    const maximumZoom = 1.5;

    function restoreCanvasView() {
        const viewport = document.getElementById("canvas-viewport");
        if (!viewport) return;
        applyZoom();
        if (deps.state.pendingCanvasAction === "fit-initial") {
            deps.state.pendingCanvasAction = null;
            fitFirstGroup();
        } else if (deps.state.pendingCanvasAction === "fit-group") {
            deps.state.pendingCanvasAction = null;
            fitCurrentGroup("auto");
        } else if (deps.state.pendingCanvasAction === "fit-all") {
            deps.state.pendingCanvasAction = null;
            fitAll("auto");
        } else if (deps.state.pendingCanvasPosition) {
            const position = deps.state.pendingCanvasPosition;
            deps.state.pendingCanvasPosition = null;
            viewport.scrollTo(position);
            deps.state.canvas.scrollLeft = position.left;
            deps.state.canvas.scrollTop = position.top;
            updateCanvasNavigation();
        } else if (!deps.state.canvas.initialized) {
            fitFirstGroup();
        } else {
            viewport.scrollTo({ left: deps.state.canvas.scrollLeft, top: deps.state.canvas.scrollTop });
            updateCanvasNavigation();
        }
        deps.state.canvas.initialized = true;
        // Explicit navigation already changed state.group; retained labels still need a refresh.
        updateActiveGroup();
        deps.residency.updateCanvasImageResidency();
    }

    function miniMap() {
        const namespace = "http://www.w3.org/2000/svg";
        const wrapper = element("div", "mini-map");
        const svg = document.createElementNS(namespace, "svg");
        svg.id = "mini-map-svg";
        svg.setAttribute("viewBox", "0 0 " + deps.manifest.canvas.size.width + " " + deps.manifest.canvas.size.height);
        svg.setAttribute("role", "group");
        svg.setAttribute("tabindex", "0");
        svg.setAttribute("aria-label", "Canvas overview. Select a position or use arrow keys to pan the atlas.");
        for (const group of deps.manifest.canvas.groupFrames) {
            const rect = document.createElementNS(namespace, "rect");
            Object.entries(rectAttributes(group.frame)).forEach(([key, value]) => rect.setAttribute(key, String(value)));
            rect.setAttribute("class", "mini-group");
            rect.dataset.groupId = group.id;
            svg.append(rect);
        }
        for (const screen of deps.manifest.screens) {
            const rect = document.createElementNS(namespace, "rect");
            Object.entries(rectAttributes(screen.frame)).forEach(([key, value]) => rect.setAttribute(key, String(value)));
            rect.setAttribute("class", "mini-screen");
            rect.dataset.screenId = screen.id;
            svg.append(rect);
        }
        const visible = document.createElementNS(namespace, "rect");
        visible.id = "mini-map-viewport";
        visible.setAttribute("class", "mini-viewport");
        svg.append(visible);
        svg.addEventListener("click", event => moveFromMiniMap(svg, event.clientX, event.clientY));
        svg.addEventListener("keydown", event => {
            const offsets: Record<string, number[]> = {
                ArrowLeft: [-0.4, 0],
                ArrowRight: [0.4, 0],
                ArrowUp: [0, -0.4],
                ArrowDown: [0, 0.4],
            };
            const offset = offsets[event.key];
            if (!offset) return;
            event.preventDefault();
            const viewport = document.getElementById("canvas-viewport");
            const { width, height } = canvasViewportSize(viewport);
            if (viewport) {
                viewport.scrollBy({ left: width * offset[0], top: height * offset[1] });
                scheduleCanvasNavigationUpdate();
                return;
            }
            queueCanvasPosition(
                deps.state.canvas.scrollLeft + width * offset[0],
                deps.state.canvas.scrollTop + height * offset[1],
            );
        });
        wrapper.append(svg);
        return wrapper;
    }

    function moveFromMiniMap(svg: SVGSVGElement, clientX: number, clientY: number) {
        const matrix = svg.getScreenCTM();
        if (!matrix) return;
        const point = new DOMPoint(clientX, clientY).matrixTransform(matrix.inverse());
        const viewport = document.getElementById("canvas-viewport");
        const { width, height } = canvasViewportSize(viewport);
        queueCanvasPosition(point.x * deps.state.zoom - width / 2, point.y * deps.state.zoom - height / 2);
    }

    function queueCanvasPosition(left: number, top: number) {
        const viewport = document.getElementById("canvas-viewport");
        const { width: viewportWidth, height: viewportHeight } = canvasViewportSize(viewport);
        const maximumLeft = Math.max(deps.manifest.canvas.size.width * deps.state.zoom - viewportWidth, 0);
        const maximumTop = Math.max(deps.manifest.canvas.size.height * deps.state.zoom - viewportHeight, 0);
        deps.state.pendingCanvasPosition = {
            left: Math.min(Math.max(left, 0), maximumLeft),
            top: Math.min(Math.max(top, 0), maximumTop),
        };
        deps.state.canvas.initialized = true;
        deps.state.view = "canvas";
        deps.state.panel = null;
        deps.actions.renderOrNavigate();
    }

    function installCanvasPinch(viewport: HTMLElement) {
        let gesture: { distance: number; zoom: number; minimumZoom: number; canvasX: number; canvasY: number } | null = null;
        viewport.addEventListener("touchstart", event => {
            if (event.touches.length !== 2) return;
            const midpoint = touchMidpoint(event.touches);
            const bounds = viewport.getBoundingClientRect();
            gesture = {
                distance: touchDistance(event.touches),
                zoom: deps.state.zoom,
                minimumZoom: Math.min(minimumManualZoom, deps.state.zoom),
                canvasX: (viewport.scrollLeft + midpoint.x - bounds.left) / deps.state.zoom,
                canvasY: (viewport.scrollTop + midpoint.y - bounds.top) / deps.state.zoom,
            };
        }, { passive: true });
        viewport.addEventListener("touchmove", event => {
            if (!gesture || event.touches.length !== 2) return;
            event.preventDefault();
            const midpoint = touchMidpoint(event.touches);
            const bounds = viewport.getBoundingClientRect();
            const nextZoom = Math.max(gesture.minimumZoom, Math.min(maximumZoom,
                gesture.zoom * touchDistance(event.touches) / Math.max(gesture.distance, 1)));
            deps.state.zoom = nextZoom;
            applyZoom();
            viewport.scrollTo({
                left: gesture.canvasX * nextZoom - (midpoint.x - bounds.left),
                top: gesture.canvasY * nextZoom - (midpoint.y - bounds.top),
            });
            captureCanvasPosition();
            scheduleCanvasNavigationUpdate();
        }, { passive: false });
        const endGesture = (event: TouchEvent) => {
            if (event.touches.length < 2) gesture = null;
        };
        viewport.addEventListener("touchend", endGesture, { passive: true });
        viewport.addEventListener("touchcancel", endGesture, { passive: true });
    }

    function captureCanvasPosition() {
        const viewport = document.getElementById("canvas-viewport");
        if (!viewport) return;
        deps.state.canvas.scrollLeft = viewport.scrollLeft;
        deps.state.canvas.scrollTop = viewport.scrollTop;
        deps.state.canvas.viewportWidth = viewport.clientWidth;
        deps.state.canvas.viewportHeight = viewport.clientHeight;
    }

    function captureListPosition() {
        const list = document.querySelector(".list-view");
        if (list) deps.state.list.scrollTop = list.scrollTop;
    }

    function captureViewPosition() {
        captureCanvasPosition();
        captureListPosition();
    }

    function applyZoom() {
        const stage = document.getElementById("canvas-stage");
        const scaled = document.getElementById("canvas-scaled");
        if (!stage || !scaled) return;
        stage.style.transform = "scale(" + deps.state.zoom + ")";
        scaled.style.width = deps.manifest.canvas.size.width * deps.state.zoom + "px";
        scaled.style.height = deps.manifest.canvas.size.height * deps.state.zoom + "px";
        const value = document.getElementById("zoom-value");
        if (value) value.textContent = Math.round(deps.state.zoom * 100) + "%";
        updateMiniMapViewport();
    }

    function setZoom(next: number) {
        const viewport = document.getElementById("canvas-viewport");
        if (viewport) acceptCanvasInteraction();
        const oldZoom = deps.state.zoom;
        const center = viewport ? {
            x: (viewport.scrollLeft + viewport.clientWidth / 2) / oldZoom,
            y: (viewport.scrollTop + viewport.clientHeight / 2) / oldZoom,
        } : null;
        deps.state.zoom = manualZoom(next, oldZoom, minimumManualZoom, maximumZoom);
        applyZoom();
        if (viewport && center) {
            viewport.scrollTo({
                left: center.x * deps.state.zoom - viewport.clientWidth / 2,
                top: center.y * deps.state.zoom - viewport.clientHeight / 2,
            });
            captureCanvasPosition();
        }
        deps.residency.updateCanvasImageResidency();
    }

    function fitFrame(frame: Rect, behavior: ScrollBehavior = "smooth") {
        const viewport = document.getElementById("canvas-viewport");
        if (!viewport) return;
        acceptCanvasInteraction();
        deps.state.zoom = fittedZoom(frame, { width: viewport.clientWidth, height: viewport.clientHeight }, maximumZoom);
        applyZoom();
        const left = (frame.x + frame.width / 2) * deps.state.zoom - viewport.clientWidth / 2;
        const top = (frame.y + frame.height / 2) * deps.state.zoom - viewport.clientHeight / 2;
        const prefersReducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches;
        viewport.scrollTo({ left, top, behavior: prefersReducedMotion ? "auto" : behavior });
        deps.state.canvas.scrollLeft = Math.max(0, left);
        deps.state.canvas.scrollTop = Math.max(0, top);
        deps.residency.updateCanvasImageResidency();
    }

    function acceptCanvasInteraction() {
        // Explicit input supersedes initialization/restoration queued for a later frame.
        deps.state.canvas.initialized = true;
        deps.state.pendingCanvasAction = null;
        deps.state.pendingCanvasPosition = null;
    }

    function fitAll(behavior: ScrollBehavior = "smooth") {
        fitFrame({ x: 0, y: 0, width: deps.manifest.canvas.size.width, height: deps.manifest.canvas.size.height }, behavior);
    }

    function fitCurrentGroup(behavior: ScrollBehavior = "smooth") {
        const group = deps.manifest.canvas.groupFrames.find(item => item.id === deps.state.group)
            || deps.manifest.canvas.groupFrames[0];
        if (group) fitFrame(group.frame, behavior);
    }

    function fitFirstGroup() {
        const viewport = document.getElementById("canvas-viewport");
        if (!viewport) return;
        const initialWidth = deps.manifest.canvas.initialFitSize?.width
            || deps.manifest.canvas.groupFrames[0]?.frame.width;
        if (!initialWidth) return;
        deps.state.zoom = initialZoom(initialWidth, viewport.clientWidth);
        applyZoom();
        viewport.scrollTo({ left: 0, top: 0, behavior: "auto" });
        deps.state.canvas.scrollLeft = 0;
        deps.state.canvas.scrollTop = 0;
        updateCanvasNavigation();
    }

    let canvasNavigationFrame: number | null = null;

    function cancelCanvasWork() {
        if (canvasNavigationFrame !== null) cancelAnimationFrame(canvasNavigationFrame);
        canvasNavigationFrame = null;
    }

    function scheduleCanvasNavigationUpdate() {
        if (canvasNavigationFrame !== null) return;
        canvasNavigationFrame = requestAnimationFrame(() => {
            canvasNavigationFrame = null;
            captureCanvasPosition();
            updateCanvasNavigation();
            deps.residency.updateCanvasImageResidency();
        });
    }

    function updateCanvasNavigation() {
        const viewport = document.getElementById("canvas-viewport");
        if (!viewport) return;
        const centerX = (viewport.scrollLeft + viewport.clientWidth / 2) / deps.state.zoom;
        const centerY = (viewport.scrollTop + viewport.clientHeight / 2) / deps.state.zoom;
        let nearest = null;
        let nearestDistance = Number.POSITIVE_INFINITY;
        for (const group of deps.manifest.canvas.groupFrames) {
            const frame = group.frame;
            const dx = Math.max(frame.x - centerX, 0, centerX - frame.x - frame.width);
            const dy = Math.max(frame.y - centerY, 0, centerY - frame.y - frame.height);
            const distance = dx * dx + dy * dy;
            if (distance < nearestDistance) {
                nearest = group.id;
                nearestDistance = distance;
            }
        }
        if (nearest && nearest !== deps.state.group) {
            deps.state.group = nearest;
            updateActiveGroup();
        }
        updateMiniMapViewport();
    }

    function updateActiveGroup() {
        for (const button of document.querySelectorAll<HTMLElement>(".group-button")) {
            button.setAttribute("aria-current", String(button.dataset.groupId === deps.state.group));
        }
        for (const group of document.querySelectorAll<SVGRectElement>(".mini-group")) {
            group.dataset.active = String(group.dataset.groupId === deps.state.group);
        }
        const current = deps.catalog.groupByID.get(deps.state.group);
        const context = document.querySelector(".canvas-context");
        if (context && current) {
            context.querySelector(".context-kicker")!.textContent = "Group " + (current.order + 1)
                + " of " + deps.manifest.groups.length;
            context.querySelector("strong")!.textContent = current.title;
        }
        const dockLabel = document.querySelector(".group-trigger .button-label");
        if (dockLabel && current) dockLabel.textContent = current.title;
    }

    function updateMiniMapViewport() {
        const viewport = document.getElementById("canvas-viewport");
        const rect = document.getElementById("mini-map-viewport");
        if (!rect) return;
        const { width, height } = canvasViewportSize(viewport);
        const scrollLeft = viewport?.scrollLeft ?? deps.state.canvas.scrollLeft;
        const scrollTop = viewport?.scrollTop ?? deps.state.canvas.scrollTop;
        rect.setAttribute("x", String(scrollLeft / deps.state.zoom));
        rect.setAttribute("y", String(scrollTop / deps.state.zoom));
        rect.setAttribute("width", String(width / deps.state.zoom));
        rect.setAttribute("height", String(height / deps.state.zoom));
    }

    function canvasViewportSize(viewport: HTMLElement | null) {
        return {
            width: viewport?.clientWidth || deps.state.canvas.viewportWidth || window.innerWidth,
            height: viewport?.clientHeight || deps.state.canvas.viewportHeight || window.innerHeight,
        };
    }

    return { setZoom, fitCurrentGroup, fitAll, scheduleCanvasNavigationUpdate, installCanvasPinch, miniMap, captureViewPosition, cancelCanvasWork, restoreCanvasView, updateMiniMapViewport };
}
