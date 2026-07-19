# PeriscopeTools – Module Shape

PeriscopeTools is the on-device log exploration tooling for
[`PeriscopeCore`](../PeriscopeCore): the latest-logs viewer, the tracer, the
debug toast, and the log view mode modifier. See [`README.md`](README.md) for
the narrative and API.

This file complements the root [`AGENTS.md`](../../../AGENTS.md), which owns
the build system, formatting, and global conventions. Read that first.

## Layout

`Sources/` groups one directory per tool — `Viewer/`, `Tracer/`, `Alerts/`,
`InspectMode/`, `Spans/` (`OpenSpansView` for live spans, `SpanTreeView` for
the durable store's span tree), `Hierarchy/` (the scope-tree browser) — plus
`Components/` for the display pieces they share (event rows, the shared
`LogEventList`, detail view, level/exit display extensions) and `Styling/` for
the design system (`PeriscopeStylesheet`). Tests stay flat, named 1:1 with
their source files.

## Scope & dependencies

- **SwiftUI + PeriscopeCore + PeriscopeUI + BroadwayCore/BroadwayUI.** No app
  code — app-specific wiring (which store, which alert handler) comes in via
  configuration.
- **Intended for DEBUG / developer surfaces**; consumers gate entry points
  behind `#if DEBUG`. Developer-facing strings are plain literals here.

## Design system — `PeriscopeStylesheet`

Appearance tokens (row geometry, badge chrome, typography, and the
severity/exit/inspect color palette) live in `PeriscopeStylesheet`
([`Sources/Styling/PeriscopeStylesheet.swift`](Sources/Styling/PeriscopeStylesheet.swift)),
a Broadway `BStylesheet` — not inline in views. Read tokens with
`@Environment(\.stylesheet) private var stylesheet`; off the `View` tree (tests)
use `PeriscopeStylesheet.default`.

- **Each public tool view seeds its own root** with `periscopeBroadwayRoot()`
  so the tooling styles correctly whether or not the host app has a Broadway
  root; nesting under an app root simply re-seeds from the same system traits.
- **Row density** (`comfortable` / `compact`) is a `RowStyle` axis resolved via
  `stylesheet.row[density]`; the active density rides the `\.logRowDensity`
  environment value. The viewer (and inspector sheet) seed it from a
  `UserDefaults`-persisted preference (`Density.load`/`save`), which defaults to
  `compact` — the roomier `comfortable` is only the raw environment fallback for
  rootless contexts (previews, isolated rows). The viewer's filter menu carries
  the picker and writes the choice back on change.
- **Color decisions live in `Palette`**, not on `LogLevel` / `SpanExit.Mode` —
  `tint(forLevel:)` bands by severity so custom levels inherit a sensible color.
- Because PeriscopeTools links Broadway as a **static** library it can seed
  Broadway directly. If it ever becomes a dynamic framework or is embedded in
  one (e.g. hosted inside WhereUI), follow WhereUI's rule: consumers must not
  re-link BroadwayCore/BroadwayUI, or the type-keyed environment splits and the
  stylesheet stops resolving across the boundary.

## Invariants

- **Read-only over the store.** Tooling queries `PeriscopeCore`'s store and
  live buffer; it never records events of its own (except through the normal
  logging API).
- **The toast is hookable** — apps override the default handler rather than
  this module special-casing any app. Handlers must not log at or above the
  alerter threshold (they'd alert themselves in a loop).
- **`Periscope.isInspectModeEnabled` is the inspect flag's source of
  truth** — `PeriscopeInspector` is its observable SwiftUI mirror, synced
  both ways: the inspector writes through, and direct system writes flow
  back via `inspectModeChanges()`. Either side may write; they converge.
- **Merged multi-query results sort by `(date, sequence)`** — the tracer and
  inspector combine several store queries, and the store's insertion
  sequence is the tiebreak that keeps same-millisecond events stable.
- **Live tree/hierarchy models refresh incrementally.** `LogHierarchyModel`
  and `SpanTreeModel` accumulate their derived state (per-scope counts; the
  begin/end pairs) and, on each `changes()` ping, fetch only events past the
  highest `sequence` they've merged via `LogQuery.afterSequence` — never a
  full-store re-read. The merge re-filters on `sequence` so it stays
  idempotent if `run()` restarts over already-seen events. This bounds the
  per-commit *fetch* by what the commit added (the in-memory forest/tree
  rebuild is still O(accumulated); see TODOs) and trades exact reflection of
  deletions (retention prune / clear, neither wired into the live app) for
  it; a store swap makes the hosting view build a fresh model, resetting the
  watermark.
- **Tool views rebind on in-place input swaps** — each view's `.task(id:)`
  is keyed on store identity plus its other inputs and rebuilds the model
  when they change; a new identity-relevant input must join the key, or
  the view silently keeps serving the old inputs.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PeriscopeToolsTests`). Seed an in-memory store, drive the view models
directly, and host views with `TestHostSupport`'s `show()` helpers.
