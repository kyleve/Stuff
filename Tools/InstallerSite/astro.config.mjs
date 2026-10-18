import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'astro/config';

// The Python boundary validates input before Astro reads it. Type checks need no catalog.
const input = process.env.INSTALLER_SITE_DATA;
const site = input ? JSON.parse(readFileSync(input, 'utf8')) : undefined;

export default defineConfig({
  srcDir: fileURLToPath(new URL('./src/', import.meta.url)),
  output: 'static',
  site: site?.siteURL,
  base: site?.basePath ?? '/',
  trailingSlash: 'always',
  publicDir: process.env.INSTALLER_SITE_PUBLIC ?? './public',
  cacheDir: process.env.INSTALLER_SITE_CACHE ?? './node_modules/.astro',
  build: { format: 'directory' },
  vite: {
    build: { assetsInlineLimit: 0 },
    server: { fs: { allow: [fileURLToPath(new URL('.', import.meta.url))] } },
  },
});
