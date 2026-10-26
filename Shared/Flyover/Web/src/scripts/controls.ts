import type { Actions } from "./actions.ts";
import type { CanvasController } from "./canvas-controller.ts";
import type { Catalog } from "./catalog.ts";
import { element, icon, iconButton } from "./dom.ts";
import type { AtlasManifest, AtlasRoute, AtlasScreen } from "./manifest.ts";
import type { RouteDirection, Session } from "./session.ts";

interface Dependencies {
    manifest: AtlasManifest;
    state: Session;
    selectedVariants: Map<string, string>;
    canvas: Pick<CanvasController, "setZoom" | "fitCurrentGroup" | "fitAll">;
    catalog: Pick<Catalog, "groupByID" | "screenByID" | "routeByID">;
    actions: Pick<Actions, "chooseProfile" | "openPanel" | "chooseView" | "chooseVariant" | "openScreen">;
}

export interface Controls {
    variantSelector: (screen: AtlasScreen, updateHistory?: boolean, className?: string) => HTMLSelectElement;
    routeButton: (route: AtlasRoute, direction: RouteDirection) => HTMLButtonElement;
    profileSelect: (className?: string, focusKey?: string) => HTMLSelectElement;
    routeButtons: (screen: AtlasScreen, direction: RouteDirection) => HTMLDivElement;
    appHeader: () => HTMLElement;
    bottomDock: () => HTMLElement;
}

