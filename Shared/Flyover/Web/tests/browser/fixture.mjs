import { deflateSync } from 'node:zlib';

/** Synthetic captures test browser behavior, not the native rendering pipeline. */
export function fixture() {
    const profiles = ['light', 'dark'].map(colorScheme => ({ id: `phone-${colorScheme}`, title: `Phone ${colorScheme}`, device: 'phone', orientation: 'portrait', colorScheme, dynamicType: 'large', contrast: 'standard', layoutDirection: 'left-to-right', legibilityWeight: 'regular', snapshotType: 'standard' }));
    const screens = Array.from({ length: 24 }, (_, index) => ({
        id: `screen-${index + 1}`, title: `Screen ${index + 1}`, groupID: index < 12 ? 'first' : 'second', groupOrder: index < 12 ? 0 : 1, screenOrder: index,
        viewport: { kind: 'device' }, navigationContainer: 'stack',
        frame: { x: 50 + index % 6 * 240, y: 80 + Math.floor(index / 6) * 520, width: 210, height: 480 },
        variants: ['default', 'alternate'].map(id => ({ id, title: id === 'default' ? 'Default' : 'Alternate', captureExtent: 'fullContent', imagesByProfile: Object.fromEntries(profiles.map(profile => [profile.id, `images/${index}/${id}/${profile.id}.png`])) })),
        incomingRouteIDs: index === 1 ? ['route-1'] : [], outgoingRouteIDs: index === 0 ? ['route-1'] : [],
    }));
    const geometry = { start: { x: 260, y: 300 }, firstControl: { x: 270, y: 300 }, secondControl: { x: 280, y: 300 }, end: { x: 290, y: 300 }, firstArrowPoint: { x: 284, y: 294 }, secondArrowPoint: { x: 284, y: 306 } };
    const groups = ['first', 'second'].map((id, order) => ({ id, order, title: `Group ${order + 1}`, rootScreenID: screens[order * 12].id, screenIDs: screens.slice(order * 12, order * 12 + 12).map(screen => screen.id) }));
    return {
        schemaVersion: 1, application: { id: 'fixture', title: 'Test Atlas' },
        build: { commit: 'abc1234', dirty: false, generatedAt: '2026-10-22T12:00:00Z', xcodeVersion: 'Fixture', simulatorDevice: 'Fixture', simulatorOS: 'Fixture' }, profiles, groups, screens,
        canvas: { size: { width: 1500, height: 2200 }, initialFitSize: { width: 1500, height: 1100 }, groupFrames: groups.map(group => ({ id: group.id, frame: { x: 0, y: group.order * 1040, width: 1500, height: 1040 } })), depthBandFrames: [], screenFrames: screens.map(screen => ({ id: screen.id, frame: screen.frame })), connectors: [{ routeID: 'route-1', geometry }] },
        routes: [{ id: 'route-1', sourceScreenID: 'screen-1', destinationScreenID: 'screen-2', kind: 'push', label: 'Details', geometry }],
        images: screens.flatMap(screen => screen.variants.flatMap(variant => profiles.map(profile => ({ screenID: screen.id, variantID: variant.id, profileID: profile.id, relativePath: variant.imagesByProfile[profile.id], pointWidth: 402, pointHeight: 2600, pixelWidth: 402, pixelHeight: 2600, scale: 1, captureExtent: 'fullContent' })))),
    };
}

export function capturePNG(dark) {
    const width = 402, height = 2600;
    const pixels = Buffer.alloc((width * 3 + 1) * height);
    for (let y = 0; y < height; y++) pixels.fill(dark ? 30 + (y % 60) : 190 + (y % 60), y * (width * 3 + 1) + 1, (y + 1) * (width * 3 + 1));
    const header = Buffer.alloc(13);
    header.writeUInt32BE(width, 0); header.writeUInt32BE(height, 4); header[8] = 8; header[9] = 2;
    const chunk = (type, payload) => {
        const data = Buffer.concat([Buffer.from(type), payload]);
        let crc = 0xffffffff;
        for (const byte of data) { crc ^= byte; for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0); }
        const prefix = Buffer.alloc(4), suffix = Buffer.alloc(4);
        prefix.writeUInt32BE(payload.length); suffix.writeUInt32BE((crc ^ 0xffffffff) >>> 0);
        return Buffer.concat([prefix, data, suffix]);
    };
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header), chunk('IDAT', deflateSync(pixels)), chunk('IEND', Buffer.alloc(0))]);
}
