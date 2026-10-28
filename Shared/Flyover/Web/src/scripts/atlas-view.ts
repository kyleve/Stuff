import type { Actions } from "./actions.ts";
import type { CanvasController } from "./canvas-controller.ts";
import type { Catalog } from "./catalog.ts";
import type { Controls } from "./controls.ts";
import { captureLabel, element, iconButton, quantity, rectStyle } from "./dom.ts";
import type { FilterController } from "./filter-controller.ts";
import type { ImageController } from "./image-controller.ts";
import type { AtlasManifest, AtlasScreen } from "./manifest.ts";
import type { Panels } from "./panels.ts";
import type { Previews } from "./previews.ts";
import type { Session } from "./session.ts";

interface Dependencies {
    state: Session;
    manifest: AtlasManifest;
    catalog: Pick<Catalog, "groupByID" | "screenVariant" | "matchesFilters" | "captureViewportAspect" | "screenByID" | "routeByID">;
    canvas: Pick<CanvasController, "scheduleCanvasNavigationUpdate" | "installCanvasPinch">;
    panels: Pick<Panels, "emptyResults">;
    captures: Pick<Previews, "screenImage">;
    controls: Pick<Controls, "variantSelector" | "routeButton">;
    filters: Pick<FilterController, "setRouteFocus">;
    residency: Pick<ImageController, "scheduleListImageResidencyUpdate">;
    actions: Pick<Actions, "openPanel" | "openScreen">;
}

export interface AtlasView {
    canvasView: () => HTMLElement;
    listView: () => HTMLElement;
}

