# WhereIntents – Module Shape

WhereIntents is the App Intents layer of the Where feature: the query +
action intents (and their interactive snippet cards) that expose Where to
Siri, Spotlight, and the Shortcuts app. See [`README.md`](README.md) for the
intent list and data paths.

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md) — read those first.

## Scope & dependencies

- Dependencies live in the root [`Package.swift`](../../Package.swift). It
  depends on **WhereUI** for its snippet cards, so it must **not** link
  `BroadwayUI`/`BroadwayCore` directly (root
  [double-link rule](../../AGENTS.md#never-double-link-a-product-whereui-already-carries)).
- Intents stay **thin adapters**: they `await intentServices.current()` and
  delegate to that `WhereServices`' collaborators. Domain rules stay in
  `WhereCore`, card bodies in `WhereUI`.

## Invariants

- **The `AppShortcutsProvider` lives in the Where app target**
  (`Where/Where/Sources/WhereShortcuts.swift`) so metadata extraction
  reliably discovers the phrases; intent/entity types are `public` for it.
- **Intents never start GPS.** `WhereServices.forIntents(sharingStoreOf:)`
  wires an `IdleLocationSource`; an intent-logged manual entry records a
  "Logged with Siri" audit and no captured location.
- **Resolve services through the `@Dependency`-injected `IntentServices`;
  intents never open a store.** The app's `AppDelegate` owns the one instance
  and registers it in `didFinishLaunching`; the launch's `open-store` step is
  the process's only store open, and the `onServicesReady` hook derives and
  installs the store-sharing intents stack (re-fired on retry and reset
  relaunches). An intent that fires before installation **parks** in
  `current()` (cancellation-aware) — there is deliberately no self-open
  fallback. A `LogDayIntent` write therefore pings the same `changes()`
  signal the running UI refreshes from.
- **Every `perform()` wraps its work in `measureIntent(_:)`**, and each
  `WhereIntentsLog.IntentName` carries the budget for its own kind of work — so
  the span history reads per intent (`perform(days-in-region)`) and a slow Siri
  answer is attributable. Build the `IntentResult` *outside* the measured
  closure: keep the span around the fetch/write, and the result's type inference
  out of it. `IntentServices.current()` spans only the parking path, so a
  measured wait means the intent actually raced the app's launch.
- **Use `Calendar.whereIntents` for all year/day math**, never
  `Calendar.current` — Gregorian in the current time zone, matching
  `DayAggregator()`. Guard: `Calendar+WhereIntentsTests`.
- **Snippet `perform()` is side-effect-free and re-run on reload.** Mutation
  goes through a separate action intent (`LogDayIntent`); never mutate inside
  a `SnippetIntent`.
- **`Region` is exposed as `RegionEntity`, not an `AppEnum`** — an `AppEnum`
  requires compile-time-constant display literals, and an entity's runtime
  `displayRepresentation` keeps RegionKit the single source of a region's
  spelling. `RegionEntity`/`RegionEntityQuery` are `rawValue`-keyed.
- **Suggestions and Spotlight surface the *tracked* set; resolution is
  *full-catalog*** — `suggestedEntities()` / `RegionSpotlightIndexer` read
  `RegionEntity.tracked(from:)`, while `entities(for:)` resolves any region
  by id (a spoken untracked region still answers, with a zero count).
- **App Intents static metadata is literal; dialog copy is catalog-backed.**
  Titles and display names are `LocalizedStringResource` literals (the
  framework requires constants); runtime `IntentDialog` copy goes through
  `IntentStrings`, which composes this module's generated symbols.
- **Only the `dialog.*` / `snippet.*` / `audit.*` keys are `manual`; leave
  the rest of the catalog alone.** The other entries are the framework's own
  extracted literals, and one of them is `%@` — marking that `manual` fails
  the build with *"Unable to derive a symbol name from this key."*

## Testing

Swift Testing in [`Tests/`](Tests) (`WhereIntentsTests`, hosted in
`StuffTestHost`). Drive intent read/write logic against
`PreviewSupport.previewServices()` seeded via `DayJournal` — never the
on-disk store. No `extraPackageProducts`; everything arrives transitively
through WhereUI.

**Never call an intent's `perform()` in a test.** `perform()` resolves its
`@Dependency` from the process-wide `AppDependencyManager`: in
`StuffTestHost`-hosted bundles nothing registers one (the resolution traps),
and in the app-hosted `WhereTests` process an intent would silently ride the
host app's own registration. Test read/write logic against injected
services, and the handoff on per-test `IntentServices` instances
(`IntentServicesTests`). The registration→`@Dependency` plumbing is not
unit-testable — the framework fatal-errors on any `@Dependency` access
outside the intent perform flow (a probe was tried and trapped); verify it by
invoking a Siri/Shortcuts intent on a device. Don't construct extra
`AppDelegate`s in tests: each `didFinishLaunching` re-registers the handoff,
and `AppDependencyManager`'s re-registration behavior is undocumented.
