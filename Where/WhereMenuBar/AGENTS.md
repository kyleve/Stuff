# WhereMenuBar – Module Shape

WhereMenuBar is the native macOS, icon-only menu bar helper for Where. See
[`README.md`](README.md). This file complements the root
[`AGENTS.md`](../../AGENTS.md), feature [`Where/AGENTS.md`](../AGENTS.md), and
the shared contract [`WhereSurface/AGENTS.md`](../WhereSurface/AGENTS.md).

## Scope & dependencies

- Depend on WhereSurface plus system AppKit/SwiftUI only; never import
  WhereCore, RegionKit, SwiftData, CloudKit, WidgetKit, or location frameworks.
- Read the App Group artifact only. The helper never writes shared data or
  launches the host automatically.
- Keep login-item registration in the Catalyst app; the helper only renders
  and handles its explicit Open Where action.

## Invariants

- Keep the status item icon-only and give its button an accessibility label.
- Preserve the last good snapshot when refresh or decode fails, showing its
  original relative age and a failure note.
- Pair Darwin observer registration with removal; treat delivery as advisory.
- Keep user-facing copy in this target's generated string catalog.

## Testing

Wire-format, file-read, and compatibility behavior lives in
[`WhereSurface/Tests`](../WhereSurface/Tests); payload construction and ranking
live in WhereCore tests. Keep this target a thin native host.
