# PeriscopeTools – Module Shape

PeriscopeTools is the on-device log exploration tooling for [`PeriscopeCore`](../PeriscopeCore). It provides the latest-logs viewer, the tracer, the debug toast, and the log view mode modifier. See [`README.md`](README.md) for the narrative and API.

Read the root [`AGENTS.md`](../../../AGENTS.md) first. That file owns the build system, formatting, and global conventions.

## Scope & dependencies

- **Use SwiftUI, SFSafeSymbols, PeriscopeCore, PeriscopeUI, and BroadwayCore/BroadwayUI.** Do not import app code. App-specific wiring (which store, which alert handler) comes in through configuration.
- **Target DEBUG and developer surfaces.** Consumers gate entry points behind `#if DEBUG`. Developer-facing strings are plain literals here.
- **`Sources/` groups one directory per tool, plus `Components/` for shared display pieces and `Styling/` for the design system.** Tests stay flat, 1:1 with their source files.

## Design system — `PeriscopeStylesheet`

Follow the repo [`building-ui`](../../../.agents/skills/building-ui/SKILL.md) skill for Broadway token ownership, variants, trait derivation, layout, accessibility, previews, and rendering coverage. This module's sheet is [`PeriscopeStylesheet`](Sources/Styling/PeriscopeStylesheet.swift), read through `@Environment(\.stylesheet)` and defaulted to `PeriscopeStylesheet.default` off the view tree.

- **Seed each public tool view with its own root** through `periscopeBroadwayRoot()`. Then tooling styles correctly with or without a host Broadway root.
- **Resolve row density** (`comfortable` / `compact`) as a `RowStyle` axis through `stylesheet.row[density]`, riding the `\.logRowDensity` environment value.
- **The viewer seeds density from a `UserDefaults`-persisted preference** (`Density.load`/`save`, defaulting `compact`).
- **Keep color decisions in `Palette`, not on `LogLevel` / `SpanExit.Mode`.** `tint(forLevel:)` bands by severity so custom levels inherit a color.
- **PeriscopeTools seeds Broadway directly.** A consumer must not re-list `BroadwayCore`/`BroadwayUI` beside a product that already carries them.
- **See the root [double-linking rule](../../../AGENTS.md#never-double-link-a-product-whereui-already-carries).**

## Invariants

- **Stay read-only over the store.** Tooling queries `PeriscopeCore`'s store and live buffer. It never records events of its own (except through the normal logging API).
- **Report tool failures to OSLog, not to Periscope.** `PeriscopeToolsLog.failures` is the channel for a store read that threw or a stored payload that would not decode.
- **Logging those through Periscope would commit a change these surfaces then reload for.** One corrupt row becomes a refresh loop.
- **Every `catch` still logs.** A `.failed` state alone is not enough.
- **Never let a reading claim more than the row can say.**
- **Values from different sources must be one state.** Example: an exit mode from an indexed column and a duration from a payload.
- **Otherwise a decode failure renders contradictions.** `SpanNode.Outcome` exists because an ended span used to show an exit chip beside a "running" duration.
- **Label a name recovered from a row's message as recovered.** Do not pass it off as the recorded one.
- **The toast is hookable.** Apps override the default handler.
- **Handlers must not log at or above the alerter threshold.** They would alert themselves in a loop.
- **`Periscope.isInspectModeEnabled` is the inspect flag's source of truth.** `PeriscopeInspector` is its observable mirror, synced both ways through `inspectModeChanges()`.
- **Sort merged multi-query results by `(date, sequence)`.** The store's insertion sequence is the tiebreak that keeps same-millisecond events stable.
- **Refresh live tree/hierarchy models incrementally.**
- **`LogHierarchyModel` and `SpanTreeModel` accumulate derived state.** They fetch only past their highest merged `sequence` (`LogQuery.afterSequence`).
- **Never do a full-store re-read.** The merge re-filters on `sequence` so restarts stay idempotent.
- **This trades exact reflection of deletions for a bounded per-commit fetch.** Retention prune / clear are neither wired into the live app.
- **The in-memory rebuild is still O(accumulated) — see [`TODOs.md`](../TODOs.md).** A store swap makes the hosting view build a fresh model.
- **Rebind tool views on in-place input swaps.** Each view's `.task(id:)` is keyed on store identity plus its other inputs.
- **A new identity-relevant input must join the key.** Otherwise the view silently keeps serving the old inputs.
- **Name the builds a timing reading pools.** `SpanHistoryScope` filters the accumulated ends (never a refetch).
- **`SpanHistoryView` labels the active scope.**
- **Percentiles mixing an `-Onone` build with an `-O` one measure nothing.**
- **An unlabelled reading cannot be told apart from a narrowed one.**
- **Do not offer a scope the sessions cannot resolve.** If a selection stops resolving, fall back to `.all`.

## Testing

Swift Testing lives in [`Tests/`](Tests), hosted in `StuffTestHost` (`PeriscopeToolsTests`). Seed an in-memory store. Drive the view models directly. Host views with `TestHostSupport`'s `show()` helpers.
