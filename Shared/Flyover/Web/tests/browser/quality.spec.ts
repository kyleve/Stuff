import AxeBuilder from '@axe-core/playwright';
import { test, expect } from '@playwright/test';

for (const surface of ['canvas', 'list', 'inspector', 'details'] as const) {
    test(`web chrome passes automated accessibility checks on ${surface}`, async ({ page }) => {
        await page.emulateMedia({ reducedMotion: 'reduce' });
        await page.goto('./');
        await expect(page.locator('.screen-card')).toHaveCount(24);
        if (surface !== 'canvas') {
            await page.getByRole('button', { name: 'List', exact: true }).click();
            await expect(page.locator('.list-row')).toHaveCount(24);
        }
        if (surface === 'inspector' || surface === 'details') {
            await page.locator('.list-thumbnail').first().click();
            await expect(page.locator('.inspector')).toBeVisible();
        }
        if (surface === 'details') {
            await page.getByRole('button', { name: 'Capture details', exact: true }).click();
            await expect(page.getByRole('button', { name: 'Close details', exact: true })).toBeVisible();
        }
        const result = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
        expect(result.violations, surface).toEqual([]);
    });
}

test('two-finger input zooms the canvas through the browser touch pipeline', async ({ page, context, browserName }, testInfo) => {
    test.skip(browserName !== 'chromium' || !testInfo.project.name.endsWith('portrait'), 'CDP touch injection uses Chromium portrait');
    await page.goto('./');
    await expect(page.locator('.screen-card')).toHaveCount(24);
    await expect(page.locator('#zoom-value')).not.toHaveText('100%');
    const initial = await page.locator('#zoom-value').textContent();
    const client = await context.newCDPSession(page);
    const points = (spread: number) => [
        { x: 190 - spread, y: 320, id: 1 }, { x: 190 + spread, y: 320, id: 2 },
    ];
    await client.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: points(40) });
    await client.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: points(80) });
    await client.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await expect(page.locator('#zoom-value')).not.toHaveText(initial!);
    await client.detach();
});

test('canvas uses thumbnail requests and releases them during inspection', async ({ page }) => {
    const requests: string[] = [];
    page.on('request', request => { if (request.url().includes('/images/')) requests.push(request.url()); });
    await page.goto('./');
    await expect(page.locator('.screen-card')).toHaveCount(24);
    await page.keyboard.press('f');
    await expect.poll(() => page.locator('.screen-card img').evaluateAll(images =>
        images.filter(image => image instanceof HTMLImageElement && image.complete && image.naturalWidth > 0).length
    )).toBe(24);
    expect(requests.every(url => url.includes('-thumbnail.png'))).toBe(true);
    expect(new Set(requests).size).toBe(24);
    expect(requests).toHaveLength(24);
    const pixels = await page.locator('.screen-card img').evaluateAll(images => images.reduce((sum, image) =>
        sum + (image as HTMLImageElement).naturalWidth * (image as HTMLImageElement).naturalHeight, 0));
    expect(pixels).toBeLessThanOrEqual(24 * 134 * 867);
    await page.locator('.card-image-button').first().click();
    await expect(page.locator('.inspector img')).toBeVisible();
    await expect.poll(() => page.locator('.screen-card img[src]').count()).toBe(0);
    expect(requests.filter(url => !url.includes('-thumbnail.png'))).toHaveLength(1);
});
