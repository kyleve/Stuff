import type { Catalog } from "./catalog.ts";
import { captureLabel, element } from "./dom.ts";
import type { AtlasScreen } from "./manifest.ts";
import type { Session } from "./session.ts";

interface Dependencies {
    root: HTMLElement;
    state: Session;
    catalog: Pick<Catalog, "imagePath" | "thumbnailPath" | "screenVariant" | "screenByID" | "captureViewportAspect">;
}

export interface Previews {
    screenImage: (screen: AtlasScreen, className?: string, eager?: boolean, fullResolution?: boolean) => HTMLImageElement;
    updatePreviews: () => void;
}

export function createPreviews(deps: Dependencies): Previews {
    function screenImage(screen: AtlasScreen, className = "", eager = false, fullResolution = false) {
        const image = element("img", className);
        image.draggable = false;
        image.loading = eager ? "eager" : "lazy";
        image.decoding = "async";
        const source = fullResolution ? deps.catalog.imagePath(screen) : deps.catalog.thumbnailPath(screen);
        if (eager) image.src = source;
        else image.dataset.src = source;
        image.dataset.captureExtent = deps.catalog.screenVariant(screen)?.captureExtent || "viewport";
        image.alt = screen.title + " — " + (deps.catalog.screenVariant(screen)?.title || "Default");
        return image;
    }

    function updatePreviews() {
        for (const card of deps.root.querySelectorAll<HTMLElement>(".screen-card, .list-row")) {
            const screen = deps.catalog.screenByID.get(card.dataset.screenId!);
            if (!screen) continue;
            const variant = deps.catalog.screenVariant(screen);
            const image = card.querySelector("img");
            if (image) {
                image.dataset.src = deps.catalog.thumbnailPath(screen);
                image.dataset.captureExtent = variant.captureExtent;
                image.alt = screen.title + " — " + variant.title;
            }
            const select = card.querySelector("select");
            if (select) select.value = variant.id;
            const badge = card.querySelector(".capture-badge");
            if (badge) badge.textContent = captureLabel(variant.captureExtent);
            const device = card.querySelector<HTMLElement>(".device-preview");
            if (device) {
                device.dataset.captureExtent = variant.captureExtent;
                device.style.setProperty("--viewport-aspect", String(deps.catalog.captureViewportAspect(screen)));
            }
        }
        const profile = deps.root.querySelector<HTMLSelectElement>(".header-profile select");
        if (profile) profile.value = deps.state.profile;
    }

    return { screenImage, updatePreviews };
}
