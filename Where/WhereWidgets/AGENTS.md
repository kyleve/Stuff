# WhereWidgets – Module Shape

The **Where** widget extension is a WidgetKit target. It reads a published
`WidgetSnapshot` from the App Group and renders via shared views in **WhereUI**.
See [`README.md`](README.md) for the data path and widget list.

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md). Read those first.

## Scope & dependencies

- **Tuist app-extension target** ([`Project.swift`](../../Project.swift),
  bundle ID `com.stuff.where.widgets`), depending on **WhereCore**,
  **WhereUI**, **RegionKit**, and **PeriscopeCore**.
- Must **not** import SwiftData, open the user's store, or duplicate
  aggregation logic. The app publishes. The extension only reads and renders.
- Logs via the `WhereLog` facade (typed `WhereWidgetsLog` events). As a
  separate WidgetKit process its `Periscope.shared` is OSLog-only (no store).
- No test bundle. Behavior is covered from **WhereCore** and **WhereUI**.

## Refresh contract

1. App commits a store change. Then `WidgetSnapshotPublisher` rebuilds the
   snapshot. It writes JSON and calls `WidgetCenter.reloadAllTimelines()`.
2. The provider reads the JSON on each timeline request. It schedules
   `.after(nextMidnight)` so WidgetKit re-queries even without an app reload.

## Invariants

- **Read-only App Group access.** Only the app writes `widget-snapshot.json`.
- **No stale-day invalidation in the provider.** A snapshot whose `day` rolled
  past today is still shown until the app republishes. That is intentional.
- In-widget strings come from WhereUI (shared views + `WhereFormat`). The
  gallery name/description resolve through this extension's own generated
  catalog symbols (`String(localized: .widgetGalleryTodayName)`).
- **Seed the Broadway root via WhereUI's `whereBroadwayRoot()`** (applied in each
  widget's `StaticConfiguration` content). Then the shared WhereUI views resolve
  trait-aware `@Environment(\.stylesheet)` tokens instead of `.default`. Never
  add a direct `BroadwayCore`/`BroadwayUI` dependency. Broadway arrives through
  `WhereUI`. That is why the seam lives there rather than a `broadwayRoot` call
  here (see the root
  [`AGENTS.md`](../../AGENTS.md#never-double-link-a-product-whereui-already-carries)).
