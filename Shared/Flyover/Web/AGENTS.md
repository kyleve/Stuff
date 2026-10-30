# Flyover web presentation

Read the [project guide](README.md), [Flyover rules](../AGENTS.md), and [repository rules](../../../AGENTS.md).

- Use the shared root npm workspace. Do not add a second lockfile or an InstallerKit dependency.
- Keep capture policy, catalog validation, layout geometry, and publication outside browser presentation.
- Load local JSON over HTTP. Keep all emitted asset references relative for subdirectory hosting.
- Keep images unchanged. Astro must not optimize or resize native captures.
- Preserve visible-image residency, URL restoration, keyboard scrolling, and modal focus behavior during module extraction.
- Select thumbnail sizes in both zoom directions. Use layout dimensions and requested zoom before paint. Budget the selected pixels.
- Type-check every client module and TypeScript test. Use explicit component dependencies and one application-owned session.
- Retain atlas nodes during selection and overlay changes. Replace the active view only when its mode changes. Synchronize retained group labels after explicit navigation and viewport changes.
- Test module exports directly. Use browser tests for DOM, history, layout, and accessibility behavior; do not extract source strings.
- Cancel render-owned frames before replacing their DOM. Preserve pending inspector scroll position across same-screen selections until the replacement image loads. Clear it when inspection ends or changes screen.
- Verify control dimensions and foreground/background contrast in browser tests, not only CSS source assertions.
- Keep component styles and their media rules together. Use the declared cascade layers; do not raise specificity to defeat responsive rules.
- Keep shared colors and control dimensions in `tokens.css`. Keep cross-component accessibility preferences in `accessibility.css`.
- Move focus into animated overlays without scrolling their offscreen transform position into view.
- Run the type check, web command regressions, and retained Flyover tool tests after changes.
  Exercise the production build in a browser at desktop and mobile widths.
