import type { Catalog } from "./catalog.ts";
import type { ImageController } from "./image-controller.ts";
import type { AtlasManifest } from "./manifest.ts";
import type { Session } from "./session.ts";

interface Dependencies {
    manifest: AtlasManifest;
    state: Session;
    catalog: Pick<Catalog, "visibleScreenIDs" | "screenByID" | "routeByID">;
    residency: Pick<ImageController, "updateCanvasImageResidency" | "updateListImageResidency">;
}

export interface FilterController {
    setRouteFocus: (screenID: string | null) => void;
    updateSearchVisibility: () => void;
}

export function createFilterController(deps: Dependencies): FilterController {
    function updateSearchVisibility() {
        const visible = deps.catalog.visibleScreenIDs();
        for (const node of document.querySelectorAll<HTMLElement | SVGElement>("[data-screen-id]")) {
            if (node.matches(".route")) continue;
            node.dataset.hidden = String(!visible.has(node.dataset.screenId!));
        }
        for (const group of deps.manifest.groups) {
            const hasResults = group.screenIDs.some(id => visible.has(id));
            for (const node of document.querySelectorAll<HTMLElement | SVGElement>('[data-group-id="' + CSS.escape(group.id) + '"]')) {
                node.dataset.empty = String(!hasResults);
            }
            const listGroup = document.querySelector<HTMLElement>('[data-list-group-id="' + CSS.escape(group.id) + '"]');
            if (listGroup) listGroup.hidden = !hasResults;
        }
        for (const route of document.querySelectorAll<SVGGElement>(".route")) {
            const sourceVisible = visible.has(route.dataset.sourceScreenId!);
            const destinationVisible = visible.has(route.dataset.destinationScreenId!);
            route.dataset.hidden = String(!sourceVisible || !destinationVisible);
        }
        const count = document.getElementById("result-count");
        if (count) count.textContent = visible.size + " / " + deps.manifest.screens.length;
        const empty = document.getElementById("empty-results");
        if (empty) empty.hidden = visible.size !== 0;
        updateFilterStatus();
        updateRouteFocus();
        if (deps.state.view === "canvas") deps.residency.updateCanvasImageResidency();
        else deps.residency.updateListImageResidency();
    }

    function updateFilterStatus() {
        const activeCount = Object.values(deps.state.filters).filter(value => value !== "all").length;
        const button = document.getElementById("filter-trigger");
        if (!button) return;
        button.dataset.active = String(activeCount > 0);
        button.setAttribute("aria-label", activeCount > 0 ? "Filters, " + activeCount + " active" : "Filters");
        const badge = button.querySelector(".filter-badge");
        if (badge) badge.textContent = activeCount > 0 ? String(activeCount) : "";
    }

    function setRouteFocus(screenID: string | null) {
        deps.state.routeFocus = screenID;
        updateRouteFocus();
    }

    function updateRouteFocus() {
        const focused = deps.state.routeFocus;
        const connected = new Map<string, "upstream" | "downstream">();
        if (focused) {
            const screen = deps.catalog.screenByID.get(focused);
            for (const id of screen?.incomingRouteIDs || []) {
                const route = deps.catalog.routeByID.get(id);
                if (route) connected.set(route.sourceScreenID, "upstream");
            }
            for (const id of screen?.outgoingRouteIDs || []) {
                const route = deps.catalog.routeByID.get(id);
                if (route) connected.set(route.destinationScreenID, "downstream");
            }
        }
        for (const card of document.querySelectorAll<HTMLElement>(".screen-card")) {
            card.dataset.routeRelation = card.dataset.screenId === focused
                ? "focus" : (connected.get(card.dataset.screenId!) || (focused ? "unrelated" : "none"));
        }
        for (const route of document.querySelectorAll<SVGGElement>(".route")) {
            const isConnected = route.dataset.sourceScreenId === focused
                || route.dataset.destinationScreenId === focused;
            route.dataset.routeRelation = isConnected ? "focus" : (focused ? "unrelated" : "none");
        }
    }

    return { setRouteFocus, updateSearchVisibility };
}
