import { defineConfig } from 'astro/config';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const cache = process.env.FLYOVER_SITE_CACHE ?? './node_modules/.astro';

export default defineConfig({
    srcDir: fileURLToPath(new URL('./src/', import.meta.url)),
    output: 'static',
    publicDir: process.env.FLYOVER_SITE_PUBLIC ?? './public',
    cacheDir: cache,
    build: { assets: 'assets', assetsPrefix: '.', inlineStylesheets: 'never' },
    vite: {
        cacheDir: join(cache, 'vite'),
        server: { fs: { allow: [fileURLToPath(new URL('.', import.meta.url))] } },
        build: { assetsInlineLimit: 0 },
    },
});
