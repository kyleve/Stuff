# WhereWidgets – Module Shape

The **Where** widget extension: WidgetKit configurations that read published
data and presentation files from the App Group and render via shared views in **WhereUI**.
See [`README.md`](README.md) for the data path and widget list.

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md). Read those first.

## Scope & dependencies

- **Tuist app-extension target** ([`Project.swift`](../../Project.swift),
  bundle ID `com.stuff.where.widgets`), depending on **WhereCore**,
  **WhereUI**, **RegionKit**, and **PeriscopeCore**.
- Must **not** import SwiftData, open the user's store, or duplicate
  aggregation logic — the app publishes; the extension only reads and renders.
- Logs via the `WhereLog` facade (typed `WhereWidgetsLog` events); as a
  separate WidgetKit process its `Periscope.shared` is OSLog-only (no store).
- No test bundle; behavior is covered from **WhereCore** and **WhereUI**.

## Refresh contract

1. App commits a store change → `WidgetSnapshotPublisher` rebuilds the
   snapshot → writes JSON + `WidgetCenter.reloadAllTimelines()`.
2. A device-theme change → `WidgetPresentationPublisher` writes the separate
   presentation JSON + reloads timelines without rebuilding data.
3. The provider reads both files on each timeline request and schedules
   `.after(nextMidnight)` so WidgetKit re-queries even without an app reload.

## Invariants

- **Read-only App Group access** — only the app writes `widget-snapshot.json` and
  `widget-presentation.json`.
- **No stale-day invalidation in the provider.** A snapshot whose `day` rolled
  past today is still shown until the app republishes — intentional.
- In-widget strings come from WhereUI (shared views + `WhereFormat`); the
  gallery name/description resolve through this extension's own generated
  catalog symbols (`String(localized: .widgetGalleryTodayName)`).
- **Seed the Broadway root via WhereUI's `whereBroadwayRoot()`** with the
  separately published theme and the snapshot's region styles (applied in each
  widget's `StaticConfiguration` content) so the shared WhereUI views resolve
  trait-aware `@Environment(\.stylesheet)` tokens instead of `.default`. Never
  add a direct `BroadwayCore`/`BroadwayUI` dependency — Broadway arrives through
  `WhereUI`, which is why the seam lives there rather than a `broadwayRoot` call
  here (see the root
  [`AGENTS.md`](../../AGENTS.md#never-double-link-a-product-whereui-already-carries)).
