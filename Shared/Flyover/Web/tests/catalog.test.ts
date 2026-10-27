import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { createCatalog } from '../src/scripts/catalog.ts';
import { createSession } from '../src/scripts/session.ts';
import { readManifest } from '../src/scripts/manifest.ts';
import { fixture } from './browser/fixture.ts';

void test('catalog selection preserves metadata and uses thumbnail pixels when present', () => {
    const manifest = fixture();
    const state = createSession(manifest);
    const selectedVariants = new Map<string, string>();
    const catalog = createCatalog({ manifest, state, selectedVariants });
    const screen = manifest.screens[0];
    assert.equal(catalog.screenVariant(screen).id, 'default');
    assert.equal(catalog.imagePath(screen), 'images/0/default/phone-light.png');
    const metadata = catalog.imageMetadata(screen)!;
    metadata.thumbnailRelativePath = 'thumb.png';
    metadata.thumbnailPixelWidth = 201;
    metadata.thumbnailPixelHeight = 1300;
    assert.equal(catalog.thumbnailPath(screen), 'thumb.png');
    assert.equal(catalog.screenThumbnail(screen, { width: 100, height: 100 }, 1, 'contain').pixelWidth, 201);
    selectedVariants.set(screen.id, 'alternate');
    state.profile = 'phone-dark';
    const alternate = catalog.imageMetadata(screen)!;
    delete alternate.thumbnailRelativePath;
    delete alternate.thumbnailPixelWidth;
    delete alternate.thumbnailPixelHeight;
    assert.equal(catalog.thumbnailPath(screen), 'images/0/alternate/phone-dark.png');
    assert.equal(catalog.screenThumbnail(screen, { width: 100, height: 100 }, 1, 'contain').pixelWidth, 402);
});

void test('search and filters include groups, named states, and route endpoints', () => {
    const manifest = fixture();
    const state = createSession(manifest);
    const catalog = createCatalog({ manifest, state, selectedVariants: new Map() });
    for (const term of ['group 1', 'screen 1', 'alternate', 'details', 'screen 2']) assert.ok(catalog.searchableText(manifest.screens[0]).includes(term));
    state.filters.routes = 'incoming';
    assert.deepEqual([...catalog.visibleScreenIDs()], ['screen-2']);
    state.filters.group = 'second';
    assert.equal(catalog.visibleScreenIDs().size, 0);
    state.filters.routes = 'unlinked';
    assert.equal(catalog.visibleScreenIDs().size, 12);
    state.filters.extent = 'viewport';
    assert.equal(catalog.visibleScreenIDs().size, 0);
});

void test('fixed viewports retain dimensions across device profiles', () => {
    const manifest = fixture();
    const screen = manifest.screens[0];
    const state = createSession(manifest);
    const catalog = createCatalog({ manifest, state, selectedVariants: new Map() });
    assert.deepEqual(catalog.captureViewportSize(screen), { width: 402, height: 874 });
    manifest.profiles[0].orientation = 'landscape';
    assert.deepEqual(catalog.captureViewportSize(screen), { width: 874, height: 402 });
    manifest.profiles[0].viewportSize = { width: 999, height: 777 };
    assert.deepEqual(catalog.captureViewportSize(screen), { width: 999, height: 777 });
    screen.viewport = { kind: 'fixed', fixedSize: { width: 100, height: 200 } };
    assert.equal(catalog.captureViewportAspect(screen), 0.5);
});

void test('shared native wire fixture drives the catalog without browser device constants', () => {
    const manifest = readManifest(JSON.parse(readFileSync(new URL('../../Tests/Fixtures/manifest-v1.json', import.meta.url), 'utf8')));
    const catalog = createCatalog({ manifest, state: createSession(manifest), selectedVariants: new Map() });
    assert.deepEqual(catalog.captureViewportSize(manifest.screens[0]), manifest.profiles[0].viewportSize);
    assert.equal(catalog.imagePath(manifest.screens[0]), manifest.images[0].relativePath);
});

void test('unsupported wire versions fail visibly at the loader boundary', () => {
    for (const input of [null, {}, { schemaVersion: 2 }]) assert.throws(() => readManifest(input), /schema version 1/);
    const manifest = fixture();
    assert.equal(readManifest(manifest), manifest);
});
