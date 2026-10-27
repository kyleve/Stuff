import assert from 'node:assert/strict';
import { test } from 'node:test';
import { selectThumbnail } from '../src/scripts/thumbnail-selection.ts';
import { fixture } from './browser/fixture.ts';

void test('thumbnail selection follows displayed size and density in both zoom directions', () => {
    const image = fixture().images[0];
    Object.assign(image, { thumbnailRelativePath: 'large.png', thumbnailPixelWidth: 512, thumbnailPixelHeight: 1024,
        thumbnailVariants: [128, 256, 512].map(height => ({ relativePath: `${height}.png`, pixelWidth: height / 2, pixelHeight: height })) });
    const select = (width: number, height: number, ratio: number, fit: 'contain' | 'cover' = 'contain') =>
        selectThumbnail(image, 'full.png', { width, height }, ratio, fit).relativePath;
    assert.equal(select(20, 40, 3), '128.png');
    assert.equal(select(40, 80, 3), '256.png');
    assert.equal(select(100, 200, 2), '512.png');
    assert.equal(select(100, 200, 3), 'large.png');
    assert.equal(select(1000, 2000, 3), 'large.png');
    assert.equal(select(20, 40, 3), '128.png');
    assert.equal(select(0, 0, 3), '128.png');
    assert.equal(select(200, 60, 1), '128.png');
    assert.equal(select(200, 60, 1, 'cover'), '512.png');
});

void test('legacy exports use their thumbnail or full capture without inventing asset paths', () => {
    const image = fixture().images[0];
    assert.equal(selectThumbnail(image, 'full.png', { width: 1, height: 1 }, 3, 'contain').relativePath, image.thumbnailRelativePath);
    delete image.thumbnailRelativePath;
    delete image.thumbnailPixelWidth;
    delete image.thumbnailPixelHeight;
    assert.deepEqual(selectThumbnail(image, 'full.png', { width: 1, height: 1 }, 3, 'contain'), {
        relativePath: 'full.png', pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight,
    });
});
