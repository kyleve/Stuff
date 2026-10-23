/** Schema 1 presentation contract. Native export and Tools.flyover_manifest own catalog validation. */
export interface Size { width: number; height: number }
export interface Point { x: number; y: number }
export interface Rect extends Size, Point { }
export interface Geometry {
    start: Point; end: Point; firstControl: Point; secondControl: Point;
    firstArrowPoint: Point; secondArrowPoint: Point;
}
export type CaptureExtent = 'viewport' | 'intrinsic' | 'fullContent' | 'fullContent2D';
export interface AtlasVariant {
    id: string; title: string; captureExtent: CaptureExtent; imagesByProfile: Record<string, string>;
}
export interface AtlasScreen {
    id: string; title: string; groupID: string; groupOrder: number; screenOrder: number;
    viewport: { kind: 'device'; fixedSize?: null } | { kind: 'fixed'; fixedSize: Size };
    navigationContainer: 'stack' | 'none'; frame: Rect; variants: AtlasVariant[];
    incomingRouteIDs: string[]; outgoingRouteIDs: string[];
}
export interface AtlasGroup {
    id: string; title: string; order: number; rootScreenID: string; screenIDs: string[];
}
export interface AtlasRoute {
    id: string; sourceScreenID: string; destinationScreenID: string;
    kind: 'push' | 'modal'; label?: string | null; geometry: Geometry;
}
export interface AtlasProfile {
    id: string; title: string; device: string; orientation: string; colorScheme: string;
    dynamicType: string; contrast: string; layoutDirection: string; legibilityWeight: string; snapshotType: string;
}
export interface AtlasImage {
    screenID: string; variantID: string; profileID: string; relativePath: string;
    thumbnailRelativePath?: string | null; thumbnailPixelWidth?: number | null; thumbnailPixelHeight?: number | null;
    pointWidth: number; pointHeight: number; pixelWidth: number; pixelHeight: number; scale: number; captureExtent: CaptureExtent;
}
export interface AtlasManifest {
    schemaVersion: 1;
    application: { id: string; title: string };
    build: { commit: string; dirty: boolean; branch?: string | null; generatedAt: string; xcodeVersion: string; simulatorDevice: string; simulatorOS: string };
    profiles: AtlasProfile[]; groups: AtlasGroup[]; screens: AtlasScreen[]; routes: AtlasRoute[]; images: AtlasImage[];
    canvas: {
        size: Size; initialFitSize: Size;
        groupFrames: { id: string; frame: Rect }[];
        screenFrames: { id: string; frame: Rect }[];
        depthBandFrames: { groupID: string; kind: string; depth?: number | null; frame: Rect }[];
        connectors: { routeID: string; geometry: Geometry }[];
    };
}

/** Check the wire version here; the exporter validates the complete catalog before publication. */
export function readManifest(value: unknown): AtlasManifest {
    if (!value || typeof value !== 'object' || !('schemaVersion' in value) || value.schemaVersion !== 1) {
        throw new Error('This site requires manifest schema version 1.');
    }
    return value as AtlasManifest;
}
