# Flyover website

Astro builds a static viewer for native Flyover captures. The browser loads `manifest.json` from the same HTTP directory.
The site has no backend, remote assets, analytics, or native control execution.

## Commands

From the repository root:

```sh
mise exec -- npm ci
./flyover export
./flyover preview --lan
./flyover dev
mise exec -- npm run check
bash Shared/Flyover/Tools/Tests/flyover_test.sh
python3 -m unittest Tools.Tests.test_flyover_site Tools.Tests.test_flyover_manifest Tools.Tests.test_flyover_preview
mise exec -- npx playwright install chromium webkit
mise exec -- npm run test:browser --workspace stuff-flyover-site
```

The preview command serves the existing generated viewer. The dev command uses current source with the existing captures.
Each server owns a temporary copy. Restart the server after a new export.
Both commands accept `--output`, `--port`, and `--lan`. The default bind address is loopback.

Upload the generated directory to any static HTTP host. Subdirectory hosting works without a rebuild.
Direct `file://` viewing is unsupported. Viewers need no Node installation.

## Ownership

The root npm workspace supplies the locked Astro, TypeScript, and Node type dependencies for both repository websites.
`Tools/astro_site.py` resolves the pinned Node runtime and isolates generated Astro state.
`Tools/flyover_site.py` builds the shell and starts Astro dev or preview.
`Tools/flyover_manifest.py` validates captures and the generated `web-assets.json` inventory.
The root `flyover` command owns capture orchestration, staging, rollback, and publication.

`src/layouts/` and `src/pages/` own the document and loading state.
`src/scripts/load-atlas.ts` owns loading and visible errors.
`navigation.ts`, `image-residency.ts`, and `capture-scroller.ts` own typed interaction policies.
`viewer.js` retains the existing DOM presentation and session orchestration. It is not a second rendering framework.
`src/styles/styles.css` retains the viewer's responsive styles.

The native manifest schema remains version 1. The exporter no longer writes `manifest.js`.
Regenerate earlier artifacts before using the new preview command.
PNG capture, thumbnail generation, and geometry remain native responsibilities.

## Browser regressions

Playwright loads the production Astro build with synthetic PNG captures under a nested HTTP path.
The suite covers Chromium and WebKit at desktop, portrait, and landscape widths.
It checks modal frame cancellation, profile scroll restoration, select sizing, and dark action contrast.
These tests do not replace native capture tests.
