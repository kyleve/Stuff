# App todos

## Usage
- Tag issues with conventional commit semantics: feat, fix, refactor, perf, test, docs
	- Eg "- feat: Add log viewer to settings page"
- Nest tasks that depend on other tasks.
- Don't delete completed tasks, move them to the "Completed issues" section at the bottom.

# Open issues

## PX (Exploratory)
- File system containerization for more structured storage.
- Thinking outloud, every write into the DB results in various "view" and output changes; but nothing really changes beyond that if writes havent happened. What if we established a pipeline that is:
	1) Write into DB
	2) Kick off async jobs to re-evaluate DB contents
	3) Write out views into a table
	4) Consumers consume those view changes
This feels like it might result in a cleaner "pipeline-esque" code layout, and also importantly, will short-circuit a lot of work?
- I still think _WhereServices_' sub-services should be optional based on the current state of the application. Worth trying to see what happens. Or better yet, decompose it all into an enum representing "logged in" vs "logged out" state.
- For logging out / resetting, why do we need to delete all the DB entries? Could we just write the DB into a folder, and on reset, move to another one?
- Noticed when I don't move for a day, nothing gets recorded. I assume this is because we're relying on GPS updates for updates in the background. Any way to guarantee a daily boot outside of GPS?
- Update deployment target to iOS 27; this allows us to use HistoryObserver for CloudKit/SwiftData over the notification.

## P0s (Must do)
- Remove the `waitForOneRunloop` calls added to UI tests; it's a flake paradise.
- Performance pass (How often is the app booting? Can we only do it on changes of say, 1km or more?)
- Schedule local push notifications if we haven’t recorded for the day yet
- Add snapshot images to a new test target