export function createControls(deps: Dependencies): Controls {
    function profileSelect(className = "", focusKey = "profile") {
        const select = element("select", className);
        select.setAttribute("aria-label", "Capture profile");
        select.dataset.focusKey = focusKey;
        for (const item of deps.manifest.profiles) {
            const option = element("option", "", item.title);
            option.value = item.id;
            option.selected = item.id === deps.state.profile;
            select.append(option);
        }
        select.addEventListener("change", () => deps.actions.chooseProfile(select.value));
        return select;
    }

    function appHeader() {
        const header = element("header", "app-header");
        const identity = element("div", "app-identity");
        const brandMark = element("span", "brand-mark", "F");
        brandMark.setAttribute("aria-hidden", "true");
        identity.append(brandMark);
        const copy = element("div", "identity-copy");
        copy.append(element("span", "product-label", "Flyover"), element("h1", "", deps.manifest.application.title));
        identity.append(copy);

        const actions = element("div", "header-actions");
        const profile = element("label", "header-profile");
        profile.append(
            element("span", "visually-hidden", "Capture profile"),
            profileSelect("", "header-profile"),
        );
        actions.append(profile);

        const search = iconButton("search", "Search", "header-button search-trigger", true);
        search.id = "search-trigger";
        search.setAttribute("aria-keyshortcuts", "/ Meta+K Control+K");
        search.append(element("kbd", "", "⌘K"));
        search.addEventListener("click", () => deps.actions.openPanel("search", search.id));
        actions.append(search);

        const build = iconButton("info", "Build details", "header-button build-trigger");
        build.id = "build-trigger";
        build.append(element("code", "commit-label", deps.manifest.build.commit.slice(0, 8)));
        if (deps.manifest.build.dirty) {
            build.setAttribute("aria-label", "Build details, uncommitted changes");
            build.title = "Build details, uncommitted changes";
            build.append(element("span", "dirty-dot"));
        }
        build.addEventListener("click", () => deps.actions.openPanel("build", build.id));
        actions.append(build);
        header.append(identity, actions);
        return header;
    }

    function bottomDock() {
        const dock = element("nav", "bottom-dock");
        dock.setAttribute("aria-label", "Atlas controls");

        const viewTabs = element("div", "segmented-control view-tabs");
        viewTabs.setAttribute("aria-label", "Atlas view");
        for (const item of ([["canvas", "canvas", "Canvas"], ["list", "list", "List"]] as const)) {
            const button = iconButton(item[1], item[2], "segment", true);
            button.setAttribute("aria-pressed", String(deps.state.view === item[0]));
            button.dataset.focusKey = "view-" + item[0];
            button.addEventListener("click", () => deps.actions.chooseView(item[0]));
            viewTabs.append(button);
        }
        dock.append(viewTabs, element("span", "dock-separator"));

        if (deps.state.view === "canvas") {
            const zoom = element("div", "zoom-controls");
            const minus = iconButton("minus", "Zoom out");
            minus.addEventListener("click", () => deps.canvas.setZoom(deps.state.zoom - 0.1));
            const value = element("output", "zoom-value", Math.round(deps.state.zoom * 100) + "%");
            value.id = "zoom-value";
            const plus = iconButton("plus", "Zoom in");
            plus.addEventListener("click", () => deps.canvas.setZoom(deps.state.zoom + 0.1));
            zoom.append(minus, value, plus);

            const fitGroup = iconButton("fit", "Fit current group", "dock-action", true);
            fitGroup.setAttribute("aria-keyshortcuts", "0");
            fitGroup.addEventListener("click", () => deps.canvas.fitCurrentGroup());
            const fitAllButton = iconButton("fit", "Fit all", "dock-action fit-all", true);
            fitAllButton.setAttribute("aria-keyshortcuts", "F");
            fitAllButton.addEventListener("click", () => deps.canvas.fitAll());
            dock.append(zoom, fitGroup, fitAllButton, element("span", "dock-separator"));
        }

        const groups = iconButton("map", "Browse groups", "dock-action group-trigger", true);
        groups.id = "group-trigger";
        const currentGroup = deps.catalog.groupByID.get(deps.state.group);
        groups.querySelector(".button-label")!.textContent = currentGroup?.title || "Groups";
        groups.addEventListener("click", () => deps.actions.openPanel("groups", groups.id));
        dock.append(groups);

        const filters = iconButton("filter", "Filters", "dock-action filter-trigger", true);
        filters.id = "filter-trigger";
        filters.dataset.focusKey = "filters-control";
        filters.append(element("span", "filter-badge"));
        filters.addEventListener("click", () => deps.actions.openPanel("filters", filters.id));
        dock.append(filters);

        const count = element("span", "result-count");
        count.id = "result-count";
        count.setAttribute("aria-live", "polite");
        dock.append(count);
        return dock;
    }

    function variantSelector(screen: AtlasScreen, updateHistory = false, className = "") {
        const select = element("select", className);
        select.setAttribute("aria-label", "State for " + screen.title);
        select.dataset.focusKey = (updateHistory ? "inspector-state-" : "atlas-state-") + screen.id;
        for (const variant of screen.variants) {
            const option = element("option", "", variant.title);
            option.value = variant.id;
            option.selected = variant.id === deps.selectedVariants.get(screen.id);
            select.append(option);
        }
        select.addEventListener("change", event => {
            event.stopPropagation();
            deps.actions.chooseVariant(screen, select.value, updateHistory);
        });
        return select;
    }

    function routeButton(route: AtlasRoute, direction: RouteDirection) {
        const destinationID = direction === "outgoing" ? route.destinationScreenID : route.sourceScreenID;
        const destination = deps.catalog.screenByID.get(destinationID);
        const cue = direction === "outgoing"
            ? (route.kind === "modal" ? "Modal" : "Push")
            : (route.kind === "modal" ? "Presented from" : "Back to");
        const title = direction === "outgoing" && route.label
            ? route.label : (destination?.title || destinationID);
        const button = element("button", "route-chip " + route.kind);
        button.type = "button";
        button.append(icon("route"), element("span", "", cue + " · " + title));
        button.addEventListener("click", event => {
            event.stopPropagation();
            deps.actions.openScreen(destinationID);
        });
        return button;
    }

    function routeButtons(screen: AtlasScreen, direction: RouteDirection) {
        const links = element("div", "route-links");
        const ids = direction === "incoming" ? screen.incomingRouteIDs : screen.outgoingRouteIDs;
        for (const id of ids) {
            const route = deps.catalog.routeByID.get(id);
            if (route) links.append(routeButton(route, direction));
        }
        if (ids.length === 0) links.append(element("span", "no-routes", "None"));
        return links;
    }

    return { variantSelector, routeButton, profileSelect, routeButtons, appHeader, bottomDock };
}
