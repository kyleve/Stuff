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
python3 -m unittest discover -s Tools/Tests -p 'test_flyover*.py'
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
The root `flyover` launcher delegates to `Tools/flyover_cli.py`.
`Tools/flyover_export.py` composes capture and validation. `Tools/flyover_publication.py` owns staging, rollback, and publication.
`Tools/flyover_artifact_access.py` supplies secure file access independently of the server.

`src/layouts/` and `src/pages/` own the document and loading state.
`src/scripts/load-atlas.ts` owns loading and visible errors.
`manifest.ts` defines the wire contract. Native export and Python publication validate the complete catalog.
`viewer.ts` owns one session, URL navigation, mounted views, overlays, and global event cleanup.
`catalog.ts` indexes the manifest and resolves selected captures. Controllers receive explicit, typed dependencies.
`atlas-view.ts`, `controls.ts`, `inspector.ts`, `panels.ts`, and `search.ts` own their presentation surfaces.
`canvas-controller.ts` owns zoom and scrolling. `image-controller.ts` owns thumbnail residency and scheduled loading.
`navigation.ts`, `geometry.ts`, `image-residency.ts`, and `capture-scroller.ts` contain separately tested interaction policies.
`inspector-position.ts` retains pending scroll restoration across overlapping image loads. Each viewer owns one controller and clears it on screen changes or dismissal.
The application retains cards during selection and overlay changes. Only view switches replace the active atlas view.
Group navigation updates the retained canvas and dock labels, including selections from Search and Filters.
State and profile changes update existing previews. Inspector selection changes replace only the overlay and preserve reading position.
The cleanup function returned by `startAtlas` removes global listeners, scheduled work, observers, and mounted DOM.
`src/styles/styles.css` declares the cascade order and imports the stylesheets.
`tokens.css` owns shared colors, dimensions, and theme values. `base.css` owns shared controls and document defaults.
Shell, canvas, list, panel, and inspector styles live in separate files. Each file includes its responsive overrides.
The `responsive` layer follows component styles, so device adaptations do not require stronger selectors.
`accessibility.css` owns cross-component motion and transparency preferences. Native modal behavior keeps background controls out of keyboard navigation.

The native manifest schema remains version 1. The exporter no longer writes `manifest.js`.
Regenerate earlier artifacts before using the new preview command.
PNG capture, thumbnail generation, and geometry remain native responsibilities.
New captures include optional `thumbnailVariants` alongside the existing largest thumbnail.
`thumbnail-selection.ts` selects the smallest sufficient image from the displayed preview size, fit mode, and device pixel density.
The controller assigns the selected source directly, so zooming out can replace a larger image.
Legacy captures retain their single-thumbnail or full-capture fallback.

New schema-1 exports include `profiles[].viewportSize` in points. The viewer uses these dimensions for device viewports.
Legacy exports without this field retain the original phone, landscape, and tablet sizes. Fixed screen viewports still take precedence.
`../Tests/Fixtures/manifest-v1.json` is shared by native serialization, Python validation, and TypeScript catalog tests.

Failed previews identify the error in their alternative text. Open the inspector for retry and reload actions.
Retry requests bypass the failed image URL cache. Reload preserves the selected screen and state through the URL.

## Browser regressions

Run `mise exec -- npm run lint` for Python, TypeScript, Astro, and CSS correctness checks.
`npm run test:lint` tests representative rule failures. CI runs both commands.
Browser tests also scan primary surfaces with axe and enforce thumbnail request and decoded-pixel budgets.
A separate 57-screen fixture uses production-scale geometry and thumbnails at 3× pixel density.
Its regression covers zoom increases, zoom decreases, profile changes, and inspector transitions.
Real two-touch injection runs in Chromium portrait; WebKit still runs layout, interaction, and accessibility tests.

Playwright loads the production Astro build with synthetic PNG captures under a nested HTTP path.
The suite covers Chromium and WebKit at desktop, portrait, and landscape widths.
It checks modal lifetime and focus, overlapping profile and history navigation, inspector position reset, control sizing, dark action contrast, and visible-image loading.
Group navigation tests cover Groups, Search, and Filters without replacing the canvas.
It also covers selectable text, reduced motion, all capture sizing classes, and unsupported schemas.
Mobile route targets use the shared 44-pixel minimum. Inspector focus changes must not scroll the outer dialog during drawer transitions.
Unit tests import production modules directly. They do not evaluate extracted source strings or emulate browser history.
These tests do not replace native capture tests.
