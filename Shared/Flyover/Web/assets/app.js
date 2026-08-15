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
        search: "",
        zoom: 1,
        group: manifest.groups[0]?.id,
        routeFocus: null,
        inspectorScale: "fit",
        filters: {
            group: "all",
            extent: "all",
            routes: "all",
        },
    };

    function element(tag, className, text) {
        const value = document.createElement(tag);
        if (className) value.className = className;
        if (text !== undefined) value.textContent = text;
        return value;
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

    function matchesSearch(screen) {
        const terms = state.search.trim().toLocaleLowerCase().split(/ +/).filter(Boolean);
        if (!terms.every(term => searchableText(screen).includes(term))) return false;
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
        return new Set(manifest.screens.filter(matchesSearch).map(screen => screen.id));
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
            if (screen.variants.some(variant => variant.id === variantID)) {
                selectedVariants.set(screenID, variantID);
            }
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
        return new Intl.DateTimeFormat(undefined, {
            dateStyle: "medium",
            timeStyle: "short",
        }).format(date);
    }

    function labeledSelect(title, select, className) {
        const label = element("label", className || "field");
        label.append(element("span", "field-label", title), select);
        return label;
    }

    function profileSelect() {
        const select = element("select", "");
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

    function toolbar() {
        const shell = element("header", "app-header");
        const masthead = element("div", "masthead");
        const brand = element("div", "brand");
        brand.append(element("span", "brand-mark", "F"));
        const brandCopy = element("div", "");
        brandCopy.append(element("p", "eyebrow", "Flyover QA Atlas"));
        brandCopy.append(element("h1", "", manifest.application.title));
        brand.append(brandCopy);
        masthead.append(brand);

        const build = element("details", "build-details");
        const summary = element("summary", "");
        summary.append(element("span", "commit-dot"), element("code", "", manifest.build.commit.slice(0, 8)));
        if (manifest.build.dirty) summary.append(element("span", "dirty", "Dirty"));
        build.append(summary);
        const buildPanel = element("div", "build-panel");
        buildPanel.append(
            metadataRow("Generated", formatGeneratedAt(manifest.build.generatedAt)),
            metadataRow("Branch", manifest.build.branch || "Detached"),
            metadataRow("Commit", manifest.build.commit),
            metadataRow("Xcode", manifest.build.xcodeVersion),
            metadataRow("Simulator", manifest.build.simulatorDevice + " · iOS " + manifest.build.simulatorOS),
        );
        build.append(buildPanel);
        masthead.append(build);

        const primary = element("div", "primary-toolbar");
        const tabs = element("div", "view-tabs");
        tabs.setAttribute("aria-label", "Atlas view");
        for (const view of ["canvas", "list"]) {
            const button = element("button", "", view[0].toUpperCase() + view.slice(1));
            button.type = "button";
            button.setAttribute("aria-pressed", String(state.view === view));
            button.addEventListener("click", () => chooseView(view));
            tabs.append(button);
        }
        primary.append(tabs);

        const searchField = element("label", "search-field");
        searchField.append(element("span", "search-icon", "⌕"));
        const search = element("input", "");
        search.id = "global-search";
        search.type = "search";
        search.placeholder = "Find screens, states, or routes";
        search.setAttribute("aria-label", "Search screens, states, and routes");
        search.setAttribute("aria-keyshortcuts", "/");
        search.value = state.search;
        search.addEventListener("input", () => {
            state.search = search.value;
            updateSearchVisibility();
        });
        searchField.append(search, element("kbd", "", "/"));
        primary.append(searchField);
        primary.append(filterMenu());
        primary.append(labeledSelect("Profile", profileSelect(), "profile-field"));
        shell.append(masthead, primary);

        const context = element("div", "context-toolbar");
        const resultCount = element("p", "result-count");
        resultCount.id = "result-count";
        resultCount.setAttribute("aria-live", "polite");
        context.append(resultCount);
        if (state.view === "canvas") context.append(canvasControls());
        shell.append(context);
        return shell;
    }

    function metadataRow(label, value) {
        const row = element("div", "metadata-row");
        row.append(element("dt", "", label), element("dd", "", value));
        return row;
    }

    function filterMenu() {
        const details = element("details", "filter-menu");
        const summary = element("summary", "", "Filters");
        details.append(summary);
        const panel = element("div", "filter-panel");
        const groupOptions = [["all", "All groups"], ...manifest.groups.map(group => [group.id, group.title])];
        panel.append(
            filterSelect("Group", state.filters.group, groupOptions, value => {
                state.filters.group = value;
                render();
            }),
            filterSelect("Capture", state.filters.extent, [
                ["all", "All captures"],
                ["viewport", "Viewport"],
                ["intrinsic", "Intrinsic"],
                ["fullContent", "Full content"],
                ["fullContent2D", "Full content 2D"],
            ], value => {
                state.filters.extent = value;
                render();
            }),
            filterSelect("Routes", state.filters.routes, [
                ["all", "Any route state"],
                ["linked", "Linked"],
                ["unlinked", "Unlinked"],
                ["incoming", "Has incoming"],
                ["outgoing", "Has outgoing"],
            ], value => {
                state.filters.routes = value;
                render();
            }),
        );
        const clear = element("button", "clear-filters", "Clear filters");
        clear.type = "button";
        clear.addEventListener("click", () => {
            state.filters = { group: "all", extent: "all", routes: "all" };
            state.search = "";
            render();
        });
        panel.append(clear);
        details.append(panel);
        return details;
    }

    function filterSelect(labelText, value, options, onChange) {
        const select = element("select", "");
        for (const pair of options) {
            const option = element("option", "", pair[1]);
            option.value = pair[0];
            option.selected = pair[0] === value;
            select.append(option);
        }
        select.addEventListener("change", () => onChange(select.value));
        return labeledSelect(labelText, select);
    }

    function canvasControls() {
        const controls = element("div", "canvas-controls");
        const minus = element("button", "icon-button", "−");
        minus.type = "button";
        minus.setAttribute("aria-label", "Zoom out");
        minus.addEventListener("click", () => setZoom(state.zoom - 0.1));
        const zoom = element("input", "");
        zoom.id = "canvas-zoom";
        zoom.type = "range";
        zoom.min = "0.1";
        zoom.max = "1.5";
        zoom.step = "0.05";
        zoom.value = String(state.zoom);
        zoom.setAttribute("aria-label", "Canvas zoom");
        zoom.addEventListener("input", () => setZoom(Number(zoom.value)));
        const plus = element("button", "icon-button", "+");
        plus.type = "button";
        plus.setAttribute("aria-label", "Zoom in");
        plus.addEventListener("click", () => setZoom(state.zoom + 0.1));
        const value = element("output", "zoom-value", Math.round(state.zoom * 100) + "%");
        value.id = "zoom-value";
        value.setAttribute("for", "canvas-zoom");
        const fitGroup = element("button", "", "Fit group");
        fitGroup.type = "button";
        fitGroup.setAttribute("aria-keyshortcuts", "0");
        fitGroup.addEventListener("click", fitCurrentGroup);
        const fit = element("button", "primary-button", "Fit all");
        fit.type = "button";
        fit.setAttribute("aria-keyshortcuts", "F");
        fit.addEventListener("click", fitAll);
        controls.append(minus, zoom, plus, value, fitGroup, fit);
        return controls;
    }

    function variantSelector(screen, updateHistory = false) {
        const select = element("select", "");
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
        const button = element("button", "route-chip " + route.kind, cue + " · " + (destination?.title || destinationID));
        button.type = "button";
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

    function screenImage(screen, className) {
        const image = element("img", className || "");
        image.loading = "lazy";
        image.decoding = "async";
        image.src = imagePath(screen);
        image.alt = screen.title + " — " + (screenVariant(screen)?.title || "Default");
        return image;
    }

    function captureLabel(extent) {
        if (extent === "fullContent") return "Full content";
        if (extent === "fullContent2D") return "Full content 2D";
        return extent[0].toUpperCase() + extent.slice(1);
    }

    function canvasView() {
        const layout = element("main", "canvas-layout");
        const sidebar = canvasSidebar();
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
            const group = groupByID.get(item.id);
            const shelf = element("section", "group-shelf");
            shelf.dataset.groupId = item.id;
            Object.assign(shelf.style, rectStyle(item.frame));
            const shelfHeader = element("div", "shelf-header");
            shelfHeader.append(
                element("p", "eyebrow", "Group " + (group?.order + 1)),
                element("h2", "", group?.title || item.id),
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
        layout.append(sidebar, viewport, emptyResults());
        requestAnimationFrame(() => {
            applyZoom();
            updateSearchVisibility();
            if (!state.screen && !location.hash.includes("view=")) fitFirstGroup();
        });
        return layout;
    }

    function canvasSidebar() {
        const sidebar = element("aside", "canvas-sidebar");
        const heading = element("div", "sidebar-heading");
        heading.append(element("p", "eyebrow", "Browse"), element("h2", "", "Groups"));
        sidebar.append(heading);
        const navigation = element("nav", "group-navigation");
        navigation.setAttribute("aria-label", "Canvas groups");
        for (const group of manifest.groups) {
            const button = element("button", "group-button");
            button.type = "button";
            button.dataset.groupId = group.id;
            button.setAttribute("aria-current", String(group.id === state.group));
            const copy = element("span", "");
            copy.append(element("strong", "", group.title), element("small", "", group.screenIDs.length + " screens"));
            button.append(element("span", "group-index", String(group.order + 1).padStart(2, "0")), copy);
            button.addEventListener("click", () => {
                state.group = group.id;
                updateActiveGroup();
                fitCurrentGroup();
            });
            navigation.append(button);
        }
        sidebar.append(navigation, miniMap());
        const legend = element("div", "route-legend");
        legend.append(
            legendItem("push", "Push"),
            legendItem("modal", "Modal"),
        );
        sidebar.append(legend);
        const hint = element("p", "keyboard-hint", "Press / to search · F to fit all");
        sidebar.append(hint);
        return sidebar;
    }

    function legendItem(kind, title) {
        const item = element("span", "");
        item.append(element("i", kind), document.createTextNode(title));
        return item;
    }

    function miniMap() {
        const namespace = "http://www.w3.org/2000/svg";
        const wrapper = element("div", "mini-map");
        wrapper.append(element("p", "eyebrow", "Overview"));
        const svg = document.createElementNS(namespace, "svg");
        svg.id = "mini-map-svg";
        svg.setAttribute("viewBox", "0 0 " + manifest.canvas.size.width + " " + manifest.canvas.size.height);
        svg.setAttribute("role", "img");
        svg.setAttribute("aria-label", "Canvas overview. Select to move around the atlas.");
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
            const viewport = document.getElementById("canvas-viewport");
            if (!viewport) return;
            const bounds = svg.getBoundingClientRect();
            const x = (event.clientX - bounds.left) / bounds.width * manifest.canvas.size.width;
            const y = (event.clientY - bounds.top) / bounds.height * manifest.canvas.size.height;
            viewport.scrollTo({
                left: x * state.zoom - viewport.clientWidth / 2,
                top: y * state.zoom - viewport.clientHeight / 2,
                behavior: "smooth",
            });
        });
        wrapper.append(svg);
        return wrapper;
    }

    function rectAttributes(rect) {
        return {
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height,
        };
    }

    function screenCard(screen) {
        const variant = screenVariant(screen);
        const card = element("article", "screen-card");
        card.dataset.screenId = screen.id;
        card.dataset.groupId = screen.groupID;
        card.dataset.hidden = String(!matchesSearch(screen));
        card.tabIndex = 0;
        Object.assign(card.style, rectStyle(screen.frame));
        const cardHeader = element("header", "card-header");
        const title = element("div", "");
        title.append(element("h3", "", screen.title), element("p", "", groupByID.get(screen.groupID)?.title));
        const routeCount = screen.incomingRouteIDs.length + screen.outgoingRouteIDs.length;
        cardHeader.append(title, element("span", "route-count", routeCount + (routeCount === 1 ? " route" : " routes")));
        card.append(cardHeader);
        if (screen.variants.length > 1) {
            card.append(labeledSelect("State", variantSelector(screen), "card-state"));
        } else {
            card.append(element("p", "single-state", variant?.title || "Default"));
        }
        const imageButton = element("button", "card-image-button");
        imageButton.type = "button";
        imageButton.setAttribute("aria-label", "Inspect " + screen.title);
        const device = element("span", "device-preview");
        device.append(screenImage(screen));
        imageButton.append(device);
        imageButton.addEventListener("click", () => openScreen(screen.id, true));
        card.append(imageButton);
        const footer = element("footer", "card-footer");
        footer.append(element("span", "capture-badge", captureLabel(variant?.captureExtent || "viewport")));
        const inspect = element("button", "inspect-link", "Inspect →");
        inspect.type = "button";
        inspect.addEventListener("click", () => openScreen(screen.id, true));
        footer.append(inspect);
        card.append(footer);
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
        return {
            left: rect.x + "px",
            top: rect.y + "px",
            width: rect.width + "px",
            height: rect.height + "px",
        };
    }

    function listView() {
        const main = element("main", "list");
        const intro = element("div", "list-intro");
        intro.append(
            element("p", "eyebrow", "Catalog"),
            element("h2", "", manifest.screens.length + " screens across " + manifest.groups.length + " groups"),
            element("p", "", "Review captured states in a compact, scannable inventory."),
        );
        main.append(intro);
        for (const group of manifest.groups) {
            const section = element("section", "list-group");
            section.dataset.listGroupId = group.id;
            const heading = element("header", "list-group-header");
            heading.append(element("h2", "", group.title), element("span", "", group.screenIDs.length + " screens"));
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
        row.dataset.hidden = String(!matchesSearch(screen));
        const thumbnail = element("button", "list-thumbnail");
        thumbnail.type = "button";
        thumbnail.setAttribute("aria-label", "Inspect " + screen.title);
        thumbnail.append(screenImage(screen));
        thumbnail.addEventListener("click", () => openScreen(screen.id, true));
        const identity = element("div", "list-identity");
        identity.append(
            element("p", "eyebrow", captureLabel(variant?.captureExtent || "viewport")),
            element("h3", "", screen.title),
        );
        if (screen.variants.length > 1) {
            identity.append(labeledSelect("State", variantSelector(screen), "list-state"));
        } else {
            identity.append(element("p", "secondary", variant?.title || "Default"));
        }
        const profile = profileByID.get(state.profile);
        const traits = element("div", "list-traits");
        traits.append(
            element("span", "", profile?.title || state.profile),
            element("span", "", profile?.device || ""),
            element("span", "", profile?.colorScheme || ""),
        );
        const routes = element("div", "list-routes");
        const routeSummary = element("p", "secondary", screen.incomingRouteIDs.length + " incoming · "
            + screen.outgoingRouteIDs.length + " outgoing");
        routes.append(routeSummary);
        const quickRoutes = [...screen.outgoingRouteIDs, ...screen.incomingRouteIDs].slice(0, 2);
        for (const id of quickRoutes) {
            const route = routeByID.get(id);
            if (!route) continue;
            const direction = route.sourceScreenID === screen.id ? "outgoing" : "incoming";
            routes.append(routeButton(route, screen, direction));
        }
        const inspect = element("button", "list-inspect primary-button", "Inspect");
        inspect.type = "button";
        inspect.addEventListener("click", () => openScreen(screen.id, true));
        row.append(thumbnail, identity, traits, routes, inspect);
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
        dialog.setAttribute("aria-labelledby", "inspector-title");
        const header = element("header", "inspector-header");
        const heading = element("div", "");
        heading.append(
            element("p", "eyebrow", (group?.title || "Ungrouped") + " · "
                + (screenIndex + 1) + " of " + manifest.screens.length),
            element("h2", "", screen.title),
        );
        heading.querySelector("h2").id = "inspector-title";
        const headerActions = element("div", "inspector-header-actions");
        const previous = element("button", "icon-button", "←");
        previous.type = "button";
        previous.setAttribute("aria-label", "Previous screen");
        previous.setAttribute("aria-keyshortcuts", "[");
        previous.addEventListener("click", () => openScreen(neighboringScreen(-1)?.id));
        const next = element("button", "icon-button", "→");
        next.type = "button";
        next.setAttribute("aria-label", "Next screen");
        next.setAttribute("aria-keyshortcuts", "]");
        next.addEventListener("click", () => openScreen(neighboringScreen(1)?.id));
        const close = element("button", "close", "Close");
        close.type = "button";
        close.autofocus = true;
        close.addEventListener("click", closeInspector);
        headerActions.append(previous, next, close);
        header.append(heading, headerActions);
        dialog.append(header);

        const controls = element("div", "inspector-controls");
        controls.append(
            labeledSelect("State", variantSelector(screen, true)),
            labeledSelect("Profile", profileSelect()),
        );
        const scale = element("div", "scale-tabs");
        scale.setAttribute("aria-label", "Image scale");
        for (const option of [["fit", "Fit"], ["actual", "100%"]]) {
            const button = element("button", "", option[1]);
            button.type = "button";
            button.setAttribute("aria-pressed", String(state.inspectorScale === option[0]));
            button.addEventListener("click", () => {
                state.inspectorScale = option[0];
                updateInspectorScale();
            });
            scale.append(button);
        }
        controls.append(scale);
        dialog.append(controls);

        const body = element("div", "inspector-body");
        const preview = element("section", "inspector-preview");
        const previewToolbar = element("div", "preview-toolbar");
        previewToolbar.append(
            element("span", "capture-badge", captureLabel(variant.captureExtent)),
            element("span", "secondary", imageDimensions(metadata)),
        );
        const raw = element("a", "raw-link", "Open raw PNG ↗");
        raw.href = imagePath(screen);
        raw.target = "_blank";
        raw.rel = "noopener";
        previewToolbar.append(raw);
        const extentClass = variant.captureExtent === "fullContent"
            || variant.captureExtent === "fullContent2D" ? " full-content" : "";
        const imageFrame = element("div", "inspector-image " + state.inspectorScale + extentClass);
        imageFrame.id = "inspector-image";
        const device = element("div", "inspector-device");
        const fullImage = screenImage(screen);
        if (metadata) device.style.setProperty("--point-width", metadata.pointWidth + "px");
        device.append(fullImage);
        imageFrame.append(device);
        preview.append(previewToolbar, imageFrame);

        const details = element("aside", "inspector-details");
        details.append(inspectorMetadata(screen, variant, metadata));
        details.append(routeSection("Outgoing", screen, "outgoing"));
        details.append(routeSection("Incoming", screen, "incoming"));
        body.append(preview, details);
        dialog.append(body);
        dialog.addEventListener("cancel", event => {
            event.preventDefault();
            closeInspector();
        });
        return dialog;
    }

    function imageDimensions(metadata) {
        if (!metadata) return "Image metadata unavailable";
        return Math.round(metadata.pointWidth) + " × " + Math.round(metadata.pointHeight) + " pt · "
            + metadata.pixelWidth + " × " + metadata.pixelHeight + " px @" + metadata.scale + "×";
    }

    function inspectorMetadata(screen, variant, metadata) {
        const section = element("section", "detail-section");
        section.append(element("p", "eyebrow", "Capture details"));
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
        renderOrNavigate();
    }

    function emptyResults() {
        const empty = element("section", "empty-results");
        empty.id = "empty-results";
        empty.hidden = true;
        empty.append(
            element("p", "eyebrow", "No matches"),
            element("h2", "", "Try a broader search"),
            element("p", "", "Search includes group, screen, state, and connected route names."),
        );
        const clear = element("button", "primary-button", "Clear search and filters");
        clear.type = "button";
        clear.addEventListener("click", () => {
            state.search = "";
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
        if (count) count.textContent = visible.size + " of " + manifest.screens.length + " screens";
        const empty = document.getElementById("empty-results");
        if (empty) empty.hidden = visible.size !== 0;
        updateRouteFocus();
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
                ? "focus"
                : (connected.get(card.dataset.screenId) || (focused ? "unrelated" : "none"));
        }
        for (const route of document.querySelectorAll(".route")) {
            const isConnected = route.dataset.sourceScreenId === focused
                || route.dataset.destinationScreenId === focused;
            route.dataset.routeRelation = isConnected ? "focus" : (focused ? "unrelated" : "none");
        }
    }

    function applyZoom() {
        const stage = document.getElementById("canvas-stage");
        const scaled = document.getElementById("canvas-scaled");
        if (!stage || !scaled) return;
        stage.style.transform = "scale(" + state.zoom + ")";
        scaled.style.width = manifest.canvas.size.width * state.zoom + "px";
        scaled.style.height = manifest.canvas.size.height * state.zoom + "px";
        const slider = document.getElementById("canvas-zoom");
        if (slider) slider.value = String(state.zoom);
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
        }
    }

    function fitFrame(frame) {
        const viewport = document.getElementById("canvas-viewport");
        if (!viewport) return;
        const padding = 48;
        const horizontal = Math.max(viewport.clientWidth - padding * 2, 1) / Math.max(frame.width, 1);
        const vertical = Math.max(viewport.clientHeight - padding * 2, 1) / Math.max(frame.height, 1);
        state.zoom = Math.max(0.1, Math.min(1.5, horizontal, vertical));
        applyZoom();
        viewport.scrollTo({
            left: (frame.x + frame.width / 2) * state.zoom - viewport.clientWidth / 2,
            top: (frame.y + frame.height / 2) * state.zoom - viewport.clientHeight / 2,
            behavior: "smooth",
        });
    }

    function fitAll() {
        fitFrame({ x: 0, y: 0, width: manifest.canvas.size.width, height: manifest.canvas.size.height });
    }

    function fitCurrentGroup() {
        const group = manifest.canvas.groupFrames.find(item => item.id === state.group)
            || manifest.canvas.groupFrames[0];
        if (group) fitFrame(group.frame);
    }

    function fitFirstGroup() {
        const first = manifest.canvas.groupFrames[0];
        if (first) fitFrame(first.frame);
    }

    let canvasNavigationFrame = null;
    function scheduleCanvasNavigationUpdate() {
        if (canvasNavigationFrame !== null) return;
        canvasNavigationFrame = requestAnimationFrame(() => {
            canvasNavigationFrame = null;
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
        if (nearest) state.group = nearest;
        updateActiveGroup();
        updateMiniMapViewport();
    }

    function updateActiveGroup() {
        for (const button of document.querySelectorAll(".group-button")) {
            button.setAttribute("aria-current", String(button.dataset.groupId === state.group));
        }
        for (const group of document.querySelectorAll(".mini-group")) {
            group.dataset.active = String(group.dataset.groupId === state.group);
        }
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
        root.replaceChildren(toolbar(), state.view === "canvas" ? canvasView() : listView());
        const dialog = inspector();
        if (dialog) {
            root.append(dialog);
            requestAnimationFrame(() => dialog.showModal());
        }
        requestAnimationFrame(updateSearchVisibility);
    }

    window.addEventListener("hashchange", () => {
        parseHash();
        render();
    });
    window.addEventListener("resize", scheduleCanvasNavigationUpdate);
    window.addEventListener("keydown", event => {
        if (event.metaKey || event.ctrlKey || event.altKey) return;
        const target = event.target;
        const isEditing = target instanceof HTMLInputElement
            || target instanceof HTMLSelectElement
            || target instanceof HTMLTextAreaElement
            || target?.isContentEditable;
        if (event.key === "/" && !isEditing) {
            event.preventDefault();
            document.getElementById("global-search")?.focus();
            return;
        }
        if (isEditing) return;
        if (state.screen && event.key === "[") {
            event.preventDefault();
            openScreen(neighboringScreen(-1)?.id);
        } else if (state.screen && event.key === "]") {
            event.preventDefault();
            openScreen(neighboringScreen(1)?.id);
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
