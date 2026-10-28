import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'astro/config';

// The Python boundary validates input before Astro reads it. Type checks need no catalog.
const input = process.env.INSTALLER_SITE_DATA;
const site = input ? JSON.parse(readFileSync(input, 'utf8')) : undefined;
const cacheDirectory = process.env.INSTALLER_SITE_CACHE ?? './node_modules/.astro';

export default defineConfig({
  srcDir: fileURLToPath(new URL('./src/', import.meta.url)),
  output: 'static',
  site: site?.siteURL,
  base: site?.basePath ?? '/',
  trailingSlash: 'always',
  publicDir: process.env.INSTALLER_SITE_PUBLIC ?? './public',
  cacheDir: cacheDirectory,
  build: { format: 'directory' },
  vite: {
    // Each build owns its optimizer cache despite the shared node_modules symlink.
    cacheDir: join(cacheDirectory, 'vite'),
    build: { assetsInlineLimit: 0 },
    server: { fs: { allow: [fileURLToPath(new URL('.', import.meta.url))] } },
  },
});