export function createAtlasView(deps: Dependencies): AtlasView {
    function canvasView() {
        const main = element("main", "canvas-view");
        const context = element("button", "canvas-context");
        context.type = "button";
        context.setAttribute("aria-label", "Browse canvas groups");
        const group = deps.catalog.groupByID.get(deps.state.group) || deps.manifest.groups[0];
        context.append(
            element("span", "context-kicker", "Group " + ((group?.order || 0) + 1) + " of " + deps.manifest.groups.length),
            element("strong", "", group?.title || "Atlas"),
        );
        context.addEventListener("click", () => deps.actions.openPanel("groups", "group-trigger"));
        main.append(context);

        const legend = element("div", "route-legend");
        legend.append(legendItem("push", "Push"), legendItem("modal", "Modal"));
        main.append(legend);

        const viewport = element("section", "canvas-viewport");
        viewport.id = "canvas-viewport";
        viewport.setAttribute("aria-label", "Screen atlas canvas");
        const scaled = element("div", "canvas-scaled");
        scaled.id = "canvas-scaled";
        const stage = element("div", "canvas-stage");
        stage.id = "canvas-stage";
        stage.style.width = deps.manifest.canvas.size.width + "px";
        stage.style.height = deps.manifest.canvas.size.height + "px";

        for (const item of deps.manifest.canvas.groupFrames) {
            const catalogGroup = deps.catalog.groupByID.get(item.id);
            const shelf = element("section", "group-shelf");
            shelf.dataset.groupId = item.id;
            Object.assign(shelf.style, rectStyle(item.frame));
            const shelfHeader = element("header", "shelf-header");
            shelfHeader.append(
                element("span", "shelf-index", String((catalogGroup?.order || 0) + 1).padStart(2, "0")),
                element("h2", "", catalogGroup?.title || item.id),
            );
            shelf.append(shelfHeader);
            stage.append(shelf);
        }
        for (const item of deps.manifest.canvas.depthBandFrames) {
            const band = element("div", "depth-band");
            band.dataset.groupId = item.groupID;
            band.dataset.entry = String(item.kind !== "unlinked" && item.depth === 0);
            Object.assign(band.style, rectStyle(item.frame));
            const title = item.kind === "unlinked" ? "Unlinked" : (item.depth === 0 ? "Entry" : "Depth " + item.depth);
            band.append(element("span", "", title));
            stage.append(band);
        }
        stage.append(routeCanvas());
        for (const screen of deps.manifest.screens) stage.append(screenCard(screen));
        scaled.append(stage);
        viewport.append(scaled);
        viewport.addEventListener("scroll", deps.canvas.scheduleCanvasNavigationUpdate, { passive: true });
        main.append(viewport, deps.panels.emptyResults());

        deps.canvas.installCanvasPinch(viewport);
        return main;
    }

    function legendItem(kind: string, title: string) {
        const item = element("span", "");
        item.append(element("i", kind), document.createTextNode(title));
        return item;
    }

    function screenCard(screen: AtlasScreen) {
        const variant = deps.catalog.screenVariant(screen);
        const card = element("article", "screen-card");
        card.dataset.screenId = screen.id;
        card.dataset.groupId = screen.groupID;
        card.dataset.hidden = String(!deps.catalog.matchesFilters(screen));
        Object.assign(card.style, rectStyle(screen.frame));

        const header = element("header", "card-header");
        const heading = element("div", "card-heading");
        heading.append(element("h3", "", screen.title));
        const inspect = iconButton("fit", "Inspect " + screen.title, "card-inspect");
        inspect.addEventListener("click", () => deps.actions.openScreen(screen.id, true));
        header.append(heading, inspect);

        const imageButton = element("button", "card-image-button");
        imageButton.type = "button";
        imageButton.setAttribute("aria-label", "Inspect " + screen.title);
        imageButton.dataset.focusKey = "atlas-screen-" + screen.id;
        const device = element("span", "device-preview");
        device.dataset.captureExtent = variant?.captureExtent || "viewport";
        device.style.setProperty("--viewport-aspect", String(deps.catalog.captureViewportAspect(screen)));
        device.append(deps.captures.screenImage(screen));
        imageButton.append(device);
        imageButton.addEventListener("click", () => deps.actions.openScreen(screen.id, true));

        const imageMeta = element("div", "card-image-meta");
        const routeCount = screen.incomingRouteIDs.length + screen.outgoingRouteIDs.length;
        imageMeta.append(
            element("span", "capture-badge", captureLabel(variant?.captureExtent)),
            element("span", "route-count", routeCount + (routeCount === 1 ? " route" : " routes")),
        );
        imageButton.append(imageMeta);

        const footer = element("footer", "card-footer");
        if (screen.variants.length > 1) {
            footer.append(element("span", "footer-label", "State"), deps.controls.variantSelector(screen, false, "card-state-select"));
        } else {
            footer.append(element("span", "state-dot"), element("span", "single-state", variant?.title || "Default"));
        }
        card.append(header, imageButton, footer);

        card.addEventListener("pointerenter", () => deps.filters.setRouteFocus(screen.id));
        card.addEventListener("pointerleave", () => {
            if (!card.matches(":focus-within")) deps.filters.setRouteFocus(null);
        });
        card.addEventListener("focusin", () => deps.filters.setRouteFocus(screen.id));
        card.addEventListener("focusout", event => {
            if (!card.contains(event.relatedTarget instanceof Node ? event.relatedTarget : null)) deps.filters.setRouteFocus(null);
        });
        return card;
    }

    function routeCanvas() {
        const namespace = "http://www.w3.org/2000/svg";
        const svg = document.createElementNS(namespace, "svg");
        svg.classList.add("canvas-routes");
        svg.setAttribute("width", String(deps.manifest.canvas.size.width));
        svg.setAttribute("height", String(deps.manifest.canvas.size.height));
        svg.setAttribute("viewBox", "0 0 " + deps.manifest.canvas.size.width + " " + deps.manifest.canvas.size.height);
        for (const route of deps.manifest.routes) {
            const group = document.createElementNS(namespace, "g");
            group.setAttribute("class", "route route-" + route.kind);
            group.dataset.routeId = route.id;
            group.dataset.sourceScreenId = route.sourceScreenID;
            group.dataset.destinationScreenId = route.destinationScreenID;
            const geometry = route.geometry;
            const path = document.createElementNS(namespace, "path");
            path.setAttribute("d", "M " + geometry.start.x + " " + geometry.start.y
                + " C " + geometry.firstControl.x + " " + geometry.firstControl.y
                + ", " + geometry.secondControl.x + " " + geometry.secondControl.y
                + ", " + geometry.end.x + " " + geometry.end.y);
            const arrow = document.createElementNS(namespace, "polygon");
            arrow.setAttribute("points", geometry.end.x + "," + geometry.end.y
                + " " + geometry.firstArrowPoint.x + "," + geometry.firstArrowPoint.y
                + " " + geometry.secondArrowPoint.x + "," + geometry.secondArrowPoint.y);
            group.append(path, arrow);
            svg.append(group);
        }
        return svg;
    }

    function listView() {
        const main = element("main", "list-view");
        main.addEventListener("scroll", deps.residency.scheduleListImageResidencyUpdate, { passive: true });
        const intro = element("header", "list-intro");
        const copy = element("div", "");
        copy.append(element("p", "eyebrow", "Captured catalog"));
        copy.append(element("h2", "", quantity(deps.manifest.screens.length, "screen") + ", ready to review"));
        intro.append(copy, element("p", "list-summary", quantity(deps.manifest.groups.length, "group") + " · "
            + quantity(deps.manifest.routes.length, "route") + " · " + quantity(deps.manifest.profiles.length, "profile")));
        main.append(intro);

        for (const group of deps.manifest.groups) {
            const section = element("section", "list-group");
            section.dataset.listGroupId = group.id;
            const heading = element("header", "list-group-header");
            heading.append(
                element("span", "group-number", String(group.order + 1).padStart(2, "0")),
                element("h2", "", group.title),
                element("span", "group-count", quantity(group.screenIDs.length, "screen")),
            );
            section.append(heading);
            const rows = element("div", "list-rows");
            for (const screenID of group.screenIDs) {
                const screen = screenID ? deps.catalog.screenByID.get(screenID) : undefined;
                if (screen) rows.append(listRow(screen));
            }
            section.append(rows);
            main.append(section);
        }
        main.append(deps.panels.emptyResults());
        return main;
    }

    function listRow(screen: AtlasScreen) {
        const variant = deps.catalog.screenVariant(screen);
        const row = element("article", "list-row");
        row.dataset.screenId = screen.id;
        row.dataset.groupId = screen.groupID;
        row.dataset.hidden = String(!deps.catalog.matchesFilters(screen));

        const thumbnail = element("button", "list-thumbnail");
        thumbnail.type = "button";
        thumbnail.setAttribute("aria-label", "Inspect " + screen.title + ", "
            + screen.incomingRouteIDs.length + " incoming and " + screen.outgoingRouteIDs.length + " outgoing routes");
        thumbnail.dataset.focusKey = "atlas-screen-" + screen.id;
        thumbnail.append(deps.captures.screenImage(screen));
        thumbnail.addEventListener("click", () => deps.actions.openScreen(screen.id, true));

        const identity = element("div", "list-identity");
        identity.append(element("h3", "", screen.title));
        if (screen.variants.length > 1) {
            const stateField = element("label", "list-state");
            stateField.append(element("span", "", "State"), deps.controls.variantSelector(screen));
            identity.append(stateField);
        } else {
            identity.append(element("p", "secondary", variant?.title || "Default"));
        }
        identity.append(element("p", "list-route-summary secondary", screen.incomingRouteIDs.length + " in · "
            + screen.outgoingRouteIDs.length + " out"));

        const facts = element("div", "list-facts");
        facts.append(
            element("span", "capture-badge", captureLabel(variant?.captureExtent)),
            element("span", "secondary", screen.incomingRouteIDs.length + " in · "
                + screen.outgoingRouteIDs.length + " out"),
        );

        const routes = element("div", "list-routes");
        for (const routeID of screen.outgoingRouteIDs) {
            const route = deps.catalog.routeByID.get(routeID);
            if (route) routes.append(deps.controls.routeButton(route, "outgoing"));
        }
        for (const routeID of screen.incomingRouteIDs) {
            const route = deps.catalog.routeByID.get(routeID);
            if (route) routes.append(deps.controls.routeButton(route, "incoming"));
        }

        const inspect = iconButton("right", "Inspect " + screen.title, "list-inspect");
        inspect.addEventListener("click", () => deps.actions.openScreen(screen.id, true));
        row.append(thumbnail, identity, facts, routes, inspect);
        return row;
    }

    return { canvasView, listView };
}
