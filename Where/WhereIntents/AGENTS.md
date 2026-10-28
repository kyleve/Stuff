# WhereIntents – Module Shape

WhereIntents is the App Intents layer of the Where feature. It owns the query
and action intents (and their interactive snippet cards) that expose Where to
Siri, Spotlight, and the Shortcuts app. See [`README.md`](README.md) for the
intent list and data paths.

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md). Read those first.

## Scope & dependencies

- Dependencies live in the root [`Package.swift`](../../Package.swift). It
  depends on **WhereUI** for its snippet cards. It must **not** link
  `BroadwayUI`/`BroadwayCore` directly (root
  [double-link rule](../../AGENTS.md#never-double-link-a-product-whereui-already-carries)).
- Intents stay **thin adapters**. They `await intentServices.current()` and
  delegate to that `WhereServices`' collaborators. Domain rules stay in
  `WhereCore`. Card bodies stay in `WhereUI`.

## Invariants

- **The `AppShortcutsProvider` lives in the Where app target**
  (`Where/Where/Sources/WhereShortcuts.swift`). Metadata extraction
  reliably discovers the phrases from there. Intent/entity types are `public`
  for it.
- **Intents never start GPS.** `WhereServices.forIntents(sharingStoreOf:)`
  wires an `IdleLocationSource`. An intent-logged manual entry records a
  "Logged with Siri" audit and no captured location.
- **Resolve services through the `@Dependency`-injected `IntentServices`.
  Intents never open a store.** The app's `AppDelegate` owns the one instance
  and registers it in `didFinishLaunching`. The launch's `resolve-scope` step is
  the process's only store open. The `onServicesReady` hook derives and
  installs the store-sharing intents stack (re-fired on retry and reset
  relaunches). If an intent fires before installation, it **parks** in
  `current()` (cancellation-aware). There is deliberately no self-open
  fallback. A `LogDayIntent` write therefore pings the same `changes()`
  signal the running UI refreshes from.
- **Inject the host App Group into `IntentServices`.** The Today intent's
  optional widget-snapshot fast path uses it; no package target owns an
  audience default.
- **Resolve snippet services and `WhereTheme` together through
  `IntentServices.currentContext()`.** A view must never combine different handoff states.
- **Every `perform()` wraps its work in `measureIntent(_:)`.** Each
  `WhereIntentsLog.IntentName` carries the budget for its own kind of work.
  Then the span history reads per intent (`perform(days-in-region)`). A slow
  Siri answer is attributable. Build the `IntentResult` *outside* the measured
  closure. Keep the span around the fetch/write. Keep the result's type inference
  out of it. `IntentServices.current()` spans only the parking path. A
  measured wait means the intent actually raced the app's launch.
- **Use `Calendar.whereIntents` for all year/day math.** Never use
  `Calendar.current`. It is Gregorian in the current time zone, matching
  `DayAggregator()`. Guard: `Calendar+WhereIntentsTests`.
- **Snippet `perform()` is side-effect-free and re-run on reload.** Mutation
  goes through a separate action intent (`LogDayIntent`). Never mutate inside
  a `SnippetIntent`.
- **`Region` is exposed as `RegionEntity`, not an `AppEnum`.** An `AppEnum`
  requires compile-time-constant display literals. An entity's runtime
  `displayRepresentation` keeps RegionKit the single source of a region's
  spelling. `RegionEntity`/`RegionEntityQuery` are `rawValue`-keyed.
- **Suggestions and Spotlight surface the *tracked* set. Resolution is
  *full-catalog*.** `suggestedEntities()` / `RegionSpotlightIndexer` read
  `RegionEntity.tracked(from:)`. `entities(for:)` resolves any region
  by id (a spoken untracked region still answers, with a zero count).
- **App Intents static metadata is literal. Dialog copy is catalog-backed.**
  Titles and display names are `LocalizedStringResource` literals (the
  framework requires constants). Runtime `IntentDialog` copy goes through
  `IntentStrings`, which composes this module's generated symbols.
- **Only the `dialog.*` / `snippet.*` / `audit.*` keys are `manual`. Leave
  the rest of the catalog alone.** The other entries are the framework's own
  extracted literals. One of them is `%@`. Marking that `manual` fails
  the build with *"Unable to derive a symbol name from this key."*

## Testing

Swift Testing in [`Tests/`](Tests) (`WhereIntentsTests`, hosted in
`StuffTestHost`). Drive intent read/write logic against
`PreviewSupport.previewServices()` seeded via `DayJournal`. Never use the
on-disk store. No `extraPackageProducts`. Everything arrives transitively
through WhereUI.

**Never call an intent's `perform()` in a test.** `perform()` resolves its
`@Dependency` from the process-wide `AppDependencyManager`. In
`StuffTestHost`-hosted bundles nothing registers one (the resolution traps).
In the app-hosted `WhereTests` process an intent would silently ride the
host app's own registration. Test read/write logic against injected
services, and the handoff on per-test `IntentServices` instances
(`IntentServicesTests`). The registration→`@Dependency` plumbing is not
unit-testable. The framework fatal-errors on any `@Dependency` access
outside the intent perform flow (a probe was tried and trapped). Verify it by
invoking a Siri/Shortcuts intent on a device. Do not construct extra
`AppDelegate`s in tests. Each `didFinishLaunching` re-registers the handoff.
`AppDependencyManager`'s re-registration behavior is undocumented.
