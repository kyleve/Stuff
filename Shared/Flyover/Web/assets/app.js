(() => {
    "use strict";

    const root = document.getElementById("app");
    const manifest = window.FLYOVER_MANIFEST;
    if (!manifest || manifest.schemaVersion !== 1) {
        root.innerHTML = '<main class="error"><h1>Flyover export error</h1><p>This site requires manifest schema version 1.</p></main>';
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

    function matchesSearch(screen) {
        const query = state.search.trim().toLocaleLowerCase();
        if (!query) return true;
        const group = groupByID.get(screen.groupID);
        return [group?.title, screen.title, ...screen.variants.map(variant => variant.title)]
            .some(value => value?.toLocaleLowerCase().includes(query));
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
        const next = `#${values}`;
        if (location.hash !== next) location.hash = next;
    }

    function chooseView(view) {
        state.view = view;
        writeHash();
        render();
    }

    function chooseProfile(profile) {
        state.profile = profile;
        writeHash();
        render();
    }

    function chooseVariant(screen, variantID, updateHistory = false) {
        selectedVariants.set(screen.id, variantID);
        if (state.screen === screen.id || updateHistory) {
            state.screen = screen.id;
            writeHash();
        }
        render();
    }

    function openScreen(screenID) {
        const screen = screenByID.get(screenID);
        if (!screen) return;
        selectedVariants.set(screen.id, screen.variants[0]?.id);
        state.screen = screen.id;
        writeHash();
        render();
    }

    function toolbar() {
        const bar = element("header", "toolbar");
        bar.append(element("h1", "", manifest.application.title));
        bar.append(element("span", "build", manifest.build.commit.slice(0, 12)));
        if (manifest.build.dirty) bar.append(element("span", "dirty", "Dirty build"));
        bar.append(element("span", "build", manifest.build.generatedAt));
        bar.append(element("span", "toolbar-spacer"));

        const profileLabel = element("label", "");
        profileLabel.append(element("span", "", "Profile"));
        const profile = element("select", "");
        profile.setAttribute("aria-label", "Capture profile");
        for (const item of manifest.profiles) {
            const option = element("option", "", item.title);
            option.value = item.id;
            option.selected = item.id === state.profile;
            profile.append(option);
        }
        profile.addEventListener("change", () => chooseProfile(profile.value));
        profileLabel.append(profile);
        bar.append(profileLabel);

        const tabs = element("div", "view-tabs");
        for (const view of ["canvas", "list"]) {
            const button = element("button", "", view[0].toUpperCase() + view.slice(1));
            button.type = "button";
            button.setAttribute("aria-pressed", String(state.view === view));
            button.addEventListener("click", () => chooseView(view));
            tabs.append(button);
        }
        bar.append(tabs);

        const search = element("input", "");
        search.type = "search";
        search.placeholder = "Search screens and states";
        search.setAttribute("aria-label", "Search screens and states");
        search.value = state.search;
        search.addEventListener("input", () => {
            state.search = search.value;
            updateSearchVisibility();
        });
        bar.append(search);

        if (state.view === "canvas") {
            const zoomLabel = element("label", "");
            zoomLabel.append(element("span", "", "Zoom"));
            const zoom = element("input", "");
            zoom.type = "range";
            zoom.min = "0.1";
            zoom.max = "1.5";
            zoom.step = "0.05";
            zoom.value = String(state.zoom);
            zoom.addEventListener("input", () => {
                state.zoom = Number(zoom.value);
                applyZoom();
            });
            zoomLabel.append(zoom);
            bar.append(zoomLabel);
            const fit = element("button", "", "Fit All");
            fit.type = "button";
            fit.addEventListener("click", fitAll);
            bar.append(fit);
        }
        return bar;
    }

    function variantSelector(screen, updateHistory = false) {
        const select = element("select", "");
        select.setAttribute("aria-label", `State for ${screen.title}`);
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

    function routeButtons(screen) {
        const links = element("div", "route-links");
        const routeIDs = [...screen.incomingRouteIDs, ...screen.outgoingRouteIDs];
        for (const id of routeIDs) {
            const route = routeByID.get(id);
            const isOutgoing = route.sourceScreenID === screen.id;
            const destinationID = isOutgoing ? route.destinationScreenID : route.sourceScreenID;
            const destination = screenByID.get(destinationID);
            const cue = isOutgoing ? (route.kind === "modal" ? "Modal" : "Push") : "Back";
            const button = element("button", "", `${cue}: ${destination?.title || destinationID}`);
            button.type = "button";
            button.addEventListener("click", event => {
                event.stopPropagation();
                openScreen(destinationID);
            });
            links.append(button);
        }
        return links;
    }

    function screenImage(screen, className) {
        const image = element("img", className || "");
        image.loading = "lazy";
        image.src = imagePath(screen);
        image.alt = `${screen.title} — ${screenVariant(screen)?.title || "Default"}`;
        return image;
    }

    function canvasView() {
        const viewport = element("main", "canvas-viewport");
        viewport.id = "canvas-viewport";
        const scaled = element("div", "canvas-scaled");
        scaled.id = "canvas-scaled";
        const stage = element("div", "canvas-stage");
        stage.id = "canvas-stage";
        stage.style.width = `${manifest.canvas.size.width}px`;
        stage.style.height = `${manifest.canvas.size.height}px`;

        for (const item of manifest.canvas.groupFrames) {
            const group = groupByID.get(item.id);
            const shelf = element("section", "group-shelf");
            Object.assign(shelf.style, rectStyle(item.frame));
            shelf.append(element("h2", "", group?.title || item.id));
            stage.append(shelf);
        }
        for (const item of manifest.canvas.depthBandFrames) {
            const band = element("div", "depth-band");
            Object.assign(band.style, rectStyle(item.frame));
            band.append(element("span", "", item.kind === "unlinked" ? "Unlinked" : `Depth ${item.depth}`));
            stage.append(band);
        }
        stage.append(routeCanvas());

        for (const screen of manifest.screens) {
            const card = element("article", "screen-card");
            card.dataset.screenId = screen.id;
            card.dataset.hidden = String(!matchesSearch(screen));
            Object.assign(card.style, rectStyle(screen.frame));
            card.append(element("h3", "", screen.title));
            card.append(variantSelector(screen));
            const imageButton = element("button", "card-image-button");
            imageButton.type = "button";
            imageButton.setAttribute("aria-label", `Inspect ${screen.title}`);
            imageButton.append(screenImage(screen));
            imageButton.addEventListener("click", () => openScreen(screen.id));
            card.append(imageButton);
            card.append(routeButtons(screen));
            stage.append(card);
        }
        scaled.append(stage);
        viewport.append(scaled);
        requestAnimationFrame(() => {
            applyZoom();
            if (!state.screen && !location.hash.includes("view=")) fitFirstGroup();
        });
        return viewport;
    }

    function routeCanvas() {
        const namespace = "http://www.w3.org/2000/svg";
        const svg = document.createElementNS(namespace, "svg");
        svg.classList.add("canvas-routes");
        svg.setAttribute("width", manifest.canvas.size.width);
        svg.setAttribute("height", manifest.canvas.size.height);
        svg.setAttribute("viewBox", `0 0 ${manifest.canvas.size.width} ${manifest.canvas.size.height}`);
        for (const route of manifest.routes) {
            const geometry = route.geometry;
            const path = document.createElementNS(namespace, "path");
            path.setAttribute("d", `M ${geometry.start.x} ${geometry.start.y} C ${geometry.firstControl.x} ${geometry.firstControl.y}, ${geometry.secondControl.x} ${geometry.secondControl.y}, ${geometry.end.x} ${geometry.end.y}`);
            path.setAttribute("class", route.kind === "modal" ? "route-modal" : "route-push");
            svg.append(path);
            const arrow = document.createElementNS(namespace, "polygon");
            arrow.setAttribute("points", `${geometry.end.x},${geometry.end.y} ${geometry.firstArrowPoint.x},${geometry.firstArrowPoint.y} ${geometry.secondArrowPoint.x},${geometry.secondArrowPoint.y}`);
            arrow.setAttribute("class", route.kind === "modal" ? "route-arrow-modal" : "route-arrow-push");
            svg.append(arrow);
        }
        return svg;
    }

    function rectStyle(rect) {
        return {
            left: `${rect.x}px`,
            top: `${rect.y}px`,
            width: `${rect.width}px`,
            height: `${rect.height}px`,
        };
    }

    function listView() {
        const main = element("main", "list");
        for (const group of manifest.groups) {
            const section = element("section", "");
            section.append(element("h2", "", group.title));
            for (const screenID of group.screenIDs) {
                const screen = screenByID.get(screenID);
                if (!screen) continue;
                const row = element("article", "list-row");
                row.dataset.screenId = screen.id;
                row.dataset.hidden = String(!matchesSearch(screen));
                const heading = element("strong", "", screen.title);
                row.append(heading);
                row.append(variantSelector(screen));
                row.append(screenImage(screen));
                const summary = element("div", "route-summary");
                summary.textContent = `${screen.incomingRouteIDs.length} incoming · ${screen.outgoingRouteIDs.length} outgoing`;
                summary.append(routeButtons(screen));
                row.append(summary);
                const inspect = element("button", "", "Inspect");
                inspect.type = "button";
                inspect.addEventListener("click", () => openScreen(screen.id));
                row.append(inspect);
                section.append(row);
            }
            main.append(section);
        }
        return main;
    }

    function inspector() {
        const screen = screenByID.get(state.screen);
        if (!screen) return null;
        const variant = screenVariant(screen);
        const dialog = element("dialog", "");
        dialog.id = "inspector";
        dialog.setAttribute("aria-labelledby", "inspector-title");
        const header = element("header", "inspector-header");
        const title = element("h2", "", screen.title);
        title.id = "inspector-title";
        header.append(title);
        const close = element("button", "close", "Close");
        close.type = "button";
        close.addEventListener("click", closeInspector);
        header.append(close);
        dialog.append(header);

        const controls = element("div", "inspector-controls");
        const stateLabel = element("label", "");
        stateLabel.append(element("span", "", "State"));
        const states = variantSelector(screen, true);
        stateLabel.append(states);
        controls.append(stateLabel);
        const profileLabel = element("label", "");
        profileLabel.append(element("span", "", "Profile"));
        const profiles = element("select", "");
        for (const item of manifest.profiles) {
            const option = element("option", "", item.title);
            option.value = item.id;
            option.selected = item.id === state.profile;
            profiles.append(option);
        }
        profiles.addEventListener("change", () => chooseProfile(profiles.value));
        profileLabel.append(profiles);
        controls.append(profileLabel);
        controls.append(routeButtons(screen));
        dialog.append(controls);

        const body = element("div", "inspector-body");
        const imageFrame = element("div", `inspector-image ${variant.captureExtent === "fullContent" || variant.captureExtent === "fullContent2D" ? "full-content" : ""}`);
        const fullImage = screenImage(screen);
        const metadata = imageMetadata(screen);
        if (variant.captureExtent === "fullContent" && metadata) {
            fullImage.style.width = `${metadata.pointWidth}px`;
        }
        imageFrame.append(fullImage);
        body.append(imageFrame);
        const raw = element("a", "raw-link", "Open raw PNG");
        raw.href = imagePath(screen);
        body.append(raw);
        dialog.append(body);
        dialog.addEventListener("close", closeInspector);
        return dialog;
    }

    function closeInspector() {
        state.screen = null;
        writeHash();
        render();
    }

    function updateSearchVisibility() {
        for (const node of document.querySelectorAll("[data-screen-id]")) {
            const screen = screenByID.get(node.dataset.screenId);
            node.dataset.hidden = String(!matchesSearch(screen));
        }
    }

    function applyZoom() {
        const stage = document.getElementById("canvas-stage");
        const scaled = document.getElementById("canvas-scaled");
        if (!stage || !scaled) return;
        stage.style.transform = `scale(${state.zoom})`;
        scaled.style.width = `${manifest.canvas.size.width * state.zoom}px`;
        scaled.style.height = `${manifest.canvas.size.height * state.zoom}px`;
        const slider = document.querySelector('.toolbar input[type="range"]');
        if (slider) slider.value = String(state.zoom);
    }

    function fitFrame(frame) {
        const viewport = document.getElementById("canvas-viewport");
        if (!viewport) return;
        const horizontal = Math.max(viewport.clientWidth - 32, 1) / Math.max(frame.width, 1);
        const vertical = Math.max(viewport.clientHeight - 32, 1) / Math.max(frame.height, 1);
        state.zoom = Math.max(0.1, Math.min(1.5, horizontal, vertical));
        applyZoom();
        viewport.scrollTo({ left: frame.x * state.zoom, top: frame.y * state.zoom });
    }

    function fitAll() {
        fitFrame({ x: 0, y: 0, width: manifest.canvas.size.width, height: manifest.canvas.size.height });
    }

    function fitFirstGroup() {
        const first = manifest.canvas.groupFrames[0];
        if (first) fitFrame(first.frame);
    }

    function render() {
        root.replaceChildren(toolbar(), state.view === "canvas" ? canvasView() : listView());
        const dialog = inspector();
        if (dialog) {
            root.append(dialog);
            requestAnimationFrame(() => dialog.showModal());
        }
    }

    window.addEventListener("hashchange", () => {
        parseHash();
        render();
    });
    parseHash();
    render();
})();
