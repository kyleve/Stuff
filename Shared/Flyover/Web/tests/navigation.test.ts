import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readSelection, selectionHash } from '../src/scripts/navigation.ts';

const catalog = {
    screens: ['root', 'detail & +?#/☃'].map(id => ({ id, variants: [{ id: 'default' }, { id: 'empty & +?#/☃' }] })),
    profiles: [{ id: 'phone-light' }, { id: 'phone-dark' }],
};

void test('all state selections round trip, including delimiters and Unicode', () => {
    for (const view of ['canvas', 'list'] as const) {
        for (const screen of [null, ...catalog.screens.map(item => item.id)]) {
            const selection = { view, screen, profile: 'phone-dark', variants: new Map(catalog.screens.map(item => [item.id, item.variants[1].id])) };
            assert.deepEqual(readSelection(selectionHash(selection, catalog), catalog), selection);
        }
    }
});

void test('omitted defaults reset every state during history traversal', () => {
    const initial = readSelection('', catalog);
    const changed = { ...initial, variants: new Map(initial.variants) };
    changed.variants.set('root', catalog.screens[0].variants[1].id);
    const history = ['', selectionHash(changed, catalog)];
    assert.deepEqual(readSelection(history[1], catalog), changed);
    assert.deepEqual(readSelection(history[0], catalog), initial);
    assert.deepEqual(readSelection(history[1], catalog), changed);
    assert.equal(new URLSearchParams(selectionHash(initial, catalog).slice(1)).get('state.root'), null);
});

void test('unknown values resolve to catalog defaults and legacy inspector links still work', () => {
    assert.deepEqual(readSelection('#view=bad&screen=bad&profile=bad&state.root=bad', catalog), readSelection('', catalog));
    const selection = readSelection('#screen=root&variant=' + encodeURIComponent(catalog.screens[0].variants[1].id), catalog);
    assert.equal(selection.screen, 'root');
    assert.equal(selection.variants.get('root'), catalog.screens[0].variants[1].id);
    assert.equal(selection.variants.get(catalog.screens[1].id), 'default');
});
