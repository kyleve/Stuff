import type { AtlasManifest } from "./manifest.ts";

export type ViewMode = 'canvas' | 'list';
export type Panel = 'search' | 'groups' | 'filters' | 'build';
export type RouteDirection = 'incoming' | 'outgoing';
export interface Session {
    view: ViewMode; profile: string; screen: string | null; zoom: number; group: string;
    routeFocus: string | null; inspectorScale: 'fit' | 'actual'; inspectorDetails: boolean;
    panel: Panel | null; panelTrigger: string | null; commandQuery: string;
    pendingCanvasAction: 'fit-initial' | 'fit-group' | 'fit-all' | null;
    pendingCanvasPosition: { left: number; top: number } | null;
    pendingFocusKey: string | null; inspectorReturnFocusKey: string | null;
    canvas: { initialized: boolean; scrollLeft: number; scrollTop: number; viewportWidth: number; viewportHeight: number };
    list: { scrollTop: number };
    filters: { group: string; extent: string; routes: string };
}
export interface CommandEntry {
    kind: string; title: string; subtitle: string; search: string; action: () => void;
}

/** Mutable session state, owned once by the application and shared by its controllers. */
export function createSession(manifest: AtlasManifest): Session {
    return {
        view: "canvas",
        profile: manifest.profiles[0].id,
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
}
