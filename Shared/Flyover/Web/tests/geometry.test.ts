import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fittedZoom, initialZoom, manualZoom, rectIntersects, squaredDistance } from '../src/scripts/geometry.ts';

test('fit operations show large catalogs below the manual zoom floor on mobile', () => {
    for (const width of [320, 390, 844, 1280]) {
        const size = { width: 15_000, height: 6000 };
        const fit = fittedZoom(size, { width, height: 700 }, 1.5);
        assert.ok(size.width * fit <= width);
        assert.ok(size.height * fit <= 700);
        assert.ok(fit < 0.1);
        assert.equal(manualZoom(fit - 0.1, fit, 0.1, 1.5), fit);
        assert.ok(2500 * initialZoom(2500, width) <= width - 32 + 0.001);
    }
    assert.equal(manualZoom(3, 1, 0.1, 1.5), 1.5);
    assert.equal(manualZoom(-1, 1, 0.1, 1.5), 0.1);
});

test('viewport intersection excludes touching edges and distance uses canvas coordinates', () => {
    const visible = { left: 10, top: 10, right: 20, bottom: 20 };
    assert.equal(rectIntersects({ x: 0, y: 0, width: 10, height: 10 }, visible), false);
    assert.equal(rectIntersects({ x: 0, y: 0, width: 11, height: 11 }, visible), true);
    assert.equal(squaredDistance(0, 0, 3, 4), 25);
});
