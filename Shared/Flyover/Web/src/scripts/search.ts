import type { Actions } from "./actions.ts";
import type { Catalog } from "./catalog.ts";
import { element, icon, quantity } from "./dom.ts";
import type { AtlasGroup, AtlasManifest, AtlasRoute, AtlasScreen, AtlasVariant } from "./manifest.ts";
import type { Panels } from "./panels.ts";
import type { CommandEntry, Session } from "./session.ts";

interface Dependencies {
    state: Session;
    manifest: AtlasManifest;
    selectedVariants: Map<string, string>;
    panels: Pick<Panels, "panelShell">;
    catalog: Pick<Catalog, "groupByID" | "searchableText" | "screenByID">;
    actions: Pick<Actions, "closePanel" | "renderOrNavigate" | "openScreen">;
}

export interface Search {
    searchPanel: () => HTMLDialogElement;
}

export function createSearch(deps: Dependencies): Search {
    function searchPanel() {
        const dialog = deps.panels.panelShell("command-palette", "Search the atlas");
        const surface = element("div", "panel-surface command-surface");
        const field = element("label", "command-field");
        field.append(icon("search"));
        const input = element("input", "");
        input.id = "command-search";
        input.type = "search";
        input.autofocus = true;
        input.placeholder = "Find a group, screen, state, or route";
        input.autocomplete = "off";
        input.value = deps.state.commandQuery;
        input.setAttribute("aria-label", "Search groups, screens, states, and routes");
        const close = element("button", "escape-key", "Esc");
        close.type = "button";
        close.setAttribute("aria-label", "Close search");
        close.addEventListener("click", deps.actions.closePanel);
        field.append(input, close);
        const results = element("div", "command-results");
        results.id = "command-results";
        renderCommandResults(results, input.value);
        input.addEventListener("input", () => {
            deps.state.commandQuery = input.value;
            renderCommandResults(results, input.value);
        });
        input.addEventListener("keydown", event => moveCommandFocus(event, results));
        surface.append(field, results);
        dialog.append(surface);
        return dialog;
    }

    function commandEntries(query: string) {
        const terms = query.trim().toLocaleLowerCase().split(/ +/).filter(Boolean);
        if (terms.length === 0) {
            const currentScreens = deps.manifest.screens
                .filter(screen => screen.groupID === deps.state.group)
                .slice(0, 6)
                .map(screen => screenCommand(screen));
            return [...deps.manifest.groups.map(groupCommand), ...currentScreens];
        }

        const entries = [];
        for (const group of deps.manifest.groups) entries.push(groupCommand(group));
        for (const screen of deps.manifest.screens) {
            entries.push(screenCommand(screen));
            for (const variant of screen.variants) entries.push(variantCommand(screen, variant));
        }
        for (const route of deps.manifest.routes) entries.push(routeCommand(route));
        return entries
            .filter(entry => terms.every(term => entry.search.includes(term)))
            .sort((first, second) => commandScore(first, terms) - commandScore(second, terms)
                || first.title.localeCompare(second.title))
            .slice(0, 14);
    }

    function commandScore(entry: CommandEntry, terms: string[]) {
        const title = entry.title.toLocaleLowerCase();
        if (terms.every(term => title === term)) return 0;
        if (terms.every(term => title.startsWith(term))) return 1;
        if (terms.every(term => title.includes(term))) return 2;
        return entry.kind === "Screen" ? 3 : 4;
    }

    function groupCommand(group: AtlasGroup) {
        return {
            kind: "Group",
            title: group.title,
            subtitle: quantity(group.screenIDs.length, "screen"),
            search: (group.title + " group").toLocaleLowerCase(),
            action: () => {
                deps.state.group = group.id;
                deps.state.view = "canvas";
                deps.state.panel = null;
                deps.state.pendingCanvasAction = "fit-group";
                deps.actions.renderOrNavigate();
            },
        };
    }

    function screenCommand(screen: AtlasScreen) {
        const group = deps.catalog.groupByID.get(screen.groupID);
        return {
            kind: "Screen",
            title: screen.title,
            subtitle: (group?.title || "Ungrouped") + " · " + screen.variants.length
                + (screen.variants.length === 1 ? " state" : " states"),
            search: deps.catalog.searchableText(screen),
            action: () => deps.actions.openScreen(screen.id, true),
        };
    }

    function variantCommand(screen: AtlasScreen, variant: AtlasVariant) {
        const group = deps.catalog.groupByID.get(screen.groupID);
        return {
            kind: "State",
            title: screen.title + " — " + variant.title,
            subtitle: group?.title || "Ungrouped",
            search: (screen.title + " " + variant.title + " " + (group?.title || "")).toLocaleLowerCase(),
            action: () => {
                deps.selectedVariants.set(screen.id, variant.id);
                deps.actions.openScreen(screen.id, true);
            },
        };
    }

    function routeCommand(route: AtlasRoute) {
        const source = deps.catalog.screenByID.get(route.sourceScreenID);
        const destination = deps.catalog.screenByID.get(route.destinationScreenID);
        const title = route.label || (source?.title || route.sourceScreenID) + " → "
            + (destination?.title || route.destinationScreenID);
        return {
            kind: route.kind === "modal" ? "Modal route" : "Push route",
            title,
            subtitle: (source?.title || route.sourceScreenID) + " → "
                + (destination?.title || route.destinationScreenID),
            search: (title + " " + route.kind + " " + (source?.title || "") + " "
                + (destination?.title || "")).toLocaleLowerCase(),
            action: () => deps.actions.openScreen(route.destinationScreenID),
        };
    }

    function renderCommandResults(container: HTMLElement, query: string) {
        container.replaceChildren();
        const entries = commandEntries(query);
        container.append(element("p", "command-section-label", query.trim() ? "Best matches" : "Jump to"));
        if (entries.length === 0) {
            const empty = element("div", "command-empty");
            empty.append(element("strong", "", "No matches"), element("span", "", "Try another screen or state name."));
            container.append(empty);
            return;
        }
        entries.forEach((entry, index) => {
            const button = element("button", "command-result");
            button.type = "button";
            button.dataset.commandIndex = String(index);
            const glyph = element("span", "command-glyph");
            glyph.append(icon(entry.kind === "Group" ? "map" : entry.kind.includes("route") ? "route" : "canvas"));
            const copy = element("span", "command-copy");
            copy.append(element("strong", "", entry.title), element("small", "", entry.subtitle));
            button.append(glyph, copy, element("span", "command-kind", entry.kind), icon("right"));
            button.addEventListener("click", entry.action);
            button.addEventListener("keydown", event => {
                if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
                event.preventDefault();
                const buttons = [...container.querySelectorAll<HTMLButtonElement>(".command-result")];
                const offset = event.key === "ArrowDown" ? 1 : -1;
                const next = (index + offset + buttons.length) % buttons.length;
                buttons[next].focus();
            });
            container.append(button);
        });
    }

    function moveCommandFocus(event: KeyboardEvent, results: HTMLElement) {
        if (event.key !== "ArrowDown" && event.key !== "ArrowUp" && event.key !== "Enter") return;
        const buttons = [...results.querySelectorAll<HTMLButtonElement>(".command-result")];
        if (buttons.length === 0) return;
        event.preventDefault();
        if (event.key === "Enter") {
            buttons[0].click();
            return;
        }
        (event.key === "ArrowDown" ? buttons[0] : buttons[buttons.length - 1]).focus();
    }

    return { searchPanel };
}
