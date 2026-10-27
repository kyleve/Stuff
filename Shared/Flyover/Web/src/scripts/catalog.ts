import { selectThumbnail } from "./thumbnail-selection.ts";
import type { AtlasGroup, AtlasImage, AtlasThumbnail, AtlasManifest, AtlasProfile, AtlasRoute, AtlasScreen, AtlasVariant, Size } from "./manifest.ts";
import type { Session } from "./session.ts";

interface Dependencies {
    manifest: AtlasManifest;
    selectedVariants: Map<string, string>;
    state: Session;
}

export interface Catalog {
    groupByID: ReadonlyMap<string, AtlasGroup>;
    screenByID: ReadonlyMap<string, AtlasScreen>;
    routeByID: ReadonlyMap<string, AtlasRoute>;
    imagePath: (screen: AtlasScreen) => string;
    thumbnailPath: (screen: AtlasScreen) => string;
    screenVariant: (screen: AtlasScreen) => AtlasVariant;
    captureViewportAspect: (screen: AtlasScreen) => number;
    matchesFilters: (screen: AtlasScreen) => boolean;
    imageMetadata: (screen: AtlasScreen) => AtlasImage | undefined;
    captureViewportSize: (screen: AtlasScreen) => Size;
    profileByID: ReadonlyMap<string, AtlasProfile>;
    searchableText: (screen: AtlasScreen) => string;
    visibleScreenIDs: () => Set<string>;
    screenThumbnail: (screen: AtlasScreen, displaySize: Size, pixelRatio: number, fit: 'contain' | 'cover') => AtlasThumbnail;
}

export function createCatalog(deps: Dependencies): Catalog {
    const screenByID = new Map(deps.manifest.screens.map(screen => [screen.id, screen]));

    const groupByID = new Map(deps.manifest.groups.map(group => [group.id, group]));

    const routeByID = new Map(deps.manifest.routes.map(route => [route.id, route]));

    const profileByID = new Map(deps.manifest.profiles.map(profile => [profile.id, profile]));

    const imageByKey = new Map(deps.manifest.images.map(image => [
        imageKey(image.screenID, image.variantID, image.profileID),
        image,
    ]));

    function screenVariant(screen: AtlasScreen) {
        const id = deps.selectedVariants.get(screen.id);
        return screen.variants.find(variant => variant.id === id) || screen.variants[0];
    }

    function imagePath(screen: AtlasScreen) {
        return screenVariant(screen)?.imagesByProfile[deps.state.profile] || "";
    }

    function imageKey(screenID: string, variantID: string, profileID: string) {
        return JSON.stringify([screenID, variantID, profileID]);
    }

    function imageMetadata(screen: AtlasScreen) {
        const variant = screenVariant(screen);
        return imageByKey.get(imageKey(screen.id, variant?.id, deps.state.profile));
    }

    function thumbnailPath(screen: AtlasScreen) {
        return imageMetadata(screen)?.thumbnailRelativePath || imagePath(screen);
    }

    function connectedRoutes(screen: AtlasScreen) {
        return [...screen.incomingRouteIDs, ...screen.outgoingRouteIDs]
            .map(id => routeByID.get(id))
            .filter((route): route is AtlasRoute => route !== undefined);
    }

    function searchableText(screen: AtlasScreen) {
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

    function matchesFilters(screen: AtlasScreen) {
        if (deps.state.filters.group !== "all" && screen.groupID !== deps.state.filters.group) return false;
        if (deps.state.filters.extent !== "all" && screenVariant(screen)?.captureExtent !== deps.state.filters.extent) {
            return false;
        }
        if (deps.state.filters.routes === "incoming" && screen.incomingRouteIDs.length === 0) return false;
        if (deps.state.filters.routes === "outgoing" && screen.outgoingRouteIDs.length === 0) return false;
        if (deps.state.filters.routes === "linked"
            && screen.incomingRouteIDs.length + screen.outgoingRouteIDs.length === 0) return false;
        if (deps.state.filters.routes === "unlinked"
            && screen.incomingRouteIDs.length + screen.outgoingRouteIDs.length !== 0) return false;
        return true;
    }

    function visibleScreenIDs() {
        return new Set(deps.manifest.screens.filter(matchesFilters).map(screen => screen.id));
    }

    function captureViewportSize(screen: AtlasScreen) {
        if (screen.viewport.kind === "fixed" && screen.viewport.fixedSize) {
            return screen.viewport.fixedSize;
        }
        const profile = profileByID.get(deps.state.profile);
        if (profile?.viewportSize) return profile.viewportSize;
        // Compatibility for schema-1 artifacts generated before numeric profile sizes.
        if (profile?.device === "tablet") return { width: 834, height: 1194 };
        if (profile?.orientation === "landscape") return { width: 874, height: 402 };
        return { width: 402, height: 874 };
    }

    function captureViewportAspect(screen: AtlasScreen) {
        const size = captureViewportSize(screen);
        return size.width / size.height;
    }

    function screenThumbnail(screen: AtlasScreen, displaySize: Size, pixelRatio: number, fit: 'contain' | 'cover') {
        return selectThumbnail(imageMetadata(screen), imagePath(screen), displaySize, pixelRatio, fit);
    }

    return { groupByID, screenByID, routeByID, imagePath, thumbnailPath, screenVariant, captureViewportAspect, matchesFilters, imageMetadata, captureViewportSize, profileByID, searchableText, visibleScreenIDs, screenThumbnail };
}