## P1s (Should do)
- `WhereModel` is also getting quite large. Break it up into one parent with children we can pass down.
- refactor: Split `WhereSession` into an always-on coordinator + a presentation view-model whose lifetime scopes its subscriptions. The session is a ~800-line `@Observable` mixing always-on concerns (tracking intent, authorization, reset) with UI mirrors (year report, data issues, ranking, widget snapshot). The always-on reactive work already lives in `WhereCore`/`WhereServices` — `DataIssueScanner` self-invalidates off `store.changes()`, and reminder/widget reconcile is in `DayJournal`/`LocationIngestor` — so it's the presentation half that should become a scene-scoped model. Concretely closes the efficiency leak found in review: `observeDataChanges()` is wired in the headless `syncAuth` launch step (`WhereLaunch.swift`), so every background GPS commit drives a `refresh()` + forced rescan no UI consumes — redundant with the scanner's headless invalidation and `appBecameActive()`'s foreground catch-up (`WhereSession.swift`). Drive the data-change subscription from `RootView`'s scenePhase/`.task` (start on `.active`, cancel on background) instead; synchronous `subscribe()` + the `appBecameActive()` pull cover the background→foreground gap with no staleness regression. Its own PR — touches launch/reset/previews/tests. Pairs with the `WhereModel` break-up above.
- Rewrite controller layer to be a state machine so invariants can’t exist
- SwiftData browser
- What’s with all the `.accessibilityIdentifier(…)` modifiers, do we need them?
- Remove get/set closure-based bindings
- Add a UI that represents where you currently are? Maybe a border on the current location card?
- refactor: Per-entity schema versioning + lazy upcasting for CloudKit sync drift. There is intentionally **no** boot-time data migration (removed pre-release as over-built for a single dev's data). Today a data-shape change relies on: (a) `SD….toValue()` recovering old-shaped rows on read — e.g. `SDManualDay` with no `dayKey` recovers its `CalendarDay` from `dateKey` — and (b) a one-time manual backup **export → replace-import** to rewrite rows into the current shape. Gaps this leaves, which a general mechanism should close: an old-build device can sync in an old-shaped entity at any time (not just at launch), a `dayKey`-less `SDManualDay` is currently **invisible** to the `dayKey`-range queries (`manualDays(in:)` / `clear(...)`) until re-imported (only `allManualDays()` / export sees it via recovery), and legacy **dismissal** keys (epoch, not ISO `CalendarDay`) aren't recovered on read at all, so a pre-`CalendarDay` dismissal reappears until re-dismissed. Replace with:
	- Make record→value conversion (`SD….toValue()`) a version-aware **upcaster**: each `@Model` carries its written schema version, and `toValue()` applies an ordered, pure, idempotent `vN → vN+1` chain, so every read is correct regardless of stored version — no import hook or scan needed (there is no per-record CloudKit import callback anyway). This is the "lazy migration / event-sourcing upcaster" pattern; today's `toValue()` recovery is its `v0 → v1` seed. Make the *filtered* reads (`manualDays(in:)`) upcast-aware too, so a not-yet-rewritten row isn't dropped by a column predicate.
	- Persist a **minReaderVersion** per entity, not just a version. Additive (expand/contract) changes leave it low so old builds keep reading via the retained old field (tolerant reader); only a genuinely forward-incompatible change bumps it. Readers exclude entities whose `minReaderVersion > appVersion` and surface a "some data needs a newer app" warning — the only case that actually needs exclusion.
	- Durable write-back is **read-repair**, decoupled from read correctness: opportunistically (batched, on `.NSPersistentStoreRemoteChange` + launch) rewrite stale records to the current version and stamp it, so old builds can honor exclusion. Transforms must be deterministic + commutative so two devices healing the same record via CloudKit converge (LWW-safe).
	- Open question: the exclusion UX — an older device progressively hiding days a newer device has touched — needs a deliberate warning surface, not a silent drop.

## P2s (Nice to have)
- refactor: Make the scene-scoped model wiring compiler-checked rather than an `@Environment` lookup that fails silently. `WhereSession` (the always-on coordinator) is read from the environment, so a screen mounted without a parent injecting it resolves to a runtime fallback/precondition instead of a compile error. The scoped models (`YearReportModel`, `ResolveModel`, `BackupModel`, `RemindersSettingsModel`) are already constructor-injected; explore threading the coordinator the same way (or a non-defaulting typed `EnvironmentKey`) so a broken wiring can't build. Follow-up from the `WhereSession` split.
- refactor: Split `YearReportModel` further. Post-split it still fuses several roles for the selected year: the loaded report + everything derived from it (ranking, missing days, calendar inputs, tracked-day count), the Resolve badge *count*, the day-write intents (`setManualDay(s)`, `overrideDay`, `clearManualDay`, `clearSelectedYear`), and the Elsewhere drill-in reads (`days(in:)`, `locations(in:)`, `representativeCoordinates()`). The read-only presentation state and the write-intent/drill-in surface could be separate collaborators so a view only holds what it uses. Follow-up from the `WhereSession` split.
- The `guard let controller else { return }` in the WhereModel in WhereUI is weird
- refactor: Move `RegionDays` / `RegionRanking` down from `WhereUI` into `WhereCore` so `DataIssueScanner` can derive primary regions itself instead of `WhereSession` passing `primaryRegions` in. Reverses the current "ranking is a presentation concept" placement; check the widget/UI call sites still compile.
- Raw data browser (similar to SD browser)
- Move `let calendar = Calendar.current` into a var on the controller? There’s a few of these
- Move test only code behind @_spi
- Add comments to strings in xcstrings files
- Can we code-gen the strings.swift file somehow so we're not referencing the string keys manually?

## Deferred snapshot-test flakiness
Known nondeterminism in `WhereUISnapshotTests`, accepted for now — scattered
failures in these areas are expected and shouldn't be papered over by blind
re-recording:

- fix: `debugLogViewer` snapshots render the live shared `WhereLog` buffer, so wall-clock timestamps and run-dependent log lines leak into the image. Needs a fixture — a viewer configured over injected/frozen log entries rather than the process's real buffer.
- fix: Occasional ~20px vertical sheet-offset shift in iPad ax5 sheet captures (seen on `calendar.WithData_iPad_ax5`) — the sheet/scroll settling position varies between runs.
- fix: Verify runs reported large in-memory CILabDeltaE mismatches while the on-disk failure artifacts were pixel-identical to the references — the in-memory captured image at compare time differed from what was flushed to disk. Root cause unknown; needs investigation before trusting tight perceptual tolerances.
- fix: `root.LoggedIn` snapshots the empty state, not the seeded sample report: `MainTabs`' `activate()` re-pulls from the empty in-memory store, replacing the injected report. Making sample data survive requires seeding the store itself, not just injecting the report into the model.

# Completed issues

## P0s (Must do)


## P1s (Should do)
- refactor: Live-refresh the Primary / Calendar / Resolve UI off a single store-change signal. Every committed write (manual edit, live GPS, CloudKit remote import) emits `WhereStore.changes()`; `WhereSession.observeDataChanges()` re-pulls report + data issues, so the UI can't go stale behind an out-of-band write.
- Export / import system (JSON? Zip?)
- feat: Include data-resolution dismissals (`SDDismissedIssue`) in the backup export/import format, so a replace-import doesn’t silently re-surface issues the user already dismissed. (`BackupArchive.dismissedIssues` round-trips `DismissedIssue` value types, preserving `dismissedAt`.)
- Schedule local push notifications if we haven’t recorded for the day yet
- refactor: `WhereController` is getting quite big. Break it up into one parent controller with children. (dissolved into `WhereServices` + focused collaborators)
- Remove `caption(forRank rank: Int) -> String?`, I don’t want the caption

## P2s (Nice to have)
- refactor: Clean up and centralize loggers into a logging module — added the `LogKit` facade (`WhereLog.channel`) and a DEBUG-only in-app log viewer (`LogViewerUI`, Settings → Developer → Logs)
