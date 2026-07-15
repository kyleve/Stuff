# WhereIntents – Module Shape

WhereIntents is the App Intents layer of the Where feature: the query + action
intents (and their interactive snippet cards) that expose Where to Siri,
Spotlight, and the Shortcuts app. See [`README.md`](README.md) for the intent
list and data paths.

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md) — read those first (they own build/format,
layering, localization, and the WhereUI duplicate-metadata rule).

## Scope & dependencies

- Dependencies live in the root [`Package.swift`](../../Package.swift). It
  depends on **WhereUI** for its snippet cards — mirroring **WhereWidgets** —
  so it must **not** link `BroadwayUI`/`BroadwayCore` directly (a second copy
  would split Broadway's type-keyed metadata; see the root AGENTS "Targets"
  note).
- Intents stay **thin adapters**: they resolve `WhereServices.forIntents()` and
  delegate to its collaborators. Domain rules, persistence, and aggregation stay
  in `WhereCore`; presentation (the card bodies) stays in `WhereUI`. Don't
  reimplement any of that here.

## Invariants

- **The `AppShortcutsProvider` lives in the Where app target**
  (`Where/Where/Sources/WhereShortcuts.swift`), not here, so App Intents
  metadata extraction reliably discovers the phrases. Intent/entity/enum types
  are `public` so it can reference them.
- **Intents never start GPS.** `WhereServices.forIntents()` wires
  `IdleLocationSource`; a manual entry logged from an intent records a
  `ManualEntryAudit` with a "Logged with Siri" note and no captured location.
- **Resolve services through `IntentServices.shared`, not `forIntents()`
  directly.** It caches one `WhereServices` per process so repeated intent runs
  and snippet reloads share a single App Group store (`.localOnly`, matching the
  share extension) — which also makes a `LogDayIntent` write immediately visible
  when the day-count snippet reloads. The running app observes the write via
  `.NSPersistentStoreRemoteChange`.
- **Use `Calendar.whereIntents` for all year/day math**, never `Calendar.current`
  — it's Gregorian in the current time zone, matching `DayAggregator()`, so a
  spoken "this year" lines up with the aggregated report even on a non-Gregorian
  device calendar. `Calendar+WhereIntentsTests` guards the alignment.
- **Snippet `perform()` is side-effect-free and re-run on reload.** The
  interactive `DaysInRegionSnippetIntent.perform()` only re-reads and re-renders;
  its `Button(intent:)` runs a separate action intent (`LogDayIntent`) that
  mutates, then the snippet reloads. Never mutate inside a `SnippetIntent`.
- **`Region` is exposed as `RegionEntity`, not an `AppEnum`.** App Intents
  requires an `AppEnum`'s `caseDisplayRepresentations` (and any
  `typeDisplayRepresentation`) to be compile-time-constant literals; an entity's
  per-instance `displayRepresentation` is runtime, so it reads
  `Region.localizedName` and RegionKit stays the single source of a region's
  spelling. `RegionEntity`/`RegionEntityQuery` are `rawValue`-keyed.
- **App Intents static metadata is literal; dialog copy is catalog-backed.**
  Titles, parameter titles, and type/case display names are `LocalizedStringResource`
  literals (the framework extracts/localizes them and requires constants).
  Runtime `IntentDialog` copy goes through `IntentStrings` (`bundle: .module`).

## Testing

Swift Testing in [`Tests/`](Tests) (`WhereIntentsTests`, hosted in
`StuffTestHost`). Drive intent read/write logic against
`PreviewSupport.previewServices()` (in-memory, no-op schedulers) seeded via
`DayJournal` — never the on-disk store. Follows the WhereUITests dependency
shape (no `extraPackageProducts`; everything arrives transitively through
WhereUI). Internal types are reached via `@testable import WhereIntents`.
