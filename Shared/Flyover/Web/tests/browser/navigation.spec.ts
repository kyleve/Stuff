import { test, expect } from '@playwright/test';

test('selection and panels preserve atlas nodes, then history restores states after reload', async ({ page }) => {
    await page.goto('./');
    const card = page.locator('.screen-card[data-screen-id="screen-1"]');
    const handle = await card.elementHandle();
    await card.getByLabel('State for Screen 1', { exact: true }).selectOption('alternate');
    await expect(page).toHaveURL(/state.screen-1=alternate/);
    await page.locator('#search-trigger').click();
    await page.keyboard.press('Escape');
    await page.getByLabel('Capture profile', { exact: true }).selectOption('phone-dark');
    await expect(page).toHaveURL(/profile=phone-dark/);
    expect(await handle!.evaluate(node => node.isConnected && node === document.querySelector('.screen-card[data-screen-id="screen-1"]'))).toBe(true);
    await page.reload();
    await expect(card.locator('select')).toHaveValue('alternate');
    await page.goBack();
    await expect(page.getByLabel('Capture profile', { exact: true })).toHaveValue('phone-light');
    await page.goBack();
    await expect(card.locator('select')).toHaveValue('default');
    await page.goForward();
    await expect(card.locator('select')).toHaveValue('alternate');
});

test('route playback opens the destination default and native capture arrows do not navigate', async ({ page }) => {
    await page.goto('./#screen=screen-1&variant=alternate&state.screen-2=alternate');
    const inspector = page.locator('.inspector');
    await expect(inspector).toBeVisible();
    const capture = inspector.getByRole('region', { name: 'Screen 1 scrollable capture' });
    await capture.focus();
    await page.keyboard.press('ArrowRight');
    await expect(inspector).toHaveAttribute('data-screen-id', 'screen-1');
    await inspector.getByRole('button', { name: 'Capture details', exact: true }).click();
    await inspector.getByRole('button', { name: 'Push · Details', exact: true }).click();
    await expect(inspector).toHaveAttribute('data-screen-id', 'screen-2');
    await expect(inspector.getByLabel('State for Screen 2', { exact: true })).toHaveValue('default');
    await page.goBack();
    await expect(inspector).toHaveAttribute('data-screen-id', 'screen-1');
    await expect(inspector.getByLabel('State for Screen 1', { exact: true })).toHaveValue('alternate');
});

test('fit all loads every visible capture and only requests local nested assets', async ({ page }) => {
    const requests: string[] = [];
    page.on('request', request => requests.push(request.url()));
    await page.goto('./');
    await expect(page.locator('.screen-card')).toHaveCount(24);
    await page.keyboard.press('f');
    await expect.poll(() => page.locator('.screen-card img').evaluateAll(images => images.filter(image => image instanceof HTMLImageElement && image.complete && image.naturalWidth > 0).length)).toBe(24);
    const origin = new URL(page.url()).origin;
    expect(requests.every(url => url.startsWith(origin + '/atlas/'))).toBe(true);
    await page.getByRole('button', { name: 'List', exact: true }).click();
    await expect(page.locator('.list-row')).toHaveCount(24);
    await page.getByRole('button', { name: 'Canvas', exact: true }).click();
    await expect.poll(() => page.locator('.screen-card img').evaluateAll(images => images.filter(image => image instanceof HTMLImageElement && image.complete && image.naturalWidth > 0).length)).toBe(24);
});
