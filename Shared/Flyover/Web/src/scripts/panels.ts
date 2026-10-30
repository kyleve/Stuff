import type { Actions } from "./actions.ts";
import type { CanvasController } from "./canvas-controller.ts";
import type { Catalog } from "./catalog.ts";
import { element, formatGeneratedAt, icon, iconButton, metadataRow, quantity } from "./dom.ts";
import type { FilterController } from "./filter-controller.ts";
import { FrameScope } from "./frame-scope.ts";
import type { AtlasManifest } from "./manifest.ts";
import type { Search } from "./search.ts";
import type { Session } from "./session.ts";

interface Dependencies {
    state: Session;
    manifest: AtlasManifest;
    renderFrames: FrameScope;
    search: Pick<Search, "searchPanel">;
    canvas: Pick<CanvasController, "miniMap">;
    filters: Pick<FilterController, "updateSearchVisibility">;
    catalog: Pick<Catalog, "matchesFilters">;
    actions: Pick<Actions, "closePanel" | "renderOrNavigate" | "render">;
}

export interface Panels {
    emptyResults: () => HTMLElement;
    panelShell: (className: string, label: string) => HTMLDialogElement;
    activePanel: () => HTMLDialogElement | null;
}

export function createPanels(deps: Dependencies): Panels {
    function activePanel() {
        if (!deps.state.panel || deps.state.screen) return null;
        if (deps.state.panel === "search") return deps.search.searchPanel();
        if (deps.state.panel === "groups") return groupsPanel();
        if (deps.state.panel === "filters") return filtersPanel();
        if (deps.state.panel === "build") return buildPanel();
        return null;
    }

    function panelShell(className: string, label: string) {
        const dialog = element("dialog", "panel " + className);
        dialog.setAttribute("aria-label", label);
        dialog.addEventListener("cancel", event => {
            event.preventDefault();
            deps.actions.closePanel();
        });
        dialog.addEventListener("click", event => {
            if (event.target === dialog) deps.actions.closePanel();
        });
        return dialog;
    }

    function panelHeader(kicker: string, title: string) {
        const header = element("header", "panel-header");
        const copy = element("div", "");
        copy.append(element("p", "eyebrow", kicker), element("h2", "", title));
        const close = iconButton("close", "Close", "icon-button panel-close");
        close.addEventListener("click", deps.actions.closePanel);
        header.append(copy, close);
        return header;
    }

    function groupsPanel() {
        const dialog = panelShell("sheet-panel groups-panel", "Browse groups");
        const surface = element("div", "panel-surface sheet-surface");
        surface.append(panelHeader("Navigate", "Groups"));
        surface.append(deps.canvas.miniMap());
        const navigation = element("nav", "group-navigation");
        navigation.setAttribute("aria-label", "Canvas groups");
        for (const group of deps.manifest.groups) {
            const button = element("button", "group-button");
            button.type = "button";
            button.dataset.groupId = group.id;
            button.setAttribute("aria-current", String(group.id === deps.state.group));
            const copy = element("span", "");
            copy.append(
                element("strong", "", group.title),
                element("small", "", quantity(group.screenIDs.length, "screen")),
            );
            button.append(element("span", "group-index", String(group.order + 1).padStart(2, "0")), copy, icon("right"));
            button.addEventListener("click", () => {
                deps.state.group = group.id;
                deps.state.view = "canvas";
                deps.state.panel = null;
                deps.state.pendingCanvasAction = "fit-group";
                deps.actions.renderOrNavigate();
            });
            navigation.append(button);
        }
        surface.append(navigation);
        dialog.append(surface);
        return dialog;
    }

    function filtersPanel() {
        const dialog = panelShell("sheet-panel filters-panel", "Filter screens");
        const surface = element("div", "panel-surface sheet-surface");
        surface.append(panelHeader("Refine", "Filters"));
        const fields = element("div", "filter-fields");
        const groupOptions = [["all", "All groups"], ...deps.manifest.groups.map(group => [group.id, group.title])];
        fields.append(
            filterSelect("Group", deps.state.filters.group, groupOptions, value => {
                deps.state.filters.group = value;
                deps.filters.updateSearchVisibility();
            }),
            filterSelect("Capture", deps.state.filters.extent, [
                ["all", "All captures"], ["viewport", "Viewport"], ["intrinsic", "Intrinsic"],
                ["fullContent", "Full content"], ["fullContent2D", "Full content 2D"],
            ], value => {
                deps.state.filters.extent = value;
                deps.filters.updateSearchVisibility();
            }),
            filterSelect("Routes", deps.state.filters.routes, [
                ["all", "Any route state"], ["linked", "Linked"], ["unlinked", "Unlinked"],
                ["incoming", "Has incoming"], ["outgoing", "Has outgoing"],
            ], value => {
                deps.state.filters.routes = value;
                deps.filters.updateSearchVisibility();
            }),
        );
        surface.append(fields);
        const footer = element("footer", "panel-footer");
        const clear = element("button", "secondary-button", "Reset filters");
        clear.type = "button";
        clear.addEventListener("click", () => {
            deps.state.filters = { group: "all", extent: "all", routes: "all" };
            showFilteredResults();
        });
        const done = element("button", "primary-button", "Show results");
        done.type = "button";
        done.addEventListener("click", showFilteredResults);
        footer.append(clear, done);
        surface.append(footer);
        dialog.append(surface);
        return dialog;
    }

    function showFilteredResults() {
        const matchingScreens = deps.manifest.screens.filter(deps.catalog.matchesFilters);
        if (deps.state.view === "canvas" && matchingScreens.length > 0) {
            const currentGroupHasMatch = matchingScreens.some(screen => screen.groupID === deps.state.group);
            deps.state.group = currentGroupHasMatch ? deps.state.group : matchingScreens[0].groupID;
            deps.state.pendingCanvasAction = "fit-group";
        } else if (deps.state.view === "list") {
            const list = document.querySelector(".list-view");
            if (list) list.scrollTop = 0;
            deps.state.list.scrollTop = 0;
        }
        deps.actions.closePanel();
    }

    function filterSelect(labelText: string, value: string, options: string[][], onChange: (value: string) => void) {
        const label = element("label", "filter-field");
        label.append(element("span", "field-label", labelText));
        const select = element("select", "");
        for (const pair of options) {
            const option = element("option", "", pair[1]);
            option.value = pair[0];
            option.selected = pair[0] === value;
            select.append(option);
        }
        select.addEventListener("change", () => onChange(select.value));
        label.append(select);
        return label;
    }

    function buildPanel() {
        const dialog = panelShell("sheet-panel build-panel", "Build details");
        const surface = element("div", "panel-surface sheet-surface");
        surface.append(panelHeader("Artifact", "Build details"));
        const status = element("div", "build-status");
        status.append(element("span", deps.manifest.build.dirty ? "status-dot dirty" : "status-dot"));
        const copy = element("div", "");
        copy.append(
            element("strong", "", deps.manifest.build.dirty ? "Uncommitted changes" : "Clean build"),
            element("span", "", formatGeneratedAt(deps.manifest.build.generatedAt)),
        );
        status.append(copy);
        const list = element("dl", "detail-list build-list");
        list.append(
            metadataRow("Commit", deps.manifest.build.commit), metadataRow("Branch", deps.manifest.build.branch || "Detached"),
            metadataRow("Xcode", deps.manifest.build.xcodeVersion), metadataRow("Simulator", deps.manifest.build.simulatorDevice),
            metadataRow("Simulator OS", deps.manifest.build.simulatorOS),
        );
        surface.append(status, list);
        dialog.append(surface);
        return dialog;
    }

    function emptyResults() {
        const empty = element("section", "empty-results");
        empty.id = "empty-results";
        empty.hidden = true;
        empty.append(icon("filter"), element("h2", "", "No screens match"));
        empty.append(element("p", "", "Change the filters to show more of the atlas."));
        const clear = element("button", "primary-button", "Reset filters");
        clear.type = "button";
        clear.addEventListener("click", () => {
            deps.state.filters = { group: "all", extent: "all", routes: "all" };
            deps.actions.render();
            deps.renderFrames.request(() => document.getElementById("filter-trigger")?.focus());
        });
        empty.append(clear);
        return empty;
    }

    return { emptyResults, panelShell, activePanel };
}
