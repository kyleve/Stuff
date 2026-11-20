import { fileURLToPath } from 'node:url';
import { defineConfig } from 'astro/config';

const projectDirectory = fileURLToPath(new URL('.', import.meta.url));

export default defineConfig({
  output: 'static',
  devToolbar: { enabled: false },
  vite: {
    cacheDir: fileURLToPath(new URL('./.astro/vite/', import.meta.url)),
    server: {
      strictPort: true,
      fs: { allow: [projectDirectory] },
    },
  },
});
