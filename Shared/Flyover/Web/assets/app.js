(() => {
    "use strict";

    const root = document.getElementById("app");
    const manifest = window.FLYOVER_MANIFEST;
    if (!manifest || manifest.schemaVersion !== 1) {
        root.innerHTML = '<main class="error selectable-text"><p class="eyebrow">Manifest error</p><h1>Flyover cannot open this atlas</h1><p>This site requires manifest schema version 1.</p></main>';
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
    const defaultView = "canvas";
    const defaultProfile = manifest.profiles[0]?.id;
    const targetResidentImageCount = 6;
    const targetResidentPixelCount = 24_000_000;
    let inspectorResizeObserver = null;
    const selectedVariants = new Map(manifest.screens.map(screen => [screen.id, screen.variants[0]?.id]));
    const state = {
        view: defaultView,
        profile: defaultProfile,
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
        pendingCanvasPosition: null,
        pendingFocusKey: null,
        inspectorReturnFocusKey: null,
        canvas: {
            initialized: false,
            scrollLeft: 0,
            scrollTop: 0,
            viewportWidth: 0,
            viewportHeight: 0,
        },
        list: {
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

    function quantity(count, singular) {
        return count + " " + (count === 1 ? singular : singular + "s");
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
        const previousScreenID = state.screen;
        const values = new URLSearchParams(location.hash.replace(/^#/, ""));
        const view = values.get("view");
        const profile = values.get("profile");
        const screenID = values.get("screen");
        const variantID = values.get("variant");
        state.view = view === "canvas" || view === "list" ? view : defaultView;
        state.profile = profileByID.has(profile) ? profile : defaultProfile;
        if (screenByID.has(screenID)) {
            state.screen = screenID;
            const screen = screenByID.get(screenID);
            const selectedVariant = screen.variants.some(variant => variant.id === variantID)
                ? variantID : screen.variants[0]?.id;
            selectedVariants.set(screenID, selectedVariant);
        } else {
            state.screen = null;
            if (previousScreenID) {
                state.pendingFocusKey = state.inspectorReturnFocusKey || "atlas-screen-" + previousScreenID;
            }
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
        if (view === "canvas" && !state.canvas.initialized) state.pendingCanvasAction = "fit-initial";
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
        if (!state.screen) state.inspectorReturnFocusKey = "atlas-screen-" + screenID;
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
        row.append(element("dt", "", label), element("dd", "selectable-text", value));
        return row;
    }

    function profileSelect(className = "", focusKey = "profile") {
        const select = element("select", className);
        select.setAttribute("aria-label", "Capture profile");
        select.dataset.focusKey = focusKey;
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
        const brandMark = element("span", "brand-mark", "F");
        brandMark.setAttribute("aria-hidden", "true");
        identity.append(brandMark);
        const copy = element("div", "identity-copy");
        copy.append(element("span", "product-label", "Flyover"), element("h1", "", manifest.application.title));
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
        search.addEventListener("click", () => openPanel("search", search.id));
        actions.append(search);

        const build = iconButton("info", "Build details", "header-button build-trigger");
        build.id = "build-trigger";
        build.append(element("code", "commit-label", manifest.build.commit.slice(0, 8)));
        if (manifest.build.dirty) {
            build.setAttribute("aria-label", "Build details, uncommitted changes");
            build.title = "Build details, uncommitted changes";
            build.append(element("span", "dirty-dot"));
        }
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
            button.dataset.focusKey = "view-" + item[0];
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
        filters.dataset.focusKey = "filters-control";
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
        select.dataset.focusKey = (updateHistory ? "inspector-state-" : "atlas-state-") + screen.id;
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
        const title = direction === "outgoing" && route.label
            ? route.label : (destination?.title || destinationID);
        const button = element("button", "route-chip " + route.kind);
        button.type = "button";
        button.append(icon("route"), element("span", "", cue + " · " + title));
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
        image.draggable = false;
        image.loading = eager ? "eager" : "lazy";
        image.decoding = "async";
        const source = imagePath(screen);
        if (eager) image.src = source;
        else image.dataset.src = source;
        image.dataset.captureExtent = screenVariant(screen)?.captureExtent || "viewport";
        image.alt = screen.title + " — " + (screenVariant(screen)?.title || "Default");
        return image;
    }

    function captureViewportSize(screen) {
        if (screen.viewport.kind === "fixed" && screen.viewport.fixedSize) {
            return screen.viewport.fixedSize;
        }
        const profile = profileByID.get(state.profile);
        if (profile?.device === "tablet") return { width: 834, height: 1194 };
        if (profile?.orientation === "landscape") return { width: 874, height: 402 };
        return { width: 402, height: 874 };
    }

    function captureViewportAspect(screen) {
        const size = captureViewportSize(screen);
        return size.width / size.height;
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
            band.dataset.entry = String(item.kind !== "unlinked" && item.depth === 0);
            Object.assign(band.style, rectStyle(item.frame));
            const title = item.kind === "unlinked" ? "Unlinked" : (item.depth === 0 ? "Entry" : "Depth " + item.depth);
            band.append(element("span", "", title));
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
            if (state.pendingCanvasAction === "fit-initial") {
                state.pendingCanvasAction = null;
                fitFirstGroup();
            } else if (state.pendingCanvasAction === "fit-group") {
                state.pendingCanvasAction = null;
                fitCurrentGroup("auto");
            } else if (state.pendingCanvasAction === "fit-all") {
                state.pendingCanvasAction = null;
                fitAll("auto");
            } else if (state.pendingCanvasPosition) {
                const position = state.pendingCanvasPosition;
                state.pendingCanvasPosition = null;
                viewport.scrollTo(position);
                state.canvas.scrollLeft = position.left;
                state.canvas.scrollTop = position.top;
                updateCanvasNavigation();
            } else if (!state.canvas.initialized) {
                fitFirstGroup();
            } else {
                viewport.scrollTo({ left: state.canvas.scrollLeft, top: state.canvas.scrollTop });
                updateCanvasNavigation();
            }
            state.canvas.initialized = true;
            updateCanvasImageResidency();
        });
        installCanvasPinch(viewport);
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
        imageButton.dataset.focusKey = "atlas-screen-" + screen.id;
        const device = element("span", "device-preview");
        device.dataset.captureExtent = variant?.captureExtent || "viewport";
        device.style.setProperty("--viewport-aspect", captureViewportAspect(screen));
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
        main.addEventListener("scroll", scheduleListImageResidencyUpdate, { passive: true });
        const intro = element("header", "list-intro");
        const copy = element("div", "");
        copy.append(element("p", "eyebrow", "Captured catalog"));
        copy.append(element("h2", "", quantity(manifest.screens.length, "screen") + ", ready to review"));
        intro.append(copy, element("p", "list-summary", quantity(manifest.groups.length, "group") + " · "
            + quantity(manifest.routes.length, "route") + " · " + quantity(manifest.profiles.length, "profile")));
        main.append(intro);

        for (const group of manifest.groups) {
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
                const screen = screenByID.get(screenID);
                if (screen) rows.append(listRow(screen));
            }
            section.append(rows);
            main.append(section);
        }
        main.append(emptyResults());
        requestAnimationFrame(() => {
            main.scrollTop = state.list.scrollTop;
            updateListImageResidency();
        });
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
        thumbnail.setAttribute("aria-label", "Inspect " + screen.title + ", "
            + screen.incomingRouteIDs.length + " incoming and " + screen.outgoingRouteIDs.length + " outgoing routes");
        thumbnail.dataset.focusKey = "atlas-screen-" + screen.id;
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
            const route = routeByID.get(routeID);
            if (route) routes.append(routeButton(route, screen, "outgoing"));
        }
        for (const routeID of screen.incomingRouteIDs) {
            const route = routeByID.get(routeID);
            if (route) routes.append(routeButton(route, screen, "incoming"));
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
            element("h2", "selectable-text", screen.title),
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
        details.setAttribute("aria-controls", "inspector-details");
        details.setAttribute("aria-expanded", String(state.inspectorDetails));
        details.addEventListener("click", toggleInspectorDetails);
        const close = iconButton("close", "Close inspector", "inspector-action close-inspector");
        close.autofocus = true;
        close.addEventListener("click", closeInspector);
        actions.append(raw, details, close);
        header.append(heading, actions);

        const canvas = element("section", "inspection-canvas");
        const extentClass = variant.captureExtent === "fullContent2D"
            ? " full-content full-content-2d"
            : (variant.captureExtent === "fullContent" ? " full-content" : "");
        const imageFrame = element("div", "inspector-image " + state.inspectorScale + extentClass);
        imageFrame.id = "inspector-image";
        const device = element("div", "inspector-device");
        if (extentClass) {
            device.tabIndex = 0;
            device.dataset.captureScroller = "";
            device.setAttribute("role", "region");
            device.setAttribute("aria-label", screen.title + " scrollable full-content capture");
        }
        const fullImage = screenImage(screen, "", true);
        if (metadata) {
            const viewportSize = captureViewportSize(screen);
            device.style.setProperty("--point-width", metadata.pointWidth + "px");
            device.style.setProperty("--point-height", metadata.pointHeight + "px");
            device.style.setProperty("--viewport-width", viewportSize.width + "px");
            device.style.setProperty("--viewport-height", viewportSize.height + "px");
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
        previous.dataset.focusKey = "inspector-previous";
        previous.addEventListener("click", () => openScreen(neighboringScreen(-1)?.id, true));
        dock.append(previous, element("span", "dock-separator"));

        const stateField = element("label", "inspector-field");
        stateField.append(element("span", "field-label", "State"), variantSelector(screen, true));
        const profileField = element("label", "inspector-field profile-field");
        profileField.append(
            element("span", "field-label", "Profile"),
            profileSelect("", "inspector-profile"),
        );
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
        next.dataset.focusKey = "inspector-next";
        next.addEventListener("click", () => openScreen(neighboringScreen(1)?.id, true));
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
        updateInspectorDetailsAccessibility();
        fitInspectorImage();
    }

    function updateInspectorDetailsAccessibility() {
        const detailsCoverContent = Boolean(
            state.inspectorDetails
                && window.matchMedia?.("(max-width: 760px), (max-height: 520px)")?.matches,
        );
        for (const selector of [".inspection-canvas", ".inspector-dock"]) {
            const content = document.querySelector(selector);
            if (!content) continue;
            content.inert = detailsCoverContent;
            content.setAttribute("aria-hidden", String(detailsCoverContent));
        }
    }

    function updateInspectorScale() {
        const image = document.getElementById("inspector-image");
        if (image) image.className = image.className.replace(/ fit| actual/g, "") + " " + state.inspectorScale;
        fitInspectorImage();
        for (const button of document.querySelectorAll(".scale-tabs button")) {
            button.setAttribute("aria-pressed", String(
                (button.textContent === "Fit" && state.inspectorScale === "fit")
                || (button.textContent === "100%" && state.inspectorScale === "actual"),
            ));
        }
    }

    function fitInspectorImage() {
        const frame = document.getElementById("inspector-image");
        const device = frame?.querySelector(".inspector-device");
        const screen = screenByID.get(state.screen);
        const variant = screen ? screenVariant(screen) : null;
        const metadata = screen ? imageMetadata(screen) : null;
        if (!frame || !device || !metadata || !variant) return;
        if (state.inspectorScale !== "fit"
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

    function observeInspectorSize() {
        inspectorResizeObserver?.disconnect();
        inspectorResizeObserver = null;
        const frame = document.getElementById("inspector-image");
        if (!frame || typeof ResizeObserver === "undefined") return;
        inspectorResizeObserver = new ResizeObserver(fitInspectorImage);
        inspectorResizeObserver.observe(frame);
    }

    function closeInspector() {
        state.pendingFocusKey = state.inspectorReturnFocusKey;
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
        input.autofocus = true;
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
            subtitle: quantity(group.screenIDs.length, "screen"),
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
            copy.append(
                element("strong", "", group.title),
                element("small", "", quantity(group.screenIDs.length, "screen")),
            );
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
        svg.setAttribute("role", "group");
        svg.setAttribute("tabindex", "0");
        svg.setAttribute("aria-label", "Canvas overview. Select a position or use arrow keys to pan the atlas.");
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
        svg.addEventListener("click", event => moveFromMiniMap(svg, event.clientX, event.clientY));
        svg.addEventListener("keydown", event => {
            const offsets = {
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
                state.canvas.scrollLeft + width * offset[0],
                state.canvas.scrollTop + height * offset[1],
            );
        });
        wrapper.append(svg);
        return wrapper;
    }

    function moveFromMiniMap(svg, clientX, clientY) {
        const matrix = svg.getScreenCTM();
        if (!matrix) return;
        const point = new DOMPoint(clientX, clientY).matrixTransform(matrix.inverse());
        const viewport = document.getElementById("canvas-viewport");
        const { width, height } = canvasViewportSize(viewport);
        queueCanvasPosition(point.x * state.zoom - width / 2, point.y * state.zoom - height / 2);
    }

    function queueCanvasPosition(left, top) {
        const viewport = document.getElementById("canvas-viewport");
        const { width: viewportWidth, height: viewportHeight } = canvasViewportSize(viewport);
        const maximumLeft = Math.max(manifest.canvas.size.width * state.zoom - viewportWidth, 0);
        const maximumTop = Math.max(manifest.canvas.size.height * state.zoom - viewportHeight, 0);
        state.pendingCanvasPosition = {
            left: Math.min(Math.max(left, 0), maximumLeft),
            top: Math.min(Math.max(top, 0), maximumTop),
        };
        state.canvas.initialized = true;
        state.view = "canvas";
        state.panel = null;
        renderOrNavigate();
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
        const matchingScreens = manifest.screens.filter(matchesFilters);
        if (state.view === "canvas" && matchingScreens.length > 0) {
            const currentGroupHasMatch = matchingScreens.some(screen => screen.groupID === state.group);
            state.group = currentGroupHasMatch ? state.group : matchingScreens[0].groupID;
            state.pendingCanvasAction = "fit-group";
        } else if (state.view === "list") {
            const list = document.querySelector(".list-view");
            if (list) list.scrollTop = 0;
            state.list.scrollTop = 0;
        }
        closePanel();
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
            requestAnimationFrame(() => document.getElementById("filter-trigger")?.focus());
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
            route.dataset.hidden = String(!sourceVisible || !destinationVisible);
        }
        const count = document.getElementById("result-count");
        if (count) count.textContent = visible.size + " / " + manifest.screens.length;
        const empty = document.getElementById("empty-results");
        if (empty) empty.hidden = visible.size !== 0;
        updateFilterStatus();
        updateRouteFocus();
        if (state.view === "canvas") updateCanvasImageResidency();
        else updateListImageResidency();
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

    function residentScreenIDs(candidates) {
        const result = new Set();
        let pixels = 0;
        for (const candidate of candidates) {
            if (!candidate.isVisible) continue;
            result.add(candidate.screen.id);
            pixels += candidate.imagePixels;
        }
        for (const candidate of candidates) {
            if (candidate.isVisible) continue;
            if (result.size >= targetResidentImageCount) break;
            if (result.size > 0 && pixels + candidate.imagePixels > targetResidentPixelCount) continue;
            result.add(candidate.screen.id);
            pixels += candidate.imagePixels;
        }
        return result;
    }

    function screenImagePixels(screen) {
        const metadata = imageMetadata(screen);
        return metadata ? metadata.pixelWidth * metadata.pixelHeight : 0;
    }

    function updateCanvasImageResidency() {
        const viewport = document.getElementById("canvas-viewport");
        if (!viewport || state.view !== "canvas") return;
        if (state.screen) {
            updateResidentImages(".screen-card", new Set());
            return;
        }
        const visibleRect = {
            left: viewport.scrollLeft / state.zoom,
            top: viewport.scrollTop / state.zoom,
            right: (viewport.scrollLeft + viewport.clientWidth) / state.zoom,
            bottom: (viewport.scrollTop + viewport.clientHeight) / state.zoom,
        };
        const center = {
            x: (visibleRect.left + visibleRect.right) / 2,
            y: (visibleRect.top + visibleRect.bottom) / 2,
        };
        const candidates = manifest.screens
            .filter(screen => matchesFilters(screen) && rectIntersects(screen.frame, visibleRect))
            .map(screen => ({
                screen,
                imagePixels: screenImagePixels(screen),
                isVisible: true,
                distance: squaredDistance(screen.frame.x + screen.frame.width / 2,
                    screen.frame.y + screen.frame.height / 2, center.x, center.y),
            }))
            .sort((lhs, rhs) => lhs.distance - rhs.distance
                || lhs.screen.frame.y - rhs.screen.frame.y
                || lhs.screen.frame.x - rhs.screen.frame.x);
        updateResidentImages(".screen-card", residentScreenIDs(candidates));
    }

    let listResidencyFrame = null;
    function scheduleListImageResidencyUpdate() {
        if (listResidencyFrame !== null) return;
        listResidencyFrame = requestAnimationFrame(() => {
            listResidencyFrame = null;
            updateListImageResidency();
        });
    }

    function updateListImageResidency() {
        const list = document.querySelector(".list-view");
        if (!list || state.view !== "list") return;
        if (state.screen) {
            updateResidentImages(".list-row", new Set());
            return;
        }
        const viewport = list.getBoundingClientRect();
        const centerY = (viewport.top + viewport.bottom) / 2;
        const candidates = [];
        for (const row of document.querySelectorAll(".list-row")) {
            const screen = screenByID.get(row.dataset.screenId);
            if (!screen || !matchesFilters(screen)) continue;
            const frame = row.getBoundingClientRect();
            if (frame.bottom < viewport.top - 120 || frame.top > viewport.bottom + 120) continue;
            candidates.push({
                screen,
                imagePixels: screenImagePixels(screen),
                isVisible: frame.bottom > viewport.top && frame.top < viewport.bottom,
                distance: Math.abs((frame.top + frame.bottom) / 2 - centerY),
            });
        }
        candidates.sort((lhs, rhs) => lhs.distance - rhs.distance || lhs.screen.screenOrder - rhs.screen.screenOrder);
        updateResidentImages(".list-row", residentScreenIDs(candidates));
    }

    function updateResidentImages(containerSelector, residentIDs) {
        for (const container of document.querySelectorAll(containerSelector)) {
            const image = container.querySelector("img[data-src]");
            if (!image) continue;
            if (residentIDs.has(container.dataset.screenId)) {
                image.loading = "eager";
                if (image.getAttribute("src") !== image.dataset.src) image.src = image.dataset.src;
            } else {
                image.removeAttribute("src");
                image.loading = "lazy";
            }
        }
    }

    function rectIntersects(frame, visibleRect) {
        return frame.x < visibleRect.right && frame.x + frame.width > visibleRect.left
            && frame.y < visibleRect.bottom && frame.y + frame.height > visibleRect.top;
    }

    function squaredDistance(x1, y1, x2, y2) {
        const x = x1 - x2;
        const y = y1 - y2;
        return x * x + y * y;
    }

    function installCanvasPinch(viewport) {
        let gesture = null;
        viewport.addEventListener("touchstart", event => {
            if (event.touches.length !== 2) return;
            const midpoint = touchMidpoint(event.touches);
            const bounds = viewport.getBoundingClientRect();
            gesture = {
                distance: touchDistance(event.touches),
                zoom: state.zoom,
                canvasX: (viewport.scrollLeft + midpoint.x - bounds.left) / state.zoom,
                canvasY: (viewport.scrollTop + midpoint.y - bounds.top) / state.zoom,
            };
        }, { passive: true });
        viewport.addEventListener("touchmove", event => {
            if (!gesture || event.touches.length !== 2) return;
            event.preventDefault();
            const midpoint = touchMidpoint(event.touches);
            const bounds = viewport.getBoundingClientRect();
            const nextZoom = Math.max(0.1, Math.min(1.5,
                gesture.zoom * touchDistance(event.touches) / Math.max(gesture.distance, 1)));
            state.zoom = nextZoom;
            applyZoom();
            viewport.scrollTo({
                left: gesture.canvasX * nextZoom - (midpoint.x - bounds.left),
                top: gesture.canvasY * nextZoom - (midpoint.y - bounds.top),
            });
            captureCanvasPosition();
            scheduleCanvasNavigationUpdate();
        }, { passive: false });
        const endGesture = event => {
            if (event.touches.length < 2) gesture = null;
        };
        viewport.addEventListener("touchend", endGesture, { passive: true });
        viewport.addEventListener("touchcancel", endGesture, { passive: true });
    }

    function touchMidpoint(touches) {
        return {
            x: (touches[0].clientX + touches[1].clientX) / 2,
            y: (touches[0].clientY + touches[1].clientY) / 2,
        };
    }

    function touchDistance(touches) {
        return Math.hypot(
            touches[0].clientX - touches[1].clientX,
            touches[0].clientY - touches[1].clientY,
        );
    }

    function captureCanvasPosition() {
        const viewport = document.getElementById("canvas-viewport");
        if (!viewport) return;
        state.canvas.scrollLeft = viewport.scrollLeft;
        state.canvas.scrollTop = viewport.scrollTop;
        state.canvas.viewportWidth = viewport.clientWidth;
        state.canvas.viewportHeight = viewport.clientHeight;
    }

    function captureListPosition() {
        const list = document.querySelector(".list-view");
        if (list) state.list.scrollTop = list.scrollTop;
    }

    function captureViewPosition() {
        captureCanvasPosition();
        captureListPosition();
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
        updateCanvasImageResidency();
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
        const prefersReducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches;
        viewport.scrollTo({ left, top, behavior: prefersReducedMotion ? "auto" : behavior });
        state.canvas.scrollLeft = Math.max(0, left);
        state.canvas.scrollTop = Math.max(0, top);
        updateCanvasImageResidency();
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
        const viewport = document.getElementById("canvas-viewport");
        if (!viewport) return;
        const initialWidth = manifest.canvas.initialFitSize?.width
            || manifest.canvas.groupFrames[0]?.frame.width;
        if (!initialWidth) return;
        const framingInset = 16;
        const horizontal = Math.max(viewport.clientWidth - framingInset * 2, 1) / initialWidth;
        state.zoom = Math.max(0.15, Math.min(1, horizontal));
        applyZoom();
        viewport.scrollTo({ left: 0, top: 0, behavior: "auto" });
        state.canvas.scrollLeft = 0;
        state.canvas.scrollTop = 0;
        updateCanvasNavigation();
    }

    let canvasNavigationFrame = null;
    function scheduleCanvasNavigationUpdate() {
        if (canvasNavigationFrame !== null) return;
        canvasNavigationFrame = requestAnimationFrame(() => {
            canvasNavigationFrame = null;
            captureCanvasPosition();
            updateCanvasNavigation();
            updateCanvasImageResidency();
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
        if (!rect) return;
        const { width, height } = canvasViewportSize(viewport);
        const scrollLeft = viewport?.scrollLeft ?? state.canvas.scrollLeft;
        const scrollTop = viewport?.scrollTop ?? state.canvas.scrollTop;
        rect.setAttribute("x", scrollLeft / state.zoom);
        rect.setAttribute("y", scrollTop / state.zoom);
        rect.setAttribute("width", width / state.zoom);
        rect.setAttribute("height", height / state.zoom);
    }

    function canvasViewportSize(viewport) {
        return {
            width: viewport?.clientWidth || state.canvas.viewportWidth || window.innerWidth,
            height: viewport?.clientHeight || state.canvas.viewportHeight || window.innerHeight,
        };
    }

    function visibleFocusTarget(focusKey) {
        if (!focusKey) return null;
        const target = document.querySelector('[data-focus-key="' + CSS.escape(focusKey) + '"]');
        if (!target || target.closest('[data-hidden="true"], [aria-hidden="true"]')) return null;
        const style = window.getComputedStyle(target);
        return style.display === "none" || style.visibility === "hidden" ? null : target;
    }

    function render() {
        if (!state.pendingCanvasPosition) captureViewPosition();
        if (canvasNavigationFrame !== null) {
            cancelAnimationFrame(canvasNavigationFrame);
            canvasNavigationFrame = null;
        }
        if (listResidencyFrame !== null) {
            cancelAnimationFrame(listResidencyFrame);
            listResidencyFrame = null;
        }
        inspectorResizeObserver?.disconnect();
        inspectorResizeObserver = null;
        const activeElement = document.activeElement;
        const activeFocusKey = activeElement?.dataset.focusKey;
        const canRestoreActiveFocus = !state.panel
            && (!state.screen || activeElement?.closest(".inspector"));
        const focusKey = state.pendingFocusKey || (canRestoreActiveFocus ? activeFocusKey : null);
        state.pendingFocusKey = null;
        const app = element("div", "application");
        app.append(appHeader());
        app.append(state.view === "canvas" ? canvasView() : listView());
        app.append(bottomDock());
        root.replaceChildren(app);

        const inspection = inspector();
        if (inspection) {
            root.append(inspection);
            requestAnimationFrame(() => {
                inspection.showModal();
                updateInspectorDetailsAccessibility();
                fitInspectorImage();
                observeInspectorSize();
            });
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
        requestAnimationFrame(() => {
            updateSearchVisibility();
            if (focusKey) {
                (visibleFocusTarget(focusKey) || visibleFocusTarget("filters-control"))?.focus();
            }
        });
    }

    window.addEventListener("hashchange", () => {
        if (!state.pendingCanvasPosition) captureViewPosition();
        parseHash();
        render();
    });
    window.addEventListener("resize", () => {
        if (state.screen) requestAnimationFrame(() => {
            updateInspectorDetailsAccessibility();
            fitInspectorImage();
        });
        if (state.view === "canvas") scheduleCanvasNavigationUpdate();
        else scheduleListImageResidencyUpdate();
    });
    window.addEventListener("keydown", event => {
        const target = event.target;
        const isEditing = target instanceof HTMLInputElement
            || target instanceof HTMLSelectElement
            || target instanceof HTMLTextAreaElement
            || target?.isContentEditable;
        const isCaptureScroller = target?.closest?.("[data-capture-scroller]");
        const commandSearch = (event.metaKey || event.ctrlKey) && event.key.toLocaleLowerCase() === "k";
        if (commandSearch || (event.key === "/" && !isEditing && !event.metaKey && !event.ctrlKey && !event.altKey)) {
            event.preventDefault();
            if (!state.screen) openPanel("search", "search-trigger");
            return;
        }
        if (isEditing || isCaptureScroller || event.metaKey || event.ctrlKey || event.altKey || state.panel) return;
        if (state.screen && (event.key === "ArrowLeft" || event.key === "[")) {
            event.preventDefault();
            openScreen(neighboringScreen(-1)?.id, true);
        } else if (state.screen && (event.key === "ArrowRight" || event.key === "]")) {
            event.preventDefault();
            openScreen(neighboringScreen(1)?.id, true);
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
