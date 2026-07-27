# PeriscopeTools – Module Shape

PeriscopeTools is the on-device log exploration tooling for
[`PeriscopeCore`](../PeriscopeCore): the latest-logs viewer, the tracer, the
debug toast, and the log view mode modifier. See [`README.md`](README.md) for
the narrative and API.

This file complements the root [`AGENTS.md`](../../../AGENTS.md), which owns
the build system, formatting, and global conventions. Read that first.

## Scope & dependencies

- **SwiftUI + PeriscopeCore + PeriscopeUI + BroadwayCore/BroadwayUI.** No app
  code — app-specific wiring (which store, which alert handler) comes in via
  configuration.
- **Intended for DEBUG / developer surfaces**; consumers gate entry points
  behind `#if DEBUG`. Developer-facing strings are plain literals here.
- `Sources/` groups one directory per tool, plus `Components/` for shared
  display pieces and `Styling/` for the design system. Tests stay flat, 1:1
  with their source files.

## Design system — `PeriscopeStylesheet`

Appearance tokens live in `PeriscopeStylesheet`
([`Sources/Styling/PeriscopeStylesheet.swift`](Sources/Styling/PeriscopeStylesheet.swift)),
a Broadway `BStylesheet` — never inline in views. Read with
`@Environment(\.stylesheet)`; off the `View` tree use
`PeriscopeStylesheet.default`.

- **Each public tool view seeds its own root** with `periscopeBroadwayRoot()`,
  so tooling styles correctly with or without a host Broadway root.
- **Row density** (`comfortable` / `compact`) is a `RowStyle` axis resolved
  via `stylesheet.row[density]`, riding the `\.logRowDensity` environment
  value; the viewer seeds it from a `UserDefaults`-persisted preference
  (`Density.load`/`save`, defaulting `compact`).
- **Color decisions live in `Palette`**, not on `LogLevel` / `SpanExit.Mode`
  — `tint(forLevel:)` bands by severity so custom levels inherit a color.
- PeriscopeTools seeds Broadway directly; a consumer must not re-list
  `BroadwayCore`/`BroadwayUI` beside a product that already carries them —
  the root
  [double-linking rule](../../../AGENTS.md#never-double-link-a-product-whereui-already-carries).

## Invariants

- **Read-only over the store.** Tooling queries `PeriscopeCore`'s store and
  live buffer; it never records events of its own (except through the normal
  logging API).
- **The toast is hookable** — apps override the default handler. Handlers
  must not log at or above the alerter threshold (they'd alert themselves in
  a loop).
- **`Periscope.isInspectModeEnabled` is the inspect flag's source of truth**
  — `PeriscopeInspector` is its observable mirror, synced both ways via
  `inspectModeChanges()`.
- **Merged multi-query results sort by `(date, sequence)`** — the store's
  insertion sequence is the tiebreak that keeps same-millisecond events
  stable.
- **Live tree/hierarchy models refresh incrementally.** `LogHierarchyModel`
  and `SpanTreeModel` accumulate derived state and fetch only past their
  highest merged `sequence` (`LogQuery.afterSequence`) — never a full-store
  re-read; the merge re-filters on `sequence` so restarts stay idempotent.
  This trades exact reflection of deletions (retention prune / clear, neither
  wired into the live app) for a bounded per-commit fetch; the in-memory
  rebuild is still O(accumulated) — see [`TODOs.md`](../TODOs.md). A store
  swap makes the hosting view build a fresh model.
- **Tool views rebind on in-place input swaps** — each view's `.task(id:)` is
  keyed on store identity plus its other inputs; a new identity-relevant
  input must join the key, or the view silently keeps serving the old inputs.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PeriscopeToolsTests`). Seed an in-memory store, drive the view models
directly, and host views with `TestHostSupport`'s `show()` helpers.
