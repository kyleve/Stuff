import assert from 'node:assert/strict';
import { test } from 'node:test';
import { openAtlas } from '../../Web/src/scripts/load-atlas.ts';

test('loader uses the hosted subdirectory and starts only after valid JSON arrives', async () => {
    const requested = [];
    const manifest = { schemaVersion: 1 };
    const shown = [];
    globalThis.location = { protocol: 'http:' };
    globalThis.document = { baseURI: 'http://localhost:4321/reviews/atlas/' };
    globalThis.fetch = async url => {
        requested.push(String(url));
        return { ok: true, json: async () => manifest };
    };
    const root = { removeAttribute: name => shown.push(name) };
    await openAtlas(root, value => shown.push(value));
    assert.deepEqual(requested, ['http://localhost:4321/reviews/atlas/manifest.json']);
    assert.deepEqual(shown, [manifest, 'aria-busy']);
});

test('load errors remain visible and never start a partial viewer', async () => {
    for (const scenario of ['http', 'json', 'schema', 'network', 'file', 'startup']) {
        const removed = [];
        let displayed;
        let starts = 0;
        globalThis.location = { protocol: scenario === 'file' ? 'file:' : 'http:' };
        globalThis.document = {
            baseURI: 'http://localhost:4321/',
            createElement(tag) {
                return { tag, children: [], setAttribute() {}, append(...nodes) { this.children.push(...nodes); } };
            },
        };
        globalThis.fetch = async () => {
            if (scenario === 'file') assert.fail('file viewing must not fetch');
            if (scenario === 'network') throw Error('Network unavailable');
            return { ok: scenario !== 'http', status: 404, json: async () => {
                if (scenario === 'json') throw Error('Invalid JSON');
                return { schemaVersion: scenario === 'schema' ? 2 : 1 };
            } };
        };
        await openAtlas({ replaceChildren: node => { displayed = node; }, removeAttribute: name => removed.push(name) }, () => {
            starts++;
            if (scenario === 'startup') throw Error('Invalid catalog');
        });
        assert.equal(starts, scenario === 'startup' ? 1 : 0);
        assert.equal(displayed.children[0].textContent, 'Flyover cannot open this atlas');
        assert.ok(displayed.children[1].textContent.length > 0);
        assert.deepEqual(removed, ['aria-busy']);
    }
});
