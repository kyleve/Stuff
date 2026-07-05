# LogViewerUI – Module Shape

LogViewerUI is an app-agnostic SwiftUI **log viewer** over a
[`LogKit`](../LogKit) `LogStore`: hand it a `LogViewerConfiguration` (store,
title, category display names) and `LogViewer` renders entries newest-first
with filtering, share, copy, and clear. See [`README.md`](README.md) for the
narrative and API.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns the
build system, formatting, and global conventions. Read that first.

## Scope & dependencies

- **SwiftUI + Observation + UIKit (pasteboard only) + LogKit.** It must
  **not** import WhereCore or any app code — app-specific wiring comes in via
  `LogViewerConfiguration`.
- **Intended for DEBUG / developer surfaces**; consumers gate the entry point
  behind `#if DEBUG`. Developer-facing strings are plain literals here.
- `LogViewer` expects an ambient `NavigationStack` the consumer owns.

## Invariants

- **Read-only mirror.** Recording lives in `LogKit`; this module only
  consumes snapshots on the main actor (the one write is `clear()`, which
  updates `entries` synchronously so the list empties immediately).
- **Newest-first for display, oldest-first for export** — a shared/copied log
  reads chronologically.
- **The level filter is driven by `LogLevel.allCases`**, so a new level in
  LogKit flows through automatically — don't hardcode the level list.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`: seed a
`LogStore`, drive `LogViewerModel`, assert on filtering/export; host
`LogViewer` for populated and empty states.
