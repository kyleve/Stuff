# LogViewerUI – Module Shape

LogViewerUI is an app-agnostic SwiftUI **log viewer** over a [`LogKit`](../LogKit)
`LogStore`: hand it a buffer and a few display strings and it renders entries
newest-first with level/category/search filtering, share, copy, and clear. It
works for *any* `LogStore` because the host supplies everything app-specific via
`LogViewerConfiguration`. See [`README.md`](README.md) for the narrative and
usage.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns the
build system, formatting, and global conventions. Read that first.

## Scope & dependencies

- **SwiftUI + Observation + UIKit (pasteboard only) + LogKit.** It must **not**
  import WhereCore or any app code — it's generic UI the Where app (and any
  future app) adopts. App-specific wiring (which store, category display names)
  lives in the consumer, passed in via `LogViewerConfiguration`.
- Library target only ([`Package.swift`](../../Package.swift),
  `Shared/LogViewerUI/Sources`); the hosted test bundle `LogViewerUITests` is
  wired in [`Project.swift`](../../Project.swift) via the `unitTests` helper
  (host: `StuffTestHost`).
- **Intended for DEBUG / developer surfaces.** Consumers gate the entry point
  behind `#if DEBUG` (the Where app does — see `Settings/SettingsView.swift`).

## Public API (the whole surface)

Only two types are `public`; everything else is internal.

- [`LogViewerConfiguration`](Sources/LogViewerConfiguration.swift) – the value
  you build the viewer from: the `store`, a `title`, and a `@Sendable
  categoryDisplayName` mapping (defaults to identity). The mapping may run for
  every row, so keep it cheap and pure.
- [`LogViewer`](Sources/LogViewer.swift) – the root view. **Expects an ambient
  `NavigationStack`** (it sets a title/toolbar but doesn't create a stack); drop
  it into a navigation context the consumer owns.

## Internal types

- [`LogViewerModel`](Sources/LogViewerModel.swift) – the `@MainActor
  @Observable` model the view binds to. Mirrors the store into `entries`, derives
  cached `filteredEntries` and `categories`, owns the filter state (`searchText`,
  `minimumLevel`, `selectedCategory`), and renders `exportText`. Keep store work
  out of here beyond `snapshot()`/`clear()`/`observe()`.
- [`LogLevel+Display`](Sources/LogLevel+Display.swift) – `displayName` and a
  `tint` per level (escalating with severity). This is the only place levels get
  UI strings/colors.

## Invariants & behaviors to preserve

- **Read-only mirror, off-main capture.** Recording lives in `LogKit` (lock-
  guarded, any thread). This module only *consumes* snapshots on the main actor:
  `LogViewerModel.observe()` iterates `LogStore.changes()` and assigns `entries`.
  Don't record into the store from here (except `clear()`).
- **`observe()` starts in `init` and runs until the model is deallocated.**
  Observation is launched from `LogViewerModel.init` (not the view's `.task`) so
  there is no gap between the init snapshot and live updates. Cancelling the
  underlying task unregisters the observer in `LogStore`.
- **`clear()` updates `entries` synchronously** (`store.clear()` then
  `entries = store.snapshot()`) so the list empties immediately rather than
  waiting on the async stream — a unit test depends on this.
- **Newest-first for display, oldest-first for export.** `filteredEntries`
  reverses the (oldest-first) store snapshot; `exportText` reverses back so a
  shared/copied log reads chronologically. Share defers string formatting until
  the share sheet requests the payload (`Transferable`).
- **Distinct empty states.** `isEmpty` reflects the store buffer;
  `hasNoFilterMatches` is when filters exclude every entry.
- **The level filter is driven by `LogLevel.allCases`**, so adding a level in
  `LogKit` flows through automatically — don't hardcode the level list.

## Conventions

- Follow the root rules: exhaustive `switch` over enums (no bare `default:` — see
  `displayName`/`tint`), bind SwiftUI state directly to `@Observable` state (no
  closure `Binding(get:set:)`), small named structs over tuples.
- Developer-facing strings in this module are plain literals (it's a DEBUG tool);
  user-facing labels like the title come from the host via the configuration.
- Every previewable view ships a `#Preview` (see `LogViewer`), backed by an
  in-memory `LogStore` fixture.

## Testing

Swift Testing in [`Tests/`](Tests) (never XCTest), hosted in `StuffTestHost`.
Patterns: seed a `LogStore`, build a `LogViewerModel`, and assert on
`filteredEntries` across the level/category/search filters and on `exportText`
ordering; verify `clear()` empties `entries` synchronously; and host `LogViewer`
for both the populated and empty (`ContentUnavailableView`) states.
