# WhereWidgets – Module Shape

The **Where** widget extension: WidgetKit configurations that read a published
`WidgetSnapshot` from the App Group and render via shared views in **WhereUI**.
See [`README.md`](README.md) for the data path and widget list.

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md). Read those first.

## Scope & dependencies

- **Tuist app-extension target** ([`Project.swift`](../../Project.swift),
  bundle ID `com.stuff.where.widgets`), depending on **WhereCore**,
  **WhereUI**, **RegionKit**, and **LogKit**.
- Must **not** import SwiftData, open the user's store, or duplicate
  aggregation logic — the app publishes; the extension only reads and renders.
- No test bundle; behavior is covered from **WhereCore** and **WhereUI**.

## Refresh contract

1. App commits a store change → `WidgetSnapshotPublisher` rebuilds the
   snapshot → writes JSON + `WidgetCenter.reloadAllTimelines()`.
2. The provider reads the JSON on each timeline request and schedules
   `.after(nextMidnight)` so WidgetKit re-queries even without an app reload.

## Invariants

- **Read-only App Group access** — only the app writes `widget-snapshot.json`.
- **No stale-day invalidation in the provider.** A snapshot whose `day` rolled
  past today is still shown until the app republishes — intentional.
- In-widget copy comes from the shared WhereUI content views; gallery
  name/description use this extension's own generated String Catalog symbols
  (`String(localized: .widgetGalleryTodayName)`). Widgets ship `#Preview`
  timelines like any other WhereUI view.
- **Seed the Broadway root via WhereUI's `whereBroadwayRoot()`** (applied in each
  widget's `StaticConfiguration` content) so the shared WhereUI views resolve
  trait-aware `@Environment(\.stylesheet)` tokens instead of `.default`. Do **not**
  add a direct `BroadwayCore`/`BroadwayUI` dependency — the extension already gets
  Broadway through `WhereUI` (a dynamic framework), and a second copy would split
  Broadway's type-keyed environment metadata (see the root `AGENTS.md` "Targets"
  note). That's why the seam lives in WhereUI, not a `broadwayRoot` call here.
