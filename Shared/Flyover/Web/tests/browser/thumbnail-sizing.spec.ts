import { test, expect, type Page } from '@playwright/test';
import { largeFixture } from './large-fixture.ts';

test.use({ deviceScaleFactor: 3 });

async function openFittedAtlas(page: Page) {
    const requests: string[] = [];
    const errors: string[] = [];
    page.on('request', request => { if (request.url().includes('/images/')) requests.push(request.url()); });
    page.on('pageerror', error => errors.push(error.message));
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.route('**/manifest.json', route => route.fulfill({ json: largeFixture() }));
    await page.goto('./');
    await expect(page.locator('.screen-card')).toHaveCount(57);
    await expect.poll(() => page.locator('.screen-card img[src]').count()).toBeGreaterThan(0);
    await page.keyboard.press('f');
    const loadedPixels = () => page.locator('.screen-card img').evaluateAll(images => {
        const captures = images as HTMLImageElement[];
        if (!captures.every(image => image.complete && image.naturalWidth > 0
            && image.currentSrc.endsWith(image.getAttribute('src') || 'missing'))) return -1;
        return captures.reduce((sum, image) => sum + image.naturalWidth * image.naturalHeight, 0);
    });
    await expect.poll(async () => {
        const pixels = await loadedPixels();
        return pixels > 0 && pixels < 7_000_000;
    }).toBe(true);
    const fittedPixels = await loadedPixels();
    expect(fittedPixels).toBeGreaterThan(0);
    // The former fixed thumbnails decode 27,491,328 pixels for this catalog.
    expect(fittedPixels).toBeLessThan(7_000_000);
    if (page.viewportSize()!.width <= 440) expect(fittedPixels).toBeLessThan(500_000);
    expect(requests.every(url => /-thumbnail(?:-\d+)?\.png$/.test(url))).toBe(true);
    return { loadedPixels, fittedPixels, requests, errors };
}

test('production-sized atlas upgrades and downgrades thumbnails across selections', async ({ page }) => {
    const { loadedPixels, fittedPixels, requests, errors } = await openFittedAtlas(page);
    for (let index = 0; index < 8; index++) await page.keyboard.press('+');
    await expect.poll(() => page.locator('.screen-card img[src]').evaluateAll(images =>
        images.some(image => (image as HTMLImageElement).naturalHeight === 1024))).toBe(true);
    await page.keyboard.press('f');
    await expect.poll(loadedPixels).toBe(fittedPixels);
    expect(requests.every(url => /-thumbnail(?:-\d+)?\.png$/.test(url))).toBe(true);
    // A retained selection must pick the new profile at the same small size.
    await page.locator('.header-profile select').selectOption('phone-dark');
    await expect.poll(loadedPixels).toBe(fittedPixels);
    await expect.poll(() => page.locator('.screen-card img[src]').evaluateAll(images =>
        images.every(image => image.getAttribute('src')?.includes('phone-dark')))).toBe(true);
    await page.locator('.screen-card select').nth(30).selectOption('alternate');
    await expect(page.locator('.screen-card img').nth(30)).toHaveAttribute('src', /alternate\/phone-dark-thumbnail/);
    await expect.poll(loadedPixels).toBe(fittedPixels);
    expect(requests.every(url => /-thumbnail(?:-\d+)?\.png$/.test(url))).toBe(true);
    expect(errors).toEqual([]);
});

test('inspector releases and restores production-sized atlas thumbnails', async ({ page }) => {
    const { loadedPixels, fittedPixels, errors } = await openFittedAtlas(page);
    await page.locator('.header-profile select').selectOption('phone-dark');
    await page.locator('.screen-card select').nth(30).selectOption('alternate');
    await expect(page.locator('.screen-card img').nth(30)).toHaveAttribute('src', /alternate\/phone-dark-thumbnail/);
    await expect.poll(loadedPixels).toBe(fittedPixels);
    await page.locator('.card-image-button').nth(30).click();
    await expect(page.locator('.inspector img')).toHaveAttribute('src', /phone-dark\.png$/);
    await expect(page.locator('.screen-card img[src]')).toHaveCount(0);
    await page.getByRole('button', { name: 'Close inspector', exact: true }).click();
    await expect.poll(loadedPixels).toBe(fittedPixels);
    expect(errors).toEqual([]);
});

test('production-sized atlas list uses thumbnails sized for cover', async ({ page }) => {
    const { requests, errors } = await openFittedAtlas(page);
    await page.getByRole('button', { name: 'List', exact: true }).click();
    await expect.poll(() => page.locator('.list-row img[src]').count()).toBeGreaterThan(0);
    await expect.poll(() => page.locator('.list-row img[src]').evaluateAll(images =>
        images.every(image => (image as HTMLImageElement).complete && (image as HTMLImageElement).naturalHeight > 0)
    )).toBe(true);
    // Full-content list previews use cover rather than contain. At 3×, the
    // 76px mobile slot needs 228px of image width, so the 236×512 copy is required.
    if (page.viewportSize()!.width <= 440) {
        await expect.poll(() => page.locator('.list-row img[src]').evaluateAll(images =>
            images.every(image => (image as HTMLImageElement).naturalHeight === 512)
        )).toBe(true);
    }
    expect(requests.every(url => /-thumbnail(?:-\d+)?\.png$/.test(url))).toBe(true);
    expect(errors).toEqual([]);
});
