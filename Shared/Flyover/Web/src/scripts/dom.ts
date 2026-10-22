import type { AtlasImage, Rect } from "./manifest.ts";

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

export function element<K extends keyof HTMLElementTagNameMap>(tag: K, className: string, text?: string | number) {
    const value = document.createElement(tag);
    if (className) value.className = className;
    if (text !== undefined) value.textContent = String(text);
    return value;
}

export function quantity(count: number, singular: string) {
    return count + " " + (count === 1 ? singular : singular + "s");
}

export function icon(name: keyof typeof iconPaths) {
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

export function iconButton(iconName: keyof typeof iconPaths, label: string, className = "icon-button", visibleLabel = false) {
    const button = element("button", className);
    button.type = "button";
    button.setAttribute("aria-label", label);
    button.title = label;
    button.append(icon(iconName));
    if (visibleLabel) button.append(element("span", "button-label", label));
    return button;
}

export function formatGeneratedAt(value: string) {
    const date = new Date(value);
    if (Number.isNaN(date.valueOf())) return value;
    return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(date);
}

export function metadataRow(label: string, value: string) {
    const row = element("div", "metadata-row");
    row.append(element("dt", "", label), element("dd", "selectable-text", value));
    return row;
}

export function captureLabel(extent: string) {
    if (extent === "fullContent") return "Full content";
    if (extent === "fullContent2D") return "Full content 2D";
    if (!extent) return "Viewport";
    return extent[0].toUpperCase() + extent.slice(1);
}

export function rectStyle(rect: Rect) {
    return { left: rect.x + "px", top: rect.y + "px", width: rect.width + "px", height: rect.height + "px" };
}

export function imageDimensions(metadata: AtlasImage | undefined) {
    if (!metadata) return "Image metadata unavailable";
    return Math.round(metadata.pointWidth) + " × " + Math.round(metadata.pointHeight) + " pt · "
        + metadata.pixelWidth + " × " + metadata.pixelHeight + " px @" + metadata.scale + "×";
}

export function rectAttributes(rect: Rect) {
    return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
}

export function visibleFocusTarget(focusKey: string | null) {
    if (!focusKey) return null;
    const target = document.querySelector<HTMLElement>('[data-focus-key="' + CSS.escape(focusKey) + '"]');
    if (!target || target.closest('[data-hidden="true"], [aria-hidden="true"]')) return null;
    const style = window.getComputedStyle(target);
    return style.display === "none" || style.visibility === "hidden" ? null : target;
}
