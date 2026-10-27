import type { Catalog } from "./catalog.ts";
import { rectIntersects, squaredDistance } from "./geometry.ts";
import type { ImageCandidate } from "./image-residency.ts";
import { selectResidentImages } from "./image-residency.ts";
import type { AtlasManifest } from "./manifest.ts";
import type { Session } from "./session.ts";

interface Dependencies {
    state: Session;
    manifest: AtlasManifest;
    catalog: Pick<Catalog, "matchesFilters" | "screenImagePixels" | "screenByID">;
}

export interface ImageController {
    scheduleListImageResidencyUpdate: () => void;
    updateCanvasImageResidency: () => void;
    updateListImageResidency: () => void;
    cancelImageWork: () => void;
}

export function createImageController(deps: Dependencies): ImageController {
    const targetResidentImageCount = 6;

    const targetResidentPixelCount = 24_000_000;

    function residentScreenIDs(candidates: ImageCandidate[]) {
        return selectResidentImages(candidates, targetResidentImageCount, targetResidentPixelCount);
    }

    function updateCanvasImageResidency() {
        const viewport = document.getElementById("canvas-viewport");
        if (!viewport || deps.state.view !== "canvas") return;
        if (deps.state.screen) {
            updateResidentImages(".screen-card", new Set());
            return;
        }
        const visibleRect = {
            left: viewport.scrollLeft / deps.state.zoom,
            top: viewport.scrollTop / deps.state.zoom,
            right: (viewport.scrollLeft + viewport.clientWidth) / deps.state.zoom,
            bottom: (viewport.scrollTop + viewport.clientHeight) / deps.state.zoom,
        };
        const center = {
            x: (visibleRect.left + visibleRect.right) / 2,
            y: (visibleRect.top + visibleRect.bottom) / 2,
        };
        const candidates = deps.manifest.screens
            .filter(screen => deps.catalog.matchesFilters(screen) && rectIntersects(screen.frame, visibleRect))
            .map(screen => ({
                screen,
                imagePixels: deps.catalog.screenImagePixels(screen),
                isVisible: true,
                distance: squaredDistance(screen.frame.x + screen.frame.width / 2,
                    screen.frame.y + screen.frame.height / 2, center.x, center.y),
            }))
            .sort((lhs, rhs) => lhs.distance - rhs.distance
                || lhs.screen.frame.y - rhs.screen.frame.y
                || lhs.screen.frame.x - rhs.screen.frame.x);
        updateResidentImages(".screen-card", residentScreenIDs(candidates));
    }

    let listResidencyFrame: number | null = null;

    function cancelImageWork() {
        if (listResidencyFrame !== null) cancelAnimationFrame(listResidencyFrame);
        listResidencyFrame = null;
    }

    function scheduleListImageResidencyUpdate() {
        if (listResidencyFrame !== null) return;
        listResidencyFrame = requestAnimationFrame(() => {
            listResidencyFrame = null;
            updateListImageResidency();
        });
    }

    function updateListImageResidency() {
        const list = document.querySelector(".list-view");
        if (!list || deps.state.view !== "list") return;
        if (deps.state.screen) {
            updateResidentImages(".list-row", new Set());
            return;
        }
        const viewport = list.getBoundingClientRect();
        const centerY = (viewport.top + viewport.bottom) / 2;
        const candidates = [];
        for (const row of document.querySelectorAll<HTMLElement>(".list-row")) {
            const screen = deps.catalog.screenByID.get(row.dataset.screenId!);
            if (!screen || !deps.catalog.matchesFilters(screen)) continue;
            const frame = row.getBoundingClientRect();
            if (frame.bottom < viewport.top - 120 || frame.top > viewport.bottom + 120) continue;
            candidates.push({
                screen,
                imagePixels: deps.catalog.screenImagePixels(screen),
                isVisible: frame.bottom > viewport.top && frame.top < viewport.bottom,
                distance: Math.abs((frame.top + frame.bottom) / 2 - centerY),
            });
        }
        candidates.sort((lhs, rhs) => lhs.distance - rhs.distance || lhs.screen.screenOrder - rhs.screen.screenOrder);
        updateResidentImages(".list-row", residentScreenIDs(candidates));
    }

    function updateResidentImages(containerSelector: string, residentIDs: Set<string>) {
        for (const container of document.querySelectorAll<HTMLElement>(containerSelector)) {
            const image = container.querySelector<HTMLImageElement>("img[data-src]");
            if (!image) continue;
            if (residentIDs.has(container.dataset.screenId!)) {
                image.loading = "eager";
                if (image.getAttribute("src") !== image.dataset.src) image.src = image.dataset.src!;
            } else {
                image.removeAttribute("src");
                image.loading = "lazy";
            }
        }
    }

    return { scheduleListImageResidencyUpdate, updateCanvasImageResidency, updateListImageResidency, cancelImageWork };
}
