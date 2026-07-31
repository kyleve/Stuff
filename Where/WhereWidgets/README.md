# WhereWidgets

The **Where** widget extension: home-screen and lock-screen widgets that show
today's region presence and year-to-date day counts per region.

Widgets never open the SwiftData store. The app publishes a single aggregated
[`WidgetSnapshot`](../WhereCore/Sources/Widgets/WidgetDataReader.swift) JSON file
into the shared App Group (`group.com.stuff.where`); this extension reads it via
[`WidgetSnapshotStore`](../WhereCore/Sources/Widgets/WidgetSnapshotStore.swift).
All rendering lives in [`WhereUI`](../WhereUI/) — this target only wires
WidgetKit configuration, the timeline provider, and family-specific layout.

## Widgets

| Widget | Kind | Families |
|--------|------|----------|
| **Today** (iPhone/iPad) | `com.stuff.where.widgets.today` | small, inline, circular |
| **Day Counts** (iPhone/iPad) | `com.stuff.where.widgets.yearTotals` | small, medium, rectangular |
| **Where Summary** (Mac) | `com.stuff.where.widgets.macSummary` | small, medium |

## Data flow

```
Where app (WidgetSnapshotPublisher)
    └─▶ WidgetSnapshotStore.write (App Group JSON)
            └─▶ WhereWidgetProvider.loadEntry (widget extension read)
                    └─▶ WhereUI widget views
```

The app refreshes the snapshot after each committed store write and calls
`WidgetCenter.reloadAllTimelines()`. The provider also schedules a reload
after the next local midnight so the timeline `date` stays current even if the
app never wakes.

## Localization

- **In-widget copy** — resolved from [`WhereUI`](../WhereUI/)'s
  `Localizable.xcstrings` (shared views and `WhereFormat`).
- **Widget gallery name/description** — resolved from this extension's
  [`Resources/Localizable.xcstrings`](Resources/Localizable.xcstrings) via its
  generated symbols (`String(localized: .widgetGalleryTodayName)`).

## Installation

`WhereWidgets` is a multi-destination Tuist app-extension target in
[`Project.swift`](../../Project.swift) (bundle ID `com.stuff.where.widgets`).
It depends on **WhereCore**, **WhereUI**, **RegionKit** (for the `Region` model
its snapshot fixtures use), and **PeriscopeCore**. The main **Where** app embeds the
extension and shares the App Group entitlement.
The bundle declaration exposes only the combined Today + year-to-date summary
when compiled for Mac Catalyst.

## Previews

Each widget file ships `#Preview` timelines at the bottom (DEBUG only),
using `WhereWidgetEntry.sample` and the fixtures in
`WidgetPreviewFixtures.swift`.

## Limitations

- After midnight, the timeline reloads but may still show yesterday's snapshot
  until the app republishes — a known product trade-off (stale data beats empty).
- There is no dedicated widget test bundle; timeline logic is covered indirectly
  via **WhereCore** store tests and **WhereUI** widget view hosting tests.
- Cross-process publish → read integration is not exercised in CI (see
  [`AGENTS.md`](AGENTS.md)).
