import { fixture } from './fixture.ts';
import type { AtlasManifest, AtlasScreen } from '../../src/scripts/manifest.ts';

/** Production-sized atlas geometry and thumbnail density, without app screenshots. */
export function largeFixture(): AtlasManifest {
    const base = fixture();
    const screens: AtlasScreen[] = Array.from({ length: 57 }, (_, index) => ({
        ...base.screens[0], id: `large-${index}`, title: `Large ${index}`, groupID: 'first', groupOrder: 0, screenOrder: index,
        frame: { x: 50 + index % 15 * 560, y: 80 + Math.floor(index / 15) * 750, width: 350, height: 700 },
        incomingRouteIDs: [], outgoingRouteIDs: [],
        variants: base.screens[0].variants.map(variant => ({ ...variant,
            imagesByProfile: Object.fromEntries(base.profiles.map(profile => [profile.id, `images/large/${index}/${variant.id}/${profile.id}.png`])) })),
    }));
    const size = { width: 8660, height: 3114 };
    return { ...base, screens, routes: [],
        groups: [{ id: 'first', title: 'Large catalog', order: 0, rootScreenID: screens[0].id, screenIDs: screens.map(screen => screen.id) }],
        canvas: { size, initialFitSize: { width: 2500, height: size.height },
            groupFrames: [{ id: 'first', frame: { x: 0, y: 0, ...size } }], depthBandFrames: [],
            screenFrames: screens.map(screen => ({ id: screen.id, frame: screen.frame })), connectors: [] },
        images: screens.flatMap(screen => screen.variants.flatMap(variant => base.profiles.map(profile => ({
            ...base.images[0], screenID: screen.id, variantID: variant.id, profileID: profile.id,
            relativePath: variant.imagesByProfile[profile.id],
            thumbnailRelativePath: variant.imagesByProfile[profile.id].replace('.png', '-thumbnail.png'),
            thumbnailPixelWidth: 471, thumbnailPixelHeight: 1024,
            thumbnailVariants: [128, 256, 512].map(height => ({
                relativePath: variant.imagesByProfile[profile.id].replace('.png', `-thumbnail-${height}.png`),
                pixelWidth: Math.round(471 * height / 1024), pixelHeight: height,
            })),
        })))),
    };
}
