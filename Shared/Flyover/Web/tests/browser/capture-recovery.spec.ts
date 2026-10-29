import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

for (const failure of ['404', 'interrupted'] as const) {
    test(`capture recovery after ${failure} retains selection`, async ({ page }) => {
        let requests = 0;
        await page.route('**/images/0/default/phone-light.png*', route => {
            if (++requests > 1) return route.continue();
            return failure === '404' ? route.fulfill({ status: 404 }) : route.abort('failed');
        });
        await page.goto('./#screen=screen-1&variant=default&profile=phone-light');
        const error = page.locator('.capture-error');
        await expect(error).toBeVisible();
        await expect(error.getByRole('status')).toContainText('Screen 1');
        await error.getByRole('button', { name: 'Retry capture' }).click();
        await expect(error).toBeHidden();
        await expect(page.locator('.inspector')).toHaveAttribute('data-screen-id', 'screen-1');
        expect(await page.locator('.inspector img').evaluate(image => (image as HTMLImageElement).naturalWidth)).toBeGreaterThan(0);
        expect(requests).toBe(2);
    });
}

test('failed preview directs reviewers to recovery and reload retains the deep link', async ({ page }, testInfo) => {
    await page.route('**/images/**', route => route.fulfill({ status: 404 }));
    await page.goto('./');
    const image = page.locator('.screen-card img').first();
    await expect(image).toHaveAttribute('data-load-error', 'true');
    await expect(image).toHaveAttribute('alt', /Preview unavailable/);
    await page.locator('.card-image-button').first().click();
    const panel = page.locator('.capture-error');
    await expect(panel).toBeVisible();
    await panel.getByRole('button', { name: 'Retry capture' }).click();
    await expect(panel.getByRole('button', { name: 'Retry capture' })).toBeEnabled();
    const result = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
    expect(result.violations).toEqual([]);
    await expect(panel).toBeInViewport({ ratio: 1 });
    await page.screenshot({ path: testInfo.outputPath('capture-recovery.png') });
    const url = page.url();
    await page.unroute('**/images/**');
    await panel.getByRole('button', { name: 'Reload atlas' }).click();
    await expect(page.locator('.inspector img')).toBeVisible();
    await expect(page.locator('.capture-error')).toBeHidden();
    await expect(page).toHaveURL(url);
});
