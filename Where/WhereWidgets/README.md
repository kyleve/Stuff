# WhereWidgets

The **Where** widget extension.
It provides home-screen and lock-screen widgets that show today's region presence and year-to-date day counts per region.

Widgets never open the SwiftData store. The app publishes an aggregated
[`WidgetSnapshot`](../WhereCore/Sources/Widgets/WidgetDataReader.swift) JSON file
into its audience's shared App Group with a version/domain envelope; this extension reads it via
[`AppGroupDataAccess`](../WhereCore/Sources/Compatibility/AppGroupDataAccess.swift).
The device-local theme is independently published through `WidgetPresentationStore`.
An appearance change does not rebuild the data snapshot.
All rendering lives in [`WhereUI`](../WhereUI). This target only wires
WidgetKit configuration, the timeline provider, and family-specific layout.

## Widgets

| Widget | Kind | Families |
|--------|------|----------|
| **Today** | `com.stuff.where.widgets.today` | small, inline, circular |
| **Day Counts** | `com.stuff.where.widgets.yearTotals` | small, medium, rectangular |

## Data flow

```
Where app (WidgetSnapshotPublisher)
    └─▶ Admission-checked AppGroupDataAccess.writeWidgetSnapshot (App Group JSON)
Where app (WidgetPresentationPublisher)
    └─▶ WidgetPresentationStore.write (App Group JSON)
Receipt + matching snapshot envelope; separate theme file
    └─▶ WhereWidgetProvider.loadEntry (verified read, no store open)
            └─▶ WhereUI widget views
```

The app refreshes the snapshot after each committed store write and calls
`WidgetCenter.reloadAllTimelines()`. The provider also schedules a reload
after the next local midnight so the timeline `date` stays current even if the
app never wakes. Missing or unknown presentation values resolve to Standard.
Appearance changes publish only that small value before reloading timelines.

An exact verified receipt must match the snapshot's version and local/cloud
domain. The shared reader rechecks the receipt after loading the envelope.
Missing, blocked, or mismatched access shows a history-free “Open Where” view in
every family. Missing or old-format JSON is an absent cache after verification;
the next app publication replaces it. Compatibility withdrawal and recovery also
request reloads without rebuilding history.

## Localization

- **In-widget copy** — resolved from [`WhereUI`](../WhereUI)'s `Localizable.xcstrings` (shared views and `WhereFormat`).
- **Widget gallery name/description** — resolved from this extension's [`Resources/Localizable.xcstrings`](Resources/Localizable.xcstrings) via its generated symbols (`String(localized: .widgetGalleryTodayName)`).

## Installation

`WhereWidgets` is a Tuist app-extension target in
[`Project.swift`](../../Project.swift). Its bundle ID and App Group follow the
selected Where audience (Development is isolated; Beta and App Store share the
production family).
It depends on **WhereCore**, **WhereUI**, **RegionKit** (for the `Region` model
its snapshot fixtures use), and **PeriscopeCore**. The main **Where** app embeds the
extension and shares the App Group entitlement.

## Previews

Each widget file ships `#Preview` timelines at the bottom (DEBUG only), using `WhereWidgetEntry.sample` and the fixtures in `WidgetPreviewFixtures.swift`.

## Limitations

- After midnight, the timeline reloads but may still show yesterday's snapshot until the app republishes — a known product trade-off (stale data beats empty).
- There is no dedicated widget test bundle.
  Timeline logic is covered indirectly via **WhereCore** store tests and **WhereUI** widget view hosting tests.
- Cross-process publish → read integration is not exercised in CI (see [`AGENTS.md`](AGENTS.md)).
- Receipt and payload are independently atomic files, not a two-file transaction.
  Observable mismatches fail closed. WidgetKit may retain an already delivered
  timeline until it processes a reload request.
