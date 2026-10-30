import { defineConfig } from '@playwright/test';

export default defineConfig({
    testDir: './tests/browser',
    workers: 2,
    retries: 0,
    use: { baseURL: 'http://127.0.0.1:4329/atlas/', trace: 'retain-on-failure' },
    webServer: {
        command: 'node tests/browser/server.mjs',
        url: 'http://127.0.0.1:4329/atlas/',
        reuseExistingServer: false,
    },
    projects: ['chromium', 'webkit'].flatMap(browserName => [
        { name: `${browserName}-desktop`, use: { browserName: browserName as 'chromium' | 'webkit', viewport: { width: 1280, height: 900 } } },
        { name: `${browserName}-portrait`, use: { browserName: browserName as 'chromium' | 'webkit', viewport: { width: 390, height: 844 }, hasTouch: true } },
        { name: `${browserName}-landscape`, use: { browserName: browserName as 'chromium' | 'webkit', viewport: { width: 844, height: 390 }, hasTouch: true } },
    ]),
});
