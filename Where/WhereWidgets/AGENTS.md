# WhereWidgets – Module Shape

The **Where** widget extension: two WidgetKit configurations (Today + year
totals) that read a published `WidgetSnapshot` from the App Group and render
via shared views in **WhereUI**. See [`README.md`](README.md) for the data path
and widget list.

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md). Read those first.

## Scope & dependencies

- **Tuist app-extension target** ([`Project.swift`](../../Project.swift),
  `Where/WhereWidgets/Sources`, bundle ID `com.stuff.where.widgets`).
- Depends on **WhereCore** (snapshot types + App Group store),
  **WhereUI** (widget views + in-widget localized strings), and **LogKit**
  (via `WhereLog.channel(.whereWidgets)`).
- Must **not** import SwiftData, open the user's store, or duplicate aggregation
  logic — the app publishes; the extension only reads and renders.
- No test bundle today; behavior is covered by **WhereCore**
  (`WidgetSnapshotStoreTests`, `WidgetSnapshotPublisherTests`) and **WhereUI**
  (`WidgetViewsTests`).

## Key types

- [`WhereWidgetsBundle`](Sources/WhereWidgetsBundle.swift) – `@main`
  `WidgetBundle` registering both widgets.
- [`WhereWidgetProvider`](Sources/WhereWidgetProvider.swift) – shared
  `TimelineProvider`. Reads `WidgetSnapshotStore.shared()?.read()`; on a missing
  file logs **`warning`** and renders an empty snapshot; on App Group resolution
  failure logs **`error`**. Timeline policy is `.after(nextMidnight)`.
- [`TodayWidget`](Sources/TodayWidget.swift) /
  [`YearTotalsWidget`](Sources/YearTotalsWidget.swift) – family routing only;
  content views live in **WhereUI**.
- [`WidgetSnapshotFixtures`](Sources/WidgetSnapshotFixtures.swift) – shared
  `DayAggregator().calendar` and snapshot builders for the provider + previews.
- [`WidgetStrings`](Sources/WidgetStrings.swift) – gallery name/description from
  this extension's `Localizable.xcstrings` (`bundle: .module`).

## Behaviors to preserve

- **Read-only App Group access.** Only the app writes
  `widget-snapshot.json`; the extension never calls `write`.
- **No stale-day invalidation in the provider.** A snapshot whose `day` rolled
  past today is still shown until the app republishes — intentional (see
  `loadEntry` comment).
- **Gallery vs runtime previews.** `getSnapshot` returns `.sample` when
  `context.isPreview`; live snapshots read the store.
- **Exhaustive `WidgetFamily` switches** with `@unknown default:` — no bare
  `default:` over `WidgetFamily`.
- **Single shared calendar** via `WidgetSnapshotFixtures.calendar` — do not
  construct `DayAggregator()` per timeline load.

## Refresh contract

1. App commits a store change → `WidgetSnapshotPublisher` rebuilds snapshot →
   `WidgetTimelineRefreshing.publish` writes JSON + `WidgetCenter.reloadAllTimelines()`.
2. Widget provider reads JSON on each timeline request.
3. Provider schedules `.after(nextMidnight)` so WidgetKit re-queries even without
   an app reload (data may be stale until step 1 runs again).

## Conventions

- Follow root rules: exhaustive enum switches, small named structs, no closure
  `Binding(get:set:)`.
- In-widget strings come from **WhereUI** (`Strings.*`); gallery strings from
  **this extension's catalog** (`WidgetStrings`).
- Every widget ships `#Preview` timelines (DEBUG, bottom of file).

## Testing gaps (documented)

- No cross-process integration test (app publish → extension read) in CI.
- No dedicated timeline-provider unit tests — extract helpers here if adding a
  test target later.
