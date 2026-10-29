import { test, expect } from '@playwright/test';
import { fixture } from './fixture.ts';

test('modal focus excludes background controls and Escape restores the trigger', async ({ page }) => {
    await page.goto('./');
    const trigger = page.locator('#search-trigger');
    await trigger.click();
    const dialog = page.getByRole('dialog', { name: 'Search the atlas' });
    await expect(dialog).toHaveAttribute('open');
    expect(await dialog.evaluate(node => node.matches(':modal'))).toBe(true);
    expect(await trigger.evaluate(node => { node.focus(); return node === document.activeElement; })).toBe(false);
    for (let index = 0; index < 14; index++) {
        await page.keyboard.press(index % 3 === 0 ? 'Shift+Tab' : 'Tab');
        // Native dialogs permit focus to leave for browser chrome, represented by body.
        expect(await dialog.evaluate(node => document.activeElement === document.body || node.contains(document.activeElement))).toBe(true);
    }
    await page.keyboard.press('Escape');
    await expect(trigger).toBeFocused();
    expect(await trigger.evaluate(node => getComputedStyle(node).outlineStyle)).not.toBe('none');
});

test('mobile details make covered capture controls inert and keep route targets usable', async ({ page }) => {
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('./#screen=screen-1&variant=default');
    await page.getByRole('button', { name: 'Capture details', exact: true }).click();
    await expect.poll(() => page.locator('.inspector').evaluate(node => node.scrollTop)).toBe(0);
    expect((await page.locator('.details-close').boundingBox())!.y).toBeGreaterThanOrEqual(0);
    await expect.poll(async () => {
        const frame = (await page.locator('.details-close').boundingBox())!;
        return frame.y + frame.height;
    }).toBeLessThanOrEqual(844);
    for (const selector of ['.inspection-canvas', '.inspector-dock']) {
        expect(await page.locator(selector).evaluate(node => (node as HTMLElement).inert)).toBe(true);
    }
    const route = page.getByRole('button', { name: 'Push · Details', exact: true });
    expect((await route.boundingBox())!.height).toBeGreaterThanOrEqual(44);
    await page.keyboard.press('Escape');
    await expect(page.locator('.inspector')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Capture details', exact: true })).toBeFocused();
    expect(await page.locator('.inspection-canvas').evaluate(node => (node as HTMLElement).inert)).toBe(false);
    await page.keyboard.press('Escape');
    await expect(page.locator('.inspector')).toHaveCount(0);
});

test('chrome suppresses selection while titles, metadata, and search remain selectable', async ({ page }) => {
    await page.goto('./');
    const selection = (selector: string) => page.locator(selector).first().evaluate(node => getComputedStyle(node).userSelect);
    expect(await selection('#app')).toBe('none');
    expect(await page.locator('.screen-card img').first().evaluate(node => (node as HTMLImageElement).draggable)).toBe(false);
    await page.locator('#search-trigger').click();
    expect(await selection('#command-search')).toBe('text');
    await page.keyboard.press('Escape');
    await page.goto('./#screen=screen-1&variant=default');
    await expect(page.locator('.inspector')).toBeVisible();
    expect(await selection('.inspector')).toBe('none');
    expect(await selection('#inspector-title')).toBe('text');
    await page.getByRole('button', { name: 'Capture details', exact: true }).click();
    expect(await selection('.metadata-row dd')).toBe('text');
});

test('reduced motion and narrow viewports retain usable controls without page overflow', async ({ page }) => {
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.setViewportSize({ width: 320, height: 640 });
    await page.goto('./');
    await page.locator('#filter-trigger').click();
    const surface = page.locator('.sheet-surface');
    expect(await surface.evaluate(node => parseFloat(getComputedStyle(node).animationDuration))).toBeLessThanOrEqual(0.001);
    await page.getByRole('combobox', { name: 'Group', exact: true }).selectOption('second');
    await page.getByRole('button', { name: 'Show results', exact: true }).click();
    await expect(page.locator('#result-count')).toHaveText('12 / 24');
    await page.locator('#filter-trigger').click();
    await page.getByRole('button', { name: 'Reset filters', exact: true }).click();
    await expect(page.locator('#result-count')).toHaveText('24 / 24');
    expect(await page.evaluate(() => document.body.scrollWidth)).toBe(320);
});

test('all capture extents transfer keyboard focus to the active scroll container', async ({ page }) => {
    // Scale controls intentionally collapse below 440px; test both controls at an exposed width.
    await page.setViewportSize({ width: 800, height: 700 });
    for (const extent of ['viewport', 'intrinsic', 'fullContent', 'fullContent2D'] as const) {
        await page.route('**/manifest.json', route => {
            const manifest = fixture();
            manifest.screens[0].variants[0].captureExtent = extent;
            manifest.images[0].captureExtent = extent;
            return route.fulfill({ json: manifest });
        });
        await page.goto('./?extent=' + extent + '#screen=screen-1&variant=default');
        await page.getByRole('button', { name: '100%', exact: true }).click();
        const frame = page.locator('.inspector-image');
        await expect(frame).toHaveAttribute('tabindex', '0');
        await frame.focus();
        await page.keyboard.press('ArrowRight');
        await expect(page.locator('.inspector')).toHaveAttribute('data-screen-id', 'screen-1');
        // Programmatic activation retains the scroller's focus, like an assistive control.
        await page.getByRole('button', { name: 'Fit', exact: true }).evaluate(node => (node as HTMLButtonElement).click());
        await expect(frame).not.toHaveAttribute('tabindex');
        if (extent.startsWith('fullContent')) await expect(page.locator('.inspector-device')).toBeFocused();
        else await expect(page.locator('.inspector-device')).not.toHaveAttribute('tabindex');
        await page.unroute('**/manifest.json');
    }
});

test('an unsupported manifest shows a readable error instead of an empty atlas', async ({ page }) => {
    await page.route('**/manifest.json', route => route.fulfill({ json: { schemaVersion: 2 } }));
    await page.goto('./');
    await expect(page.getByRole('alert')).toContainText('manifest schema version 1');
    await expect(page.locator('.screen-card')).toHaveCount(0);
});
