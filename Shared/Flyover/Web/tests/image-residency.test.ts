import assert from 'node:assert/strict';
import { test } from 'node:test';
import { selectResidentImages, type ImageCandidate } from '../src/scripts/image-residency.ts';

const candidates = (count: number, isVisible: boolean, imagePixels = 1_000_000): ImageCandidate[] => Array.from({ length: count }, (_, index) => ({ screen: { id: `${isVisible}-${index}` }, isVisible, imagePixels }));

void test('all visible screens remain resident even beyond both speculative budgets', () => {
    const visible = candidates(20, true, 5_000_000);
    const result = selectResidentImages([...candidates(4, false), ...visible], 6, 24_000_000);
    assert.deepEqual([...result], visible.map(item => item.screen.id));
});

void test('offscreen prefetch observes image count and decoded pixel limits', () => {
    assert.equal(selectResidentImages(candidates(20, false), 6, 24_000_000).size, 6);
    assert.equal(selectResidentImages(candidates(20, false, 10_000_000), 6, 24_000_000).size, 2);
    assert.equal(selectResidentImages(candidates(1, false, 30_000_000), 6, 24_000_000).size, 1);
    assert.equal(selectResidentImages([], 6, 24_000_000).size, 0);
});
