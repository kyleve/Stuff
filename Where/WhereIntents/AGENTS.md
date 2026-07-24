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
- Intents stay **thin adapters**: they `await intentServices.current()` and
  delegate to that `WhereServices`' collaborators. Domain rules, persistence,
  and aggregation stay in `WhereCore`; presentation (the card bodies) stays in
  `WhereUI`. Don't reimplement any of that here.

## Invariants

- **The `AppShortcutsProvider` lives in the Where app target**
  (`Where/Where/Sources/WhereShortcuts.swift`), not here, so App Intents
  metadata extraction reliably discovers the phrases. Intent/entity/enum types
  are `public` so it can reference them.
- **Intents never start GPS.** `WhereServices.forIntents(sharingStoreOf:)`
  swaps the session's location source for an `IdleLocationSource`; a manual
  entry logged from an intent records a `ManualEntryAudit` with a "Logged with
  Siri" note and no captured location.
- **Resolve services through the `@Dependency`-injected `IntentServices`;
  intents never open a store.** The app's `AppDelegate` owns the one
  `IntentServices` instance and registers it with `AppDependencyManager` in
  `didFinishLaunching` (there is no singleton of ours); every intent and
  entity query declares `@Dependency private var intentServices:
  IntentServices`. The launch's `open-store` step is the process's *only*
  store open: it hands the session's services to the composition root
  (`WhereLaunch.makeLauncher`'s `onServicesReady` hook), which derives the
  store-sharing intents stack (`WhereServices.forIntents(sharingStoreOf:)`)
  and installs it — re-fired on retry and reset relaunches. Intents run over
  the same store instance the app opened, so a `LogDayIntent` write pings the
  same `changes()` signal the running UI refreshes from (and is immediately
  visible when the day-count snippet reloads). An intent that fires before
  installation **parks** in `current()` (cancellation-aware) rather than
  assembling its own stack — there is deliberately no self-open fallback.
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
- **Suggestions and Spotlight surface the *tracked* set; resolution is
  *full-catalog*.** `RegionEntityQuery.suggestedEntities()` and
  `RegionSpotlightIndexer` read the user's tracked regions via
  `RegionEntity.tracked(from:)` (→ `WhereServices.trackedRegions()`), while
  `entities(for:)` resolves any available region by id (so a spoken untracked
  region still answers, with a zero count).
- **App Intents static metadata is literal; dialog copy is catalog-backed.**
  Titles, parameter titles, and type/case display names are `LocalizedStringResource`
  literals (the framework extracts/localizes them and requires constants).
  Runtime `IntentDialog` copy goes through `IntentStrings`, which composes this
  module's generated `LocalizedStringResource` symbols.
- **Only the `dialog.*` / `snippet.*` / `audit.*` keys are `manual`; leave the
  rest of the catalog alone.** Symbol generation runs on `manual` keys, so a new
  key `IntentStrings` reads must be marked `manual` to get a symbol. Do **not**
  normalize the catalog wholesale: the App Intents metadata keys are the
  framework's own extracted literals (keyed by their English text), and one of
  them is `%@` — marking that `manual` fails the build with *"Unable to derive a
  symbol name from this key. It only contains characters that are invalid in
  Swift."*

## Testing

Swift Testing in [`Tests/`](Tests) (`WhereIntentsTests`, hosted in
`StuffTestHost`). Drive intent read/write logic against
`PreviewSupport.previewServices()` (in-memory, no-op schedulers) seeded via
`DayJournal` — never the on-disk store. Follows the WhereUITests dependency
shape (no `extraPackageProducts`; everything arrives transitively through
WhereUI). Internal types are reached via `@testable import WhereIntents`.

**Never call an intent's `perform()` in a test.** `perform()` resolves its
`@Dependency` from the process-wide `AppDependencyManager` — in
`StuffTestHost`-hosted bundles nothing registers one (the resolution traps),
and in the app-hosted `WhereTests` process the host app's own launch *does*
register a handoff over its in-memory store, which an intent would silently
ride. Test the read/write logic against injected services, and test the
handoff itself on per-test `IntentServices` instances (see
`IntentServicesTests`). The registration→`@Dependency` plumbing itself is
**not unit-testable**: the framework fatal-errors on any `@Dependency` access
outside "the intent perform flow" (a probe was tried and trapped), so that
seam is verified by invoking a Siri/Shortcuts intent on a device. Also don't
add tests that construct an `AppDelegate` — each `didFinishLaunching`
re-registers the handoff, and `AppDependencyManager`'s re-registration
behavior is undocumented (the one existing launch test plus the host app's
own launch is the tolerated known case).
