# WhereIntents

The **Where** App Intents layer: it brings Where's region / day-count data and
manual day logging to **Siri**, **Spotlight**, and the **Shortcuts app**, and
presents results as interactive snippet cards.

Intents are thin adapters. They open the shared App Group store through
[`WhereServices.forIntents()`](../WhereCore/Sources/WhereServices+Intents.swift)
(no GPS is started — see `WhereCore`'s `IdleLocationSource`), do their read/write
through the existing `WhereServices` collaborators (`reports`, `recentActivity`,
`journal`), and render with [`WhereUI`](../WhereUI/) snippet views. The
`AppShortcutsProvider` that gives Siri its spoken phrases lives in the **Where**
app target (`WhereShortcuts`), not here, so App Intents metadata extraction
always discovers it.

## Intents

### Query (read)

| Intent | Answers | Reads |
|--------|---------|-------|
| `DaysInRegionIntent` | "How many days in California this year?" | `ReportReader.yearReport` → `totals[region]` |
| `RegionOnDateIntent` | "What region was I in on June 3?" | `yearReport.days` for that day |
| `TodayRegionsIntent` | "Where am I today?" | `WidgetSnapshotStore` fast path, `yearReport` fallback |
| `RecentActivitySummaryIntent` | "Summarize where I've been this week." | `RecentActivitySummarizer.summary(for:)` |

### Action (write)

| Intent | Does | Writes |
|--------|------|--------|
| `LogDayIntent` | "Log that I was in New York today." | `DayJournal.addManualDay` (stamps a "Logged with Siri" `ManualEntryAudit`) |
| `LogTripIntent` | Backfill a date range with regions. | `DayJournal.addManualDays(from:through:)` |

## Snippets

Query intents return a dialog (for voice-only Siri) plus a snippet card. The
day-count card is an interactive `SnippetIntent` (`DaysInRegionSnippetIntent`):
it hosts a `Button(intent:)` that runs `LogDayIntent` and reloads the card with
the updated total. The presentational card bodies live in `WhereUI`
(`Sources/Intents/`, Broadway-styled, with `#Preview`s); the interactive
wrapper that wires the button to an intent lives here, since `WhereUI` can't
depend on `WhereIntents`.

## Spotlight

`RegionEntity` conforms to `IndexedEntity`; the five regions are indexed into
Spotlight (`RegionSpotlightIndexer.indexRegions()`, called at app launch) so a
search for a region name surfaces Where and its day-count query.

## Shared types

- `RegionAppEnum` — the region parameter for the intents (a menu Siri resolves
  by name), mapped to `RegionKit.Region`.
- `RegionEntity` (+ `RegionEntityQuery`) — the Spotlight-indexable entity and
  the reload-safe parameter of the interactive snippet.
- `ActivityWindowAppEnum` — mirrors `RecentActivityWindow` (24h / week / month /
  year so far).

## Localization

Intent titles, parameter titles, dialog templates, and shortcut phrases resolve
through this module's [`Resources/Localizable.xcstrings`](Sources/Resources/Localizable.xcstrings)
(`IntentStrings`, `bundle: .module`). Region names come from `RegionKit`'s
`Region.localizedName`; window names from this catalog.

## Installation

`WhereIntents` is an SPM library target in [`Package.swift`](../../Package.swift)
(`Where/WhereIntents/Sources`) depending on **WhereCore**, **RegionKit**,
**LogKit**, and **WhereUI** (for the snippet cards). The **Where** app links it;
the hosted `WhereIntentsTests` bundle is wired in [`Project.swift`](../../Project.swift)
via the `unitTests` helper.

## Testing

Swift Testing in [`Tests/`](Tests) (`WhereIntentsTests`, hosted in
`StuffTestHost`): entity/enum ↔ `Region` mapping, and each intent's read/write
logic driven against an in-memory `WhereServices` (via
`PreviewSupport.previewServices()`), verifying counts, date→regions, and that
action intents commit through `DayJournal`.
