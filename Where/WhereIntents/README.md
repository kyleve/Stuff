# WhereIntents

The **Where** App Intents layer: it brings Where's region / day-count data and
manual day logging to **Siri**, **Spotlight**, and the **Shortcuts app**, and
presents results as interactive snippet cards.

Intents are thin adapters. They resolve a process-cached `WhereServices`
through the `@Dependency`-injected `IntentServices` handoff (owned by the
app's `AppDelegate` and registered with `AppDependencyManager`; the launch
installs a stack built with
[`WhereServices.forIntents(sharingStoreOf:)`](../WhereCore/Sources/WhereServices+Intents.swift)
over the same `SwiftDataStore` it opened, and an intent that fires earlier
waits for that install rather than opening its own store; no GPS started via
`WhereCore`'s `IdleLocationSource`), do their read/write through the existing
collaborators
(`reports`, `recentActivity`, `journal`) using a Gregorian calendar
(`Calendar.whereIntents`, matching the domain's aggregation so year/day math
lines up), and render with [`WhereUI`](../WhereUI/) snippet views. The
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

`RegionEntity` conforms to `IndexedEntity`; the user's **tracked** regions are
indexed into Spotlight (`RegionSpotlightIndexer.indexRegions()`, called at app
launch, re-run picks up changes) so a search for a region name surfaces Where and
its day-count query.

## Shared types

- `RegionEntity` (+ `RegionEntityQuery`) — the region parameter every intent
  operates on, the Spotlight-indexable entity, and the reload-safe parameter of
  the interactive snippet. It's an `AppEntity` (not an `AppEnum`) so its
  per-instance `displayRepresentation` can read `Region.localizedName` at
  runtime — App Intents requires an `AppEnum`'s `caseDisplayRepresentations` to
  be compile-time-constant literals, which would force restating RegionKit's
  region names here. `entities(for:)` resolves **any available** region by id
  (so "days in Texas" answers even when untracked), while `suggestedEntities()`
  and the Spotlight index surface the user's **tracked** set (via
  `WhereServices.trackedRegions()`).
- `ActivityWindowAppEnum` — mirrors `RecentActivityWindow` (24h / week / month /
  year so far). An enum is fine here because these display names have no
  RegionKit-owned source.

## Timing

Every intent's work is one budgeted Periscope span named after the intent
(`perform(days-in-region)`), so a Siri answer that felt slow can be attributed
to the read, the write, or the wait itself: `IntentServices.current()` spans only
the path where it actually parks for the app's launch to install the services
stack. Budgets live on `WhereIntentsLog.IntentName` beside the name, and the
slow-by-nature intents (the on-device model summary) get the slack.

## Localization

- **Static App Intents metadata** — intent titles, parameter titles, and the
  enum/entity type & case display names — are `LocalizedStringResource` string
  literals. App Intents extracts and localizes these through the app's own App
  Intents string table; the framework requires them to be compile-time
  constants, so they can't be routed through this module's `Bundle.module`
  catalog.
- **Runtime dialog copy** (the spoken/`IntentDialog` results) resolves through
  this module's [`Resources/Localizable.xcstrings`](Sources/Resources/Localizable.xcstrings)
  via `IntentStrings`, which composes the catalog's generated symbols,
  interpolating dynamic values.
- **Region names** always come from `RegionKit`'s `Region.localizedName` — never
  restated here.

## Installation

`WhereIntents` is an SPM library target in [`Package.swift`](../../Package.swift)
(`Where/WhereIntents/Sources`) depending on **WhereCore**, **RegionKit**,
**PeriscopeCore**, and **WhereUI** (for the snippet cards). The **Where** app links it;
the hosted `WhereIntentsTests` bundle is wired in [`Project.swift`](../../Project.swift)
via the `unitTests` helper.

## Testing

Swift Testing in [`Tests/`](Tests) (`WhereIntentsTests`, hosted in
`StuffTestHost`): entity/enum ↔ `Region` mapping, and each intent's read/write
logic driven against an in-memory `WhereServices` (via
`PreviewSupport.previewServices()`), verifying counts, date→regions, and that
action intents commit through `DayJournal`.
