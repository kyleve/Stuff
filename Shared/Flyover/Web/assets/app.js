(() => {
    "use strict";

    const root = document.getElementById("app");
    const manifest = window.FLYOVER_MANIFEST;
    if (!manifest || manifest.schemaVersion !== 1) {
        root.innerHTML = '<main class="error"><p class="eyebrow">Manifest error</p><h1>Flyover cannot open this atlas</h1><p>This site requires manifest schema version 1.</p></main>';
        return;
    }

    const screenByID = new Map(manifest.screens.map(screen => [screen.id, screen]));
    const groupByID = new Map(manifest.groups.map(group => [group.id, group]));
    const routeByID = new Map(manifest.routes.map(route => [route.id, route]));
    const profileByID = new Map(manifest.profiles.map(profile => [profile.id, profile]));
    const imageByKey = new Map(manifest.images.map(image => [
        imageKey(image.screenID, image.variantID, image.profileID),
        image,
    ]));
    const selectedVariants = new Map(manifest.screens.map(screen => [screen.id, screen.variants[0]?.id]));
    const state = {
        view: "canvas",
        profile: manifest.profiles[0]?.id,
        screen: null,
        zoom: 1,
        group: manifest.groups[0]?.id,
        routeFocus: null,
        inspectorScale: "fit",
        inspectorDetails: false,
        panel: null,
        panelTrigger: null,
        commandQuery: "",
        pendingCanvasAction: null,
        canvas: {
            initialized: false,
            scrollLeft: 0,
            scrollTop: 0,
        },
        filters: {
            group: "all",
            extent: "all",
            routes: "all",
        },
    };

    const iconPaths = {
        canvas: "M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z",
        close: "M6 6l12 12M18 6 6 18",
        external: "M14 4h6v6M20 4l-9 9M18 13v6a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h6",
        filter: "M4 6h16M7 12h10M10 18h4",
        fit: "M8 3H3v5M16 3h5v5M8 21H3v-5M16 21h5v-5",
        info: "M12 11v6M12 7h.01M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",
        left: "m15 18-6-6 6-6",
        list: "M9 6h11M9 12h11M9 18h11M4 6h.01M4 12h.01M4 18h.01",
        map: "m3 6 6-3 6 3 6-3v15l-6 3-6-3-6 3V6Zm6-3v15m6-12v15",
        minus: "M5 12h14",
        plus: "M12 5v14M5 12h14",
        right: "m9 18 6-6-6-6",
        route: "M5 6h7a4 4 0 0 1 4 4v8m-4-4 4 4 4-4",
        search: "m21 21-4.35-4.35M19 11a8 8 0 1 1-16 0 8 8 0 0 1 16 0Z",
    };

    function element(tag, className, text) {
        const value = document.createElement(tag);
        if (className) value.className = className;
        if (text !== undefined) value.textContent = text;
        return value;
    }

    function icon(name) {
        const namespace = "http://www.w3.org/2000/svg";
        const svg = document.createElementNS(namespace, "svg");
        svg.setAttribute("viewBox", "0 0 24 24");
        svg.setAttribute("aria-hidden", "true");
        svg.classList.add("icon");
        const path = document.createElementNS(namespace, "path");
        path.setAttribute("d", iconPaths[name]);
        svg.append(path);
        return svg;
    }

    function iconButton(iconName, label, className = "icon-button", visibleLabel = false) {
        const button = element("button", className);
        button.type = "button";
        button.setAttribute("aria-label", label);
        button.title = label;
        button.append(icon(iconName));
        if (visibleLabel) button.append(element("span", "button-label", label));
        return button;
    }

    function screenVariant(screen) {
        const id = selectedVariants.get(screen.id);
        return screen.variants.find(variant => variant.id === id) || screen.variants[0];
    }

    function imagePath(screen) {
        return screenVariant(screen)?.imagesByProfile[state.profile] || "";
    }

    function imageKey(screenID, variantID, profileID) {
        return JSON.stringify([screenID, variantID, profileID]);
    }

    function imageMetadata(screen) {
        const variant = screenVariant(screen);
        return imageByKey.get(imageKey(screen.id, variant?.id, state.profile));
    }

    function connectedRoutes(screen) {
        return [...screen.incomingRouteIDs, ...screen.outgoingRouteIDs]
            .map(id => routeByID.get(id))
            .filter(Boolean);
    }

    function searchableText(screen) {
        const group = groupByID.get(screen.groupID);
        const routeText = connectedRoutes(screen).flatMap(route => {
            const source = screenByID.get(route.sourceScreenID);
            const destination = screenByID.get(route.destinationScreenID);
            return [route.label, route.kind, source?.title, destination?.title];
        });
        return [group?.title, screen.title, ...screen.variants.map(variant => variant.title), ...routeText]
            .filter(Boolean)
            .join(" ")
            .toLocaleLowerCase();
    }

    function matchesFilters(screen) {
        if (state.filters.group !== "all" && screen.groupID !== state.filters.group) return false;
        if (state.filters.extent !== "all" && screenVariant(screen)?.captureExtent !== state.filters.extent) {
            return false;
        }
        if (state.filters.routes === "incoming" && screen.incomingRouteIDs.length === 0) return false;
        if (state.filters.routes === "outgoing" && screen.outgoingRouteIDs.length === 0) return false;
        if (state.filters.routes === "linked"
            && screen.incomingRouteIDs.length + screen.outgoingRouteIDs.length === 0) return false;
        if (state.filters.routes === "unlinked"
            && screen.incomingRouteIDs.length + screen.outgoingRouteIDs.length !== 0) return false;
        return true;
    }

    function visibleScreenIDs() {
        return new Set(manifest.screens.filter(matchesFilters).map(screen => screen.id));
    }

    function parseHash() {
        const values = new URLSearchParams(location.hash.replace(/^#/, ""));
        const view = values.get("view");
        const profile = values.get("profile");
        const screenID = values.get("screen");
        const variantID = values.get("variant");
        if (view === "canvas" || view === "list") state.view = view;
        if (profileByID.has(profile)) state.profile = profile;
        if (screenByID.has(screenID)) {
            state.screen = screenID;
            const screen = screenByID.get(screenID);
            if (screen.variants.some(variant => variant.id === variantID)) selectedVariants.set(screenID, variantID);
        } else {
            state.screen = null;
        }
    }

    function writeHash() {
        const values = new URLSearchParams();
        values.set("view", state.view);
        values.set("profile", state.profile);
        if (state.screen) {
            values.set("screen", state.screen);
            values.set("variant", selectedVariants.get(state.screen));
        }
        const next = "#" + values;
        if (location.hash === next) return false;
        location.hash = next;
        return true;
    }

    function renderOrNavigate() {
        if (!writeHash()) render();
    }

    function chooseView(view) {
        state.view = view;
        state.panel = null;
        if (view === "canvas" && !state.canvas.initialized) state.pendingCanvasAction = "fit-group";
        renderOrNavigate();
    }

    function chooseProfile(profile) {
        state.profile = profile;
        renderOrNavigate();
    }

    function chooseVariant(screen, variantID, updateHistory = false) {
        selectedVariants.set(screen.id, variantID);
        if (state.screen === screen.id || updateHistory) {
            state.screen = screen.id;
            renderOrNavigate();
        } else {
            render();
        }
    }

    function openScreen(screenID, preserveVariant = false) {
        const screen = screenByID.get(screenID);
        if (!screen) return;
        if (!preserveVariant) selectedVariants.set(screen.id, screen.variants[0]?.id);
        state.screen = screen.id;
        state.routeFocus = screen.id;
        state.inspectorScale = "fit";
        state.inspectorDetails = false;
        state.panel = null;
        renderOrNavigate();
    }

    function neighboringScreen(offset) {
        const index = manifest.screens.findIndex(screen => screen.id === state.screen);
        if (index < 0) return null;
        const next = (index + offset + manifest.screens.length) % manifest.screens.length;
        return manifest.screens[next];
    }

    function formatGeneratedAt(value) {
        const date = new Date(value);
        if (Number.isNaN(date.valueOf())) return value;
        return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(date);
    }

    function metadataRow(label, value) {
        const row = element("div", "metadata-row");
        row.append(element("dt", "", label), element("dd", "", value));
        return row;
    }

    function profileSelect(className = "") {
        const select = element("select", className);
        select.setAttribute("aria-label", "Capture profile");
        for (const item of manifest.profiles) {
            const option = element("option", "", item.title);
            option.value = item.id;
            option.selected = item.id === state.profile;
            select.append(option);
        }
        select.addEventListener("change", () => chooseProfile(select.value));
        return select;
    }

    function appHeader() {
        const header = element("header", "app-header");
        const identity = element("div", "app-identity");
        identity.append(element("span", "brand-mark", "F"));
        const copy = element("div", "identity-copy");
        copy.append(element("span", "product-label", "Flyover"), element("h1", "", manifest.application.title));
        identity.append(copy);

        const actions = element("div", "header-actions");
        const profile = element("label", "header-profile");
        profile.append(element("span", "visually-hidden", "Capture profile"), profileSelect());
        actions.append(profile);

        const search = iconButton("search", "Search", "header-button search-trigger", true);
        search.id = "search-trigger";
        search.setAttribute("aria-keyshortcuts", "/ Meta+K Control+K");
        search.append(element("kbd", "", "⌘K"));
        search.addEventListener("click", () => openPanel("search", search.id));
        actions.append(search);

        const build = iconButton("info", "Build details", "header-button build-trigger");
        build.id = "build-trigger";
        build.append(element("code", "commit-label", manifest.build.commit.slice(0, 8)));
        if (manifest.build.dirty) build.append(element("span", "dirty-dot"));
        build.addEventListener("click", () => openPanel("build", build.id));
        actions.append(build);
        header.append(identity, actions);
        return header;
    }

    function bottomDock() {
        const dock = element("nav", "bottom-dock");
        dock.setAttribute("aria-label", "Atlas controls");

        const viewTabs = element("div", "segmented-control view-tabs");
        viewTabs.setAttribute("aria-label", "Atlas view");
        for (const item of [["canvas", "canvas", "Canvas"], ["list", "list", "List"]]) {
            const button = iconButton(item[1], item[2], "segment", true);
            button.setAttribute("aria-pressed", String(state.view === item[0]));
            button.addEventListener("click", () => chooseView(item[0]));
            viewTabs.append(button);
        }
        dock.append(viewTabs, element("span", "dock-separator"));

        if (state.view === "canvas") {
            const zoom = element("div", "zoom-controls");
            const minus = iconButton("minus", "Zoom out");
            minus.addEventListener("click", () => setZoom(state.zoom - 0.1));
            const value = element("output", "zoom-value", Math.round(state.zoom * 100) + "%");
            value.id = "zoom-value";
            const plus = iconButton("plus", "Zoom in");
            plus.addEventListener("click", () => setZoom(state.zoom + 0.1));
            zoom.append(minus, value, plus);

            const fitGroup = iconButton("fit", "Fit current group", "dock-action", true);
            fitGroup.setAttribute("aria-keyshortcuts", "0");
            fitGroup.addEventListener("click", () => fitCurrentGroup());
            const fitAllButton = iconButton("fit", "Fit all", "dock-action fit-all", true);
            fitAllButton.setAttribute("aria-keyshortcuts", "F");
            fitAllButton.addEventListener("click", () => fitAll());
            dock.append(zoom, fitGroup, fitAllButton, element("span", "dock-separator"));
        }

        const groups = iconButton("map", "Browse groups", "dock-action group-trigger", true);
        groups.id = "group-trigger";
        const currentGroup = groupByID.get(state.group);
        groups.querySelector(".button-label").textContent = currentGroup?.title || "Groups";
        groups.addEventListener("click", () => openPanel("groups", groups.id));
        dock.append(groups);

        const filters = iconButton("filter", "Filters", "dock-action filter-trigger", true);
        filters.id = "filter-trigger";
        filters.append(element("span", "filter-badge"));
        filters.addEventListener("click", () => openPanel("filters", filters.id));
        dock.append(filters);

        const count = element("span", "result-count");
        count.id = "result-count";
        count.setAttribute("aria-live", "polite");
        dock.append(count);
        return dock;
    }

    function variantSelector(screen, updateHistory = false, className = "") {
        const select = element("select", className);
        select.setAttribute("aria-label", "State for " + screen.title);
        for (const variant of screen.variants) {
            const option = element("option", "", variant.title);
            option.value = variant.id;
            option.selected = variant.id === selectedVariants.get(screen.id);
            select.append(option);
        }
        select.addEventListener("change", event => {
            event.stopPropagation();
            chooseVariant(screen, select.value, updateHistory);
        });
        return select;
    }

    function routeButton(route, screen, direction) {
        const destinationID = direction === "outgoing" ? route.destinationScreenID : route.sourceScreenID;
        const destination = screenByID.get(destinationID);
        const cue = direction === "outgoing"
            ? (route.kind === "modal" ? "Modal" : "Push")
            : (route.kind === "modal" ? "Presented from" : "Back to");
        const button = element("button", "route-chip " + route.kind);
        button.type = "button";
        button.append(icon("route"), element("span", "", cue + " · " + (destination?.title || destinationID)));
        button.addEventListener("click", event => {
            event.stopPropagation();
            openScreen(destinationID);
        });
        return button;
    }

    function routeButtons(screen, direction) {
        const links = element("div", "route-links");
        const ids = direction === "incoming" ? screen.incomingRouteIDs : screen.outgoingRouteIDs;
        for (const id of ids) {
            const route = routeByID.get(id);
            if (route) links.append(routeButton(route, screen, direction));
        }
        if (ids.length === 0) links.append(element("span", "no-routes", "None"));
        return links;
    }

    function screenImage(screen, className = "", eager = false) {
        const image = element("img", className);
        image.loading = eager ? "eager" : "lazy";
        image.decoding = "async";
        image.src = imagePath(screen);
        image.alt = screen.title + " — " + (screenVariant(screen)?.title || "Default");
        return image;
    }

    function captureLabel(extent) {
        if (extent === "fullContent") return "Full content";
        if (extent === "fullContent2D") return "Full content 2D";
        if (!extent) return "Viewport";
        return extent[0].toUpperCase() + extent.slice(1);
    }

    function canvasView() {
        const main = element("main", "canvas-view");
        const context = element("button", "canvas-context");
        context.type = "button";
        context.setAttribute("aria-label", "Browse canvas groups");
        const group = groupByID.get(state.group) || manifest.groups[0];
        context.append(
            element("span", "context-kicker", "Group " + ((group?.order || 0) + 1) + " of " + manifest.groups.length),
            element("strong", "", group?.title || "Atlas"),
        );
        context.addEventListener("click", () => openPanel("groups", "group-trigger"));
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
        stage.style.width = manifest.canvas.size.width + "px";
        stage.style.height = manifest.canvas.size.height + "px";

        for (const item of manifest.canvas.groupFrames) {
            const catalogGroup = groupByID.get(item.id);
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
        for (const item of manifest.canvas.depthBandFrames) {
            const band = element("div", "depth-band");
            band.dataset.groupId = item.groupID;
            Object.assign(band.style, rectStyle(item.frame));
            band.append(element("span", "", item.kind === "unlinked" ? "Unlinked" : "Depth " + item.depth));
            stage.append(band);
        }
        stage.append(routeCanvas());
        for (const screen of manifest.screens) stage.append(screenCard(screen));
        scaled.append(stage);
        viewport.append(scaled);
        viewport.addEventListener("scroll", scheduleCanvasNavigationUpdate, { passive: true });
        main.append(viewport, emptyResults());

        requestAnimationFrame(() => {
            applyZoom();
            updateSearchVisibility();
            if (state.pendingCanvasAction === "fit-group") {
                state.pendingCanvasAction = null;
                fitCurrentGroup("auto");
            } else if (state.pendingCanvasAction === "fit-all") {
                state.pendingCanvasAction = null;
                fitAll("auto");
            } else if (!state.canvas.initialized) {
                fitFirstGroup();
            } else {
                viewport.scrollTo({ left: state.canvas.scrollLeft, top: state.canvas.scrollTop });
                updateCanvasNavigation();
            }
            state.canvas.initialized = true;
        });
        return main;
    }

    function legendItem(kind, title) {
        const item = element("span", "");
        item.append(element("i", kind), document.createTextNode(title));
        return item;
    }

    function screenCard(screen) {
        const variant = screenVariant(screen);
        const card = element("article", "screen-card");
        card.dataset.screenId = screen.id;
        card.dataset.groupId = screen.groupID;
        card.dataset.hidden = String(!matchesFilters(screen));
        card.tabIndex = 0;
        Object.assign(card.style, rectStyle(screen.frame));

        const header = element("header", "card-header");
        const heading = element("div", "card-heading");
        heading.append(element("h3", "", screen.title));
        const inspect = iconButton("fit", "Inspect " + screen.title, "card-inspect");
        inspect.addEventListener("click", () => openScreen(screen.id, true));
        header.append(heading, inspect);

        const imageButton = element("button", "card-image-button");
        imageButton.type = "button";
        imageButton.setAttribute("aria-label", "Inspect " + screen.title);
        const device = element("span", "device-preview");
        device.append(screenImage(screen));
        imageButton.append(device);
        imageButton.addEventListener("click", () => openScreen(screen.id, true));

        const imageMeta = element("div", "card-image-meta");
        const routeCount = screen.incomingRouteIDs.length + screen.outgoingRouteIDs.length;
        imageMeta.append(
            element("span", "capture-badge", captureLabel(variant?.captureExtent)),
            element("span", "route-count", routeCount + (routeCount === 1 ? " route" : " routes")),
        );
        imageButton.append(imageMeta);

        const footer = element("footer", "card-footer");
        if (screen.variants.length > 1) {
            footer.append(element("span", "footer-label", "State"), variantSelector(screen, false, "card-state-select"));
        } else {
            footer.append(element("span", "state-dot"), element("span", "single-state", variant?.title || "Default"));
        }
        card.append(header, imageButton, footer);

        card.addEventListener("pointerenter", () => setRouteFocus(screen.id));
        card.addEventListener("pointerleave", () => {
            if (!card.matches(":focus-within")) setRouteFocus(null);
        });
        card.addEventListener("focusin", () => setRouteFocus(screen.id));
        card.addEventListener("focusout", event => {
            if (!card.contains(event.relatedTarget)) setRouteFocus(null);
        });
        card.addEventListener("keydown", event => {
            if (event.key === "Enter" && event.target === card) openScreen(screen.id, true);
        });
        return card;
    }

    function routeCanvas() {
        const namespace = "http://www.w3.org/2000/svg";
        const svg = document.createElementNS(namespace, "svg");
        svg.classList.add("canvas-routes");
        svg.setAttribute("width", manifest.canvas.size.width);
        svg.setAttribute("height", manifest.canvas.size.height);
        svg.setAttribute("viewBox", "0 0 " + manifest.canvas.size.width + " " + manifest.canvas.size.height);
        for (const route of manifest.routes) {
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

    function rectStyle(rect) {
        return { left: rect.x + "px", top: rect.y + "px", width: rect.width + "px", height: rect.height + "px" };
    }

    function listView() {
        const main = element("main", "list-view");
        const intro = element("header", "list-intro");
        const copy = element("div", "");
        copy.append(element("p", "eyebrow", "Captured catalog"));
        copy.append(element("h2", "", manifest.screens.length + " screens, ready to review"));
        intro.append(copy, element("p", "list-summary", manifest.groups.length + " groups · "
            + manifest.routes.length + " routes · " + manifest.profiles.length + " profiles"));
        main.append(intro);

        for (const group of manifest.groups) {
            const section = element("section", "list-group");
            section.dataset.listGroupId = group.id;
            const heading = element("header", "list-group-header");
            heading.append(
                element("span", "group-number", String(group.order + 1).padStart(2, "0")),
                element("h2", "", group.title),
                element("span", "group-count", group.screenIDs.length + " screens"),
            );
            section.append(heading);
            const rows = element("div", "list-rows");
            for (const screenID of group.screenIDs) {
                const screen = screenByID.get(screenID);
                if (screen) rows.append(listRow(screen));
            }
            section.append(rows);
            main.append(section);
        }
        main.append(emptyResults());
        requestAnimationFrame(updateSearchVisibility);
        return main;
    }

    function listRow(screen) {
        const variant = screenVariant(screen);
        const row = element("article", "list-row");
        row.dataset.screenId = screen.id;
        row.dataset.groupId = screen.groupID;
        row.dataset.hidden = String(!matchesFilters(screen));

        const thumbnail = element("button", "list-thumbnail");
        thumbnail.type = "button";
        thumbnail.setAttribute("aria-label", "Inspect " + screen.title);
        thumbnail.append(screenImage(screen));
        thumbnail.addEventListener("click", () => openScreen(screen.id, true));

        const identity = element("div", "list-identity");
        identity.append(element("h3", "", screen.title));
        if (screen.variants.length > 1) {
            const stateField = element("label", "list-state");
            stateField.append(element("span", "", "State"), variantSelector(screen));
            identity.append(stateField);
        } else {
            identity.append(element("p", "secondary", variant?.title || "Default"));
        }

        const facts = element("div", "list-facts");
        facts.append(
            element("span", "capture-badge", captureLabel(variant?.captureExtent)),
            element("span", "secondary", screen.incomingRouteIDs.length + " in · "
                + screen.outgoingRouteIDs.length + " out"),
        );

        const routes = element("div", "list-routes");
        const quickRouteID = screen.outgoingRouteIDs[0] || screen.incomingRouteIDs[0];
        const quickRoute = routeByID.get(quickRouteID);
        if (quickRoute) {
            const direction = quickRoute.sourceScreenID === screen.id ? "outgoing" : "incoming";
            routes.append(routeButton(quickRoute, screen, direction));
        }

        const inspect = iconButton("right", "Inspect " + screen.title, "list-inspect");
        inspect.addEventListener("click", () => openScreen(screen.id, true));
        row.append(thumbnail, identity, facts, routes, inspect);
        return row;
    }

    function inspector() {
        const screen = screenByID.get(state.screen);
        if (!screen) return null;
        const variant = screenVariant(screen);
        const metadata = imageMetadata(screen);
        const group = groupByID.get(screen.groupID);
        const screenIndex = manifest.screens.findIndex(item => item.id === screen.id);
        const dialog = element("dialog", "inspector");
        dialog.id = "inspector";
        dialog.dataset.details = String(state.inspectorDetails);
        dialog.setAttribute("aria-labelledby", "inspector-title");

        const header = element("header", "inspector-header");
        const heading = element("div", "inspector-heading");
        heading.append(
            element("p", "eyebrow", (group?.title || "Ungrouped") + " · "
                + (screenIndex + 1) + " of " + manifest.screens.length),
            element("h2", "", screen.title),
        );
        heading.querySelector("h2").id = "inspector-title";
        const actions = element("div", "inspector-header-actions");
        const raw = element("a", "inspector-action", "PNG");
        raw.href = imagePath(screen);
        raw.target = "_blank";
        raw.rel = "noopener";
        raw.setAttribute("aria-label", "Open raw PNG");
        raw.append(icon("external"));
        const details = iconButton("info", "Capture details", "inspector-action", true);
        details.id = "details-trigger";
        details.setAttribute("aria-expanded", String(state.inspectorDetails));
        details.addEventListener("click", toggleInspectorDetails);
        const close = iconButton("close", "Close inspector", "inspector-action close-inspector");
        close.autofocus = true;
        close.addEventListener("click", closeInspector);
        actions.append(raw, details, close);
        header.append(heading, actions);

        const canvas = element("section", "inspection-canvas");
        const extentClass = variant.captureExtent === "fullContent"
            || variant.captureExtent === "fullContent2D" ? " full-content" : "";
        const imageFrame = element("div", "inspector-image " + state.inspectorScale + extentClass);
        imageFrame.id = "inspector-image";
        const device = element("div", "inspector-device");
        const fullImage = screenImage(screen, "", true);
        if (metadata) {
            device.style.setProperty("--point-width", metadata.pointWidth + "px");
            device.style.setProperty("--aspect-ratio", metadata.pointWidth / metadata.pointHeight);
        }
        device.append(fullImage);
        imageFrame.append(device);
        const caption = element("div", "image-caption");
        caption.append(element("span", "capture-badge", captureLabel(variant.captureExtent)), element("span", "", imageDimensions(metadata)));
        canvas.append(imageFrame, caption);

        const drawer = element("aside", "inspector-details");
        drawer.id = "inspector-details";
        drawer.setAttribute("aria-hidden", String(!state.inspectorDetails));
        drawer.inert = !state.inspectorDetails;
        const drawerHeader = element("header", "details-header");
        drawerHeader.append(element("p", "eyebrow", "Screen details"), element("h3", "", screen.title));
        const drawerClose = iconButton("close", "Close details", "icon-button details-close");
        drawerClose.addEventListener("click", toggleInspectorDetails);
        drawerHeader.append(drawerClose);
        drawer.append(drawerHeader, inspectorMetadata(screen, variant, metadata));
        drawer.append(routeSection("Outgoing", screen, "outgoing"));
        drawer.append(routeSection("Incoming", screen, "incoming"));

        dialog.append(header, canvas, drawer, inspectorDock(screen));
        dialog.addEventListener("cancel", event => {
            event.preventDefault();
            if (state.inspectorDetails) toggleInspectorDetails();
            else closeInspector();
        });
        return dialog;
    }

    function inspectorDock(screen) {
        const dock = element("nav", "inspector-dock");
        dock.setAttribute("aria-label", "Inspector controls");
        const previous = iconButton("left", "Previous screen", "icon-button inspector-previous");
        previous.setAttribute("aria-keyshortcuts", "ArrowLeft [");
        previous.addEventListener("click", () => openScreen(neighboringScreen(-1)?.id));
        dock.append(previous, element("span", "dock-separator"));

        const stateField = element("label", "inspector-field");
        stateField.append(element("span", "field-label", "State"), variantSelector(screen, true));
        const profileField = element("label", "inspector-field profile-field");
        profileField.append(element("span", "field-label", "Profile"), profileSelect());
        dock.append(stateField, profileField, element("span", "dock-separator"));

        const scale = element("div", "segmented-control scale-tabs");
        scale.setAttribute("aria-label", "Image scale");
        for (const option of [["fit", "Fit"], ["actual", "100%"]]) {
            const button = element("button", "segment", option[1]);
            button.type = "button";
            button.setAttribute("aria-pressed", String(state.inspectorScale === option[0]));
            button.addEventListener("click", () => {
                state.inspectorScale = option[0];
                updateInspectorScale();
            });
            scale.append(button);
        }
        dock.append(scale, element("span", "dock-separator"));

        const next = iconButton("right", "Next screen", "icon-button inspector-next");
        next.setAttribute("aria-keyshortcuts", "ArrowRight ]");
        next.addEventListener("click", () => openScreen(neighboringScreen(1)?.id));
        dock.append(next);
        return dock;
    }

    function imageDimensions(metadata) {
        if (!metadata) return "Image metadata unavailable";
        return Math.round(metadata.pointWidth) + " × " + Math.round(metadata.pointHeight) + " pt · "
            + metadata.pixelWidth + " × " + metadata.pixelHeight + " px @" + metadata.scale + "×";
    }

    function inspectorMetadata(screen, variant, metadata) {
        const section = element("section", "detail-section");
        section.append(element("p", "eyebrow", "Capture"));
        const list = element("dl", "detail-list");
        list.append(
            metadataRow("State", variant.title),
            metadataRow("Extent", captureLabel(variant.captureExtent)),
            metadataRow("Profile", profileByID.get(state.profile)?.title || state.profile),
            metadataRow("Viewport", screen.viewport.kind === "fixed" && screen.viewport.fixedSize
                ? Math.round(screen.viewport.fixedSize.width) + " × " + Math.round(screen.viewport.fixedSize.height)
                : "Profile device"),
            metadataRow("Scale", metadata ? metadata.scale + "×" : "Unknown"),
        );
        section.append(list);
        return section;
    }

    function routeSection(title, screen, direction) {
        const section = element("section", "detail-section");
        const ids = direction === "incoming" ? screen.incomingRouteIDs : screen.outgoingRouteIDs;
        section.append(element("p", "eyebrow", title + " · " + ids.length));
        section.append(routeButtons(screen, direction));
        return section;
    }

    function toggleInspectorDetails() {
        state.inspectorDetails = !state.inspectorDetails;
        const dialog = document.getElementById("inspector");
        const drawer = document.getElementById("inspector-details");
        const trigger = document.getElementById("details-trigger");
        if (dialog) dialog.dataset.details = String(state.inspectorDetails);
        if (drawer) {
            drawer.setAttribute("aria-hidden", String(!state.inspectorDetails));
            drawer.inert = !state.inspectorDetails;
        }
        if (trigger) trigger.setAttribute("aria-expanded", String(state.inspectorDetails));
        if (state.inspectorDetails) drawer?.querySelector(".details-close")?.focus();
        else trigger?.focus();
    }

    function updateInspectorScale() {
        const image = document.getElementById("inspector-image");
        if (image) image.className = image.className.replace(/ fit| actual/g, "") + " " + state.inspectorScale;
        for (const button of document.querySelectorAll(".scale-tabs button")) {
            button.setAttribute("aria-pressed", String(
                (button.textContent === "Fit" && state.inspectorScale === "fit")
                || (button.textContent === "100%" && state.inspectorScale === "actual"),
            ));
        }
    }

    function closeInspector() {
        state.screen = null;
        state.routeFocus = null;
        state.inspectorDetails = false;
        renderOrNavigate();
    }

    function openPanel(panel, triggerID) {
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
        requestAnimationFrame(() => document.getElementById(triggerID)?.focus());
    }

    function activePanel() {
        if (!state.panel || state.screen) return null;
        if (state.panel === "search") return searchPanel();
        if (state.panel === "groups") return groupsPanel();
        if (state.panel === "filters") return filtersPanel();
        if (state.panel === "build") return buildPanel();
        return null;
    }

    function panelShell(className, label) {
        const dialog = element("dialog", "panel " + className);
        dialog.setAttribute("aria-label", label);
        dialog.addEventListener("cancel", event => {
            event.preventDefault();
            closePanel();
        });
        dialog.addEventListener("click", event => {
            if (event.target === dialog) closePanel();
        });
        return dialog;
    }

    function panelHeader(kicker, title) {
        const header = element("header", "panel-header");
        const copy = element("div", "");
        copy.append(element("p", "eyebrow", kicker), element("h2", "", title));
        const close = iconButton("close", "Close", "icon-button panel-close");
        close.addEventListener("click", closePanel);
        header.append(copy, close);
        return header;
    }

    function searchPanel() {
        const dialog = panelShell("command-palette", "Search the atlas");
        const surface = element("div", "panel-surface command-surface");
        const field = element("label", "command-field");
        field.append(icon("search"));
        const input = element("input", "");
        input.id = "command-search";
        input.type = "search";
        input.placeholder = "Find a group, screen, state, or route";
        input.autocomplete = "off";
        input.value = state.commandQuery;
        input.setAttribute("aria-label", "Search groups, screens, states, and routes");
        const close = element("button", "escape-key", "Esc");
        close.type = "button";
        close.setAttribute("aria-label", "Close search");
        close.addEventListener("click", closePanel);
        field.append(input, close);
        const results = element("div", "command-results");
        results.id = "command-results";
        renderCommandResults(results, input.value);
        input.addEventListener("input", () => {
            state.commandQuery = input.value;
            renderCommandResults(results, input.value);
        });
        input.addEventListener("keydown", event => moveCommandFocus(event, results));
        surface.append(field, results);
        dialog.append(surface);
        requestAnimationFrame(() => input.focus());
        return dialog;
    }

    function commandEntries(query) {
        const terms = query.trim().toLocaleLowerCase().split(/ +/).filter(Boolean);
        if (terms.length === 0) {
            const currentScreens = manifest.screens
                .filter(screen => screen.groupID === state.group)
                .slice(0, 6)
                .map(screen => screenCommand(screen));
            return [...manifest.groups.map(groupCommand), ...currentScreens];
        }

        const entries = [];
        for (const group of manifest.groups) entries.push(groupCommand(group));
        for (const screen of manifest.screens) {
            entries.push(screenCommand(screen));
            for (const variant of screen.variants) entries.push(variantCommand(screen, variant));
        }
        for (const route of manifest.routes) entries.push(routeCommand(route));
        return entries
            .filter(entry => terms.every(term => entry.search.includes(term)))
            .sort((first, second) => commandScore(first, terms) - commandScore(second, terms)
                || first.title.localeCompare(second.title))
            .slice(0, 14);
    }

    function commandScore(entry, terms) {
        const title = entry.title.toLocaleLowerCase();
        if (terms.every(term => title === term)) return 0;
        if (terms.every(term => title.startsWith(term))) return 1;
        if (terms.every(term => title.includes(term))) return 2;
        return entry.kind === "Screen" ? 3 : 4;
    }

    function groupCommand(group) {
        return {
            kind: "Group",
            title: group.title,
            subtitle: group.screenIDs.length + " screens",
            search: (group.title + " group").toLocaleLowerCase(),
            action: () => {
                state.group = group.id;
                state.view = "canvas";
                state.panel = null;
                state.pendingCanvasAction = "fit-group";
                renderOrNavigate();
            },
        };
    }

    function screenCommand(screen) {
        const group = groupByID.get(screen.groupID);
        return {
            kind: "Screen",
            title: screen.title,
            subtitle: (group?.title || "Ungrouped") + " · " + screen.variants.length
                + (screen.variants.length === 1 ? " state" : " states"),
            search: searchableText(screen),
            action: () => openScreen(screen.id, true),
        };
    }

    function variantCommand(screen, variant) {
        const group = groupByID.get(screen.groupID);
        return {
            kind: "State",
            title: screen.title + " — " + variant.title,
            subtitle: group?.title || "Ungrouped",
            search: (screen.title + " " + variant.title + " " + (group?.title || "")).toLocaleLowerCase(),
            action: () => {
                selectedVariants.set(screen.id, variant.id);
                openScreen(screen.id, true);
            },
        };
    }

    function routeCommand(route) {
        const source = screenByID.get(route.sourceScreenID);
        const destination = screenByID.get(route.destinationScreenID);
        const title = route.label || (source?.title || route.sourceScreenID) + " → "
            + (destination?.title || route.destinationScreenID);
        return {
            kind: route.kind === "modal" ? "Modal route" : "Push route",
            title,
            subtitle: (source?.title || route.sourceScreenID) + " → "
                + (destination?.title || route.destinationScreenID),
            search: (title + " " + route.kind + " " + (source?.title || "") + " "
                + (destination?.title || "")).toLocaleLowerCase(),
            action: () => openScreen(route.destinationScreenID),
        };
    }

    function renderCommandResults(container, query) {
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
                const buttons = [...container.querySelectorAll(".command-result")];
                const offset = event.key === "ArrowDown" ? 1 : -1;
                const next = (index + offset + buttons.length) % buttons.length;
                buttons[next].focus();
            });
            container.append(button);
        });
    }

    function moveCommandFocus(event, results) {
        if (event.key !== "ArrowDown" && event.key !== "ArrowUp" && event.key !== "Enter") return;
        const buttons = [...results.querySelectorAll(".command-result")];
        if (buttons.length === 0) return;
        event.preventDefault();
        if (event.key === "Enter") {
            buttons[0].click();
            return;
        }
        (event.key === "ArrowDown" ? buttons[0] : buttons[buttons.length - 1]).focus();
    }

    function groupsPanel() {
        const dialog = panelShell("sheet-panel groups-panel", "Browse groups");
        const surface = element("div", "panel-surface sheet-surface");
        surface.append(panelHeader("Navigate", "Groups"));
        surface.append(miniMap());
        const navigation = element("nav", "group-navigation");
        navigation.setAttribute("aria-label", "Canvas groups");
        for (const group of manifest.groups) {
            const button = element("button", "group-button");
            button.type = "button";
            button.dataset.groupId = group.id;
            button.setAttribute("aria-current", String(group.id === state.group));
            const copy = element("span", "");
            copy.append(element("strong", "", group.title), element("small", "", group.screenIDs.length + " screens"));
            button.append(element("span", "group-index", String(group.order + 1).padStart(2, "0")), copy, icon("right"));
            button.addEventListener("click", () => {
                state.group = group.id;
                state.view = "canvas";
                state.panel = null;
                state.pendingCanvasAction = "fit-group";
                renderOrNavigate();
            });
            navigation.append(button);
        }
        surface.append(navigation);
        dialog.append(surface);
        return dialog;
    }

    function miniMap() {
        const namespace = "http://www.w3.org/2000/svg";
        const wrapper = element("div", "mini-map");
        const svg = document.createElementNS(namespace, "svg");
        svg.id = "mini-map-svg";
        svg.setAttribute("viewBox", "0 0 " + manifest.canvas.size.width + " " + manifest.canvas.size.height);
        svg.setAttribute("role", "img");
        svg.setAttribute("aria-label", "Canvas overview. Select a position to move around the atlas.");
        for (const group of manifest.canvas.groupFrames) {
            const rect = document.createElementNS(namespace, "rect");
            Object.entries(rectAttributes(group.frame)).forEach(([key, value]) => rect.setAttribute(key, value));
            rect.setAttribute("class", "mini-group");
            rect.dataset.groupId = group.id;
            svg.append(rect);
        }
        for (const screen of manifest.screens) {
            const rect = document.createElementNS(namespace, "rect");
            Object.entries(rectAttributes(screen.frame)).forEach(([key, value]) => rect.setAttribute(key, value));
            rect.setAttribute("class", "mini-screen");
            rect.dataset.screenId = screen.id;
            svg.append(rect);
        }
        const visible = document.createElementNS(namespace, "rect");
        visible.id = "mini-map-viewport";
        visible.setAttribute("class", "mini-viewport");
        svg.append(visible);
        svg.addEventListener("click", event => {
            const bounds = svg.getBoundingClientRect();
            const x = (event.clientX - bounds.left) / bounds.width * manifest.canvas.size.width;
            const y = (event.clientY - bounds.top) / bounds.height * manifest.canvas.size.height;
            state.canvas.scrollLeft = x * state.zoom - window.innerWidth / 2;
            state.canvas.scrollTop = y * state.zoom - window.innerHeight / 2;
            state.canvas.initialized = true;
            state.view = "canvas";
            state.panel = null;
            renderOrNavigate();
        });
        wrapper.append(svg);
        return wrapper;
    }

    function rectAttributes(rect) {
        return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
    }

    function filtersPanel() {
        const dialog = panelShell("sheet-panel filters-panel", "Filter screens");
        const surface = element("div", "panel-surface sheet-surface");
        surface.append(panelHeader("Refine", "Filters"));
        const fields = element("div", "filter-fields");
        const groupOptions = [["all", "All groups"], ...manifest.groups.map(group => [group.id, group.title])];
        fields.append(
            filterSelect("Group", state.filters.group, groupOptions, value => {
                state.filters.group = value;
                updateSearchVisibility();
            }),
            filterSelect("Capture", state.filters.extent, [
                ["all", "All captures"], ["viewport", "Viewport"], ["intrinsic", "Intrinsic"],
                ["fullContent", "Full content"], ["fullContent2D", "Full content 2D"],
            ], value => {
                state.filters.extent = value;
                updateSearchVisibility();
            }),
            filterSelect("Routes", state.filters.routes, [
                ["all", "Any route state"], ["linked", "Linked"], ["unlinked", "Unlinked"],
                ["incoming", "Has incoming"], ["outgoing", "Has outgoing"],
            ], value => {
                state.filters.routes = value;
                updateSearchVisibility();
            }),
        );
        surface.append(fields);
        const footer = element("footer", "panel-footer");
        const clear = element("button", "secondary-button", "Reset filters");
        clear.type = "button";
        clear.addEventListener("click", () => {
            state.filters = { group: "all", extent: "all", routes: "all" };
            state.panel = null;
            render();
        });
        const done = element("button", "primary-button", "Show results");
        done.type = "button";
        done.addEventListener("click", closePanel);
        footer.append(clear, done);
        surface.append(footer);
        dialog.append(surface);
        return dialog;
    }

    function filterSelect(labelText, value, options, onChange) {
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
        status.append(element("span", manifest.build.dirty ? "status-dot dirty" : "status-dot"));
        const copy = element("div", "");
        copy.append(
            element("strong", "", manifest.build.dirty ? "Uncommitted changes" : "Clean build"),
            element("span", "", formatGeneratedAt(manifest.build.generatedAt)),
        );
        status.append(copy);
        const list = element("dl", "detail-list build-list");
        list.append(
            metadataRow("Commit", manifest.build.commit), metadataRow("Branch", manifest.build.branch || "Detached"),
            metadataRow("Xcode", manifest.build.xcodeVersion), metadataRow("Simulator", manifest.build.simulatorDevice),
            metadataRow("Simulator OS", manifest.build.simulatorOS),
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
            state.filters = { group: "all", extent: "all", routes: "all" };
            render();
        });
        empty.append(clear);
        return empty;
    }

    function updateSearchVisibility() {
        const visible = visibleScreenIDs();
        for (const node of document.querySelectorAll("[data-screen-id]")) {
            if (node.matches(".route")) continue;
            node.dataset.hidden = String(!visible.has(node.dataset.screenId));
        }
        for (const group of manifest.groups) {
            const hasResults = group.screenIDs.some(id => visible.has(id));
            for (const node of document.querySelectorAll('[data-group-id="' + CSS.escape(group.id) + '"]')) {
                node.dataset.empty = String(!hasResults);
            }
            const listGroup = document.querySelector('[data-list-group-id="' + CSS.escape(group.id) + '"]');
            if (listGroup) listGroup.hidden = !hasResults;
        }
        for (const route of document.querySelectorAll(".route")) {
            const sourceVisible = visible.has(route.dataset.sourceScreenId);
            const destinationVisible = visible.has(route.dataset.destinationScreenId);
            route.dataset.hidden = String(!sourceVisible && !destinationVisible);
        }
        const count = document.getElementById("result-count");
        if (count) count.textContent = visible.size + " / " + manifest.screens.length;
        const empty = document.getElementById("empty-results");
        if (empty) empty.hidden = visible.size !== 0;
        updateFilterStatus();
        updateRouteFocus();
    }

    function updateFilterStatus() {
        const activeCount = Object.values(state.filters).filter(value => value !== "all").length;
        const button = document.getElementById("filter-trigger");
        if (!button) return;
        button.dataset.active = String(activeCount > 0);
        button.setAttribute("aria-label", activeCount > 0 ? "Filters, " + activeCount + " active" : "Filters");
        const badge = button.querySelector(".filter-badge");
        if (badge) badge.textContent = activeCount > 0 ? String(activeCount) : "";
    }

    function setRouteFocus(screenID) {
        state.routeFocus = screenID;
        updateRouteFocus();
    }

    function updateRouteFocus() {
        const focused = state.routeFocus;
        const connected = new Map();
        if (focused) {
            const screen = screenByID.get(focused);
            for (const id of screen?.incomingRouteIDs || []) {
                const route = routeByID.get(id);
                if (route) connected.set(route.sourceScreenID, "upstream");
            }
            for (const id of screen?.outgoingRouteIDs || []) {
                const route = routeByID.get(id);
                if (route) connected.set(route.destinationScreenID, "downstream");
            }
        }
        for (const card of document.querySelectorAll(".screen-card")) {
            card.dataset.routeRelation = card.dataset.screenId === focused
                ? "focus" : (connected.get(card.dataset.screenId) || (focused ? "unrelated" : "none"));
        }
        for (const route of document.querySelectorAll(".route")) {
            const isConnected = route.dataset.sourceScreenId === focused
                || route.dataset.destinationScreenId === focused;
            route.dataset.routeRelation = isConnected ? "focus" : (focused ? "unrelated" : "none");
        }
    }

    function captureCanvasPosition() {
        const viewport = document.getElementById("canvas-viewport");
        if (!viewport) return;
        state.canvas.scrollLeft = viewport.scrollLeft;
        state.canvas.scrollTop = viewport.scrollTop;
    }

    function applyZoom() {
        const stage = document.getElementById("canvas-stage");
        const scaled = document.getElementById("canvas-scaled");
        if (!stage || !scaled) return;
        stage.style.transform = "scale(" + state.zoom + ")";
        scaled.style.width = manifest.canvas.size.width * state.zoom + "px";
        scaled.style.height = manifest.canvas.size.height * state.zoom + "px";
        const value = document.getElementById("zoom-value");
        if (value) value.textContent = Math.round(state.zoom * 100) + "%";
        updateMiniMapViewport();
    }

    function setZoom(next) {
        const viewport = document.getElementById("canvas-viewport");
        const oldZoom = state.zoom;
        const center = viewport ? {
            x: (viewport.scrollLeft + viewport.clientWidth / 2) / oldZoom,
            y: (viewport.scrollTop + viewport.clientHeight / 2) / oldZoom,
        } : null;
        state.zoom = Math.max(0.1, Math.min(1.5, next));
        applyZoom();
        if (viewport && center) {
            viewport.scrollTo({
                left: center.x * state.zoom - viewport.clientWidth / 2,
                top: center.y * state.zoom - viewport.clientHeight / 2,
            });
            captureCanvasPosition();
        }
    }

    function fitFrame(frame, behavior = "smooth") {
        const viewport = document.getElementById("canvas-viewport");
        if (!viewport) return;
        const padding = Math.min(Math.max(viewport.clientWidth * 0.055, 32), 80);
        const horizontal = Math.max(viewport.clientWidth - padding * 2, 1) / Math.max(frame.width, 1);
        const vertical = Math.max(viewport.clientHeight - padding * 2, 1) / Math.max(frame.height, 1);
        state.zoom = Math.max(0.1, Math.min(1.5, horizontal, vertical));
        applyZoom();
        const left = (frame.x + frame.width / 2) * state.zoom - viewport.clientWidth / 2;
        const top = (frame.y + frame.height / 2) * state.zoom - viewport.clientHeight / 2;
        viewport.scrollTo({ left, top, behavior });
        state.canvas.scrollLeft = Math.max(0, left);
        state.canvas.scrollTop = Math.max(0, top);
    }

    function fitAll(behavior = "smooth") {
        fitFrame({ x: 0, y: 0, width: manifest.canvas.size.width, height: manifest.canvas.size.height }, behavior);
    }

    function fitCurrentGroup(behavior = "smooth") {
        const group = manifest.canvas.groupFrames.find(item => item.id === state.group)
            || manifest.canvas.groupFrames[0];
        if (group) fitFrame(group.frame, behavior);
    }

    function fitFirstGroup() {
        const first = manifest.canvas.groupFrames[0];
        if (first) fitFrame(first.frame, "auto");
    }

    let canvasNavigationFrame = null;
    function scheduleCanvasNavigationUpdate() {
        if (canvasNavigationFrame !== null) return;
        canvasNavigationFrame = requestAnimationFrame(() => {
            canvasNavigationFrame = null;
            captureCanvasPosition();
            updateCanvasNavigation();
        });
    }

    function updateCanvasNavigation() {
        const viewport = document.getElementById("canvas-viewport");
        if (!viewport) return;
        const centerX = (viewport.scrollLeft + viewport.clientWidth / 2) / state.zoom;
        const centerY = (viewport.scrollTop + viewport.clientHeight / 2) / state.zoom;
        let nearest = null;
        let nearestDistance = Number.POSITIVE_INFINITY;
        for (const group of manifest.canvas.groupFrames) {
            const frame = group.frame;
            const dx = Math.max(frame.x - centerX, 0, centerX - frame.x - frame.width);
            const dy = Math.max(frame.y - centerY, 0, centerY - frame.y - frame.height);
            const distance = dx * dx + dy * dy;
            if (distance < nearestDistance) {
                nearest = group.id;
                nearestDistance = distance;
            }
        }
        if (nearest && nearest !== state.group) {
            state.group = nearest;
            updateActiveGroup();
        }
        updateMiniMapViewport();
    }

    function updateActiveGroup() {
        for (const button of document.querySelectorAll(".group-button")) {
            button.setAttribute("aria-current", String(button.dataset.groupId === state.group));
        }
        for (const group of document.querySelectorAll(".mini-group")) {
            group.dataset.active = String(group.dataset.groupId === state.group);
        }
        const current = groupByID.get(state.group);
        const context = document.querySelector(".canvas-context");
        if (context && current) {
            context.querySelector(".context-kicker").textContent = "Group " + (current.order + 1)
                + " of " + manifest.groups.length;
            context.querySelector("strong").textContent = current.title;
        }
        const dockLabel = document.querySelector(".group-trigger .button-label");
        if (dockLabel && current) dockLabel.textContent = current.title;
    }

    function updateMiniMapViewport() {
        const viewport = document.getElementById("canvas-viewport");
        const rect = document.getElementById("mini-map-viewport");
        if (!viewport || !rect) return;
        rect.setAttribute("x", viewport.scrollLeft / state.zoom);
        rect.setAttribute("y", viewport.scrollTop / state.zoom);
        rect.setAttribute("width", viewport.clientWidth / state.zoom);
        rect.setAttribute("height", viewport.clientHeight / state.zoom);
    }

    function render() {
        captureCanvasPosition();
        const app = element("div", "application");
        app.append(appHeader());
        app.append(state.view === "canvas" ? canvasView() : listView());
        app.append(bottomDock());
        root.replaceChildren(app);

        const inspection = inspector();
        if (inspection) {
            root.append(inspection);
            requestAnimationFrame(() => inspection.showModal());
        } else {
            const panel = activePanel();
            if (panel) {
                root.append(panel);
                requestAnimationFrame(() => {
                    panel.showModal();
                    updateMiniMapViewport();
                });
            }
        }
        requestAnimationFrame(updateSearchVisibility);
    }

    window.addEventListener("hashchange", () => {
        captureCanvasPosition();
        parseHash();
        render();
    });
    window.addEventListener("resize", scheduleCanvasNavigationUpdate);
    window.addEventListener("keydown", event => {
        const target = event.target;
        const isEditing = target instanceof HTMLInputElement
            || target instanceof HTMLSelectElement
            || target instanceof HTMLTextAreaElement
            || target?.isContentEditable;
        const commandSearch = (event.metaKey || event.ctrlKey) && event.key.toLocaleLowerCase() === "k";
        if (commandSearch || (event.key === "/" && !isEditing && !event.metaKey && !event.ctrlKey && !event.altKey)) {
            event.preventDefault();
            if (!state.screen) openPanel("search", "search-trigger");
            return;
        }
        if (isEditing || event.metaKey || event.ctrlKey || event.altKey || state.panel) return;
        if (state.screen && (event.key === "ArrowLeft" || event.key === "[")) {
            event.preventDefault();
            openScreen(neighboringScreen(-1)?.id);
        } else if (state.screen && (event.key === "ArrowRight" || event.key === "]")) {
            event.preventDefault();
            openScreen(neighboringScreen(1)?.id);
        } else if (state.screen && event.key.toLocaleLowerCase() === "i") {
            event.preventDefault();
            toggleInspectorDetails();
        } else if (!state.screen && state.view === "canvas" && event.key.toLocaleLowerCase() === "f") {
            event.preventDefault();
            fitAll();
        } else if (!state.screen && state.view === "canvas" && event.key === "0") {
            event.preventDefault();
            fitCurrentGroup();
        } else if (!state.screen && state.view === "canvas" && (event.key === "+" || event.key === "=")) {
            event.preventDefault();
            setZoom(state.zoom + 0.1);
        } else if (!state.screen && state.view === "canvas" && event.key === "-") {
            event.preventDefault();
            setZoom(state.zoom - 0.1);
        }
    });

    parseHash();
    render();
})();
