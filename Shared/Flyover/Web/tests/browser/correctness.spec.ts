import { test, expect } from '@playwright/test';

test('profile changes preserve the full-content reading position', async ({ page }) => {
    await page.goto('./#view=canvas&screen=screen-1&variant=default&profile=phone-light');
    const inspector = page.locator('.inspector');
    const capture = inspector.locator('.inspector-device');
    await expect(inspector).toBeVisible();
    await expect.poll(() => capture.evaluate(node => node.scrollHeight)).toBeGreaterThan(1000);
    await capture.evaluate(node => { node.scrollTop = 350; });
    await inspector.getByLabel('Capture profile', { exact: true }).selectOption('phone-dark');
    await expect(page).toHaveURL(/profile=phone-dark/);
    await expect.poll(() => capture.evaluate(node => node.scrollTop)).toBe(350);
    await page.goBack();
    await expect.poll(() => capture.evaluate(node => node.scrollTop)).toBe(350);
});

for (const nextAction of ['profile', 'history', 'close', 'screen'] as const) {
    const preservesPosition = nextAction === 'profile' || nextAction === 'history';
    test(`pending reading position ${preservesPosition ? 'survives' : 'resets after'} ${nextAction} navigation`, async ({ page }) => {
        const held = Promise.withResolvers<void>();
        const requested = Promise.withResolvers<void>();
        await page.route('**/images/0/default/phone-dark.png', async route => {
            requested.resolve();
            await held.promise;
            await route.continue();
        });
        try {
            await page.goto('./#screen=screen-1&variant=default&profile=phone-light');
            const inspector = page.locator('.inspector');
            const capture = inspector.locator('.inspector-device');
            await expect.poll(() => capture.evaluate(node => node.scrollHeight)).toBeGreaterThan(1000);
            await capture.evaluate(node => { node.scrollTop = 350; });
            await inspector.getByLabel('Capture profile', { exact: true }).selectOption('phone-dark');
            await requested.promise;
            await expect(inspector.locator('img')).toHaveAttribute('src', /phone-dark/);
            if (nextAction === 'profile') {
                await inspector.getByLabel('Capture profile', { exact: true }).selectOption('phone-light');
            } else if (nextAction === 'history') {
                await page.goBack();
            } else if (nextAction === 'close') {
                await inspector.getByRole('button', { name: 'Close inspector', exact: true }).click();
                await expect(inspector).toHaveCount(0);
                await page.goBack();
                held.resolve();
            } else {
                await inspector.getByRole('button', { name: 'Next screen', exact: true }).click();
                await expect(inspector).toHaveAttribute('data-screen-id', 'screen-2');
            }
            await expect(inspector.locator('img')).toHaveAttribute('src', preservesPosition ? /phone-light/ : /phone-dark/);
            await expect.poll(() => capture.evaluate(node => node.scrollHeight)).toBeGreaterThan(1000);
            await expect.poll(() => capture.evaluate(node => node.scrollTop)).toBe(preservesPosition ? 350 : 0);
        } finally {
            held.resolve();
            await page.unrouteAll({ behavior: 'wait' });
        }
    });
}

test('superseded modal frames cannot open detached dialogs', async ({ page }) => {
    const errors: string[] = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto('./');
    await expect(page.locator('.screen-card')).toHaveCount(24);
    await page.evaluate(() => {
        // Both input events precede the next browser frame, as during queued input.
        document.getElementById('search-trigger')!.click();
        document.getElementById('search-trigger')!.click();
    });
    await expect(page.getByRole('dialog', { name: 'Search the atlas' })).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.getByRole('dialog')).toHaveCount(0);
    expect(errors).toEqual([]);
});

test('narrow inspector selects have full-sized controls without page overflow', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('./#screen=screen-1&variant=default&profile=phone-light');
    await expect(page.locator('.inspector')).toBeVisible();
    for (const select of await page.locator('.inspector select').all()) {
        expect((await select.boundingBox())!.height).toBeGreaterThanOrEqual(44);
    }
    expect(await page.evaluate(() => document.body.scrollWidth)).toBe(390);
});

test('dark action labels retain contrast in normal and hover states', async ({ page }) => {
    await page.emulateMedia({ colorScheme: 'dark' });
    await page.goto('./');
    await page.locator('#filter-trigger').click();
    const action = page.getByRole('button', { name: 'Show results' });
    const contrast = () => action.evaluate(node => {
        const style = getComputedStyle(node);
        const luminance = (color: string) => color.match(/[\d.]+/g)!.slice(0, 3).map(Number).map(value => value / 255).map(value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4).reduce((sum, value, index) => sum + value * [0.2126, 0.7152, 0.0722][index], 0);
        const values = [luminance(style.color), luminance(style.backgroundColor)].sort((a, b) => b - a);
        return (values[0] + 0.05) / (values[1] + 0.05);
    });
    expect(await contrast()).toBeGreaterThanOrEqual(4.5);
    await action.hover();
    expect(await contrast()).toBeGreaterThanOrEqual(4.5);
});
