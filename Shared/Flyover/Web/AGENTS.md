# Flyover web presentation

Read the [project guide](README.md), [Flyover rules](../AGENTS.md), and [repository rules](../../../AGENTS.md).

- Use the shared root npm workspace. Do not add a second lockfile or an InstallerKit dependency.
- Keep capture policy, catalog validation, layout geometry, and publication outside browser presentation.
- Load local JSON over HTTP. Keep all emitted asset references relative for subdirectory hosting.
- Keep images unchanged. Astro must not optimize or resize native captures.
- Preserve visible-image residency, URL restoration, keyboard scrolling, and modal focus behavior during module extraction.
- Cancel render-owned frames before replacing their DOM. Preserve inspector scroll position when the same screen changes profile.
- Verify control dimensions and foreground/background contrast in browser tests, not only CSS source assertions.
- Run the type check, web command regressions, and retained Flyover tool tests after changes.
  Exercise the production build in a browser at desktop and mobile widths.
