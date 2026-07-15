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
- refactor: Per-entity schema versioning + lazy upcasting for CloudKit sync drift. Today a data-shape migration is a one-time, per-device pass (`StoreMigration` gated by the `store.migrationVersion` marker); it only heals rows present when it runs. A device on an older build can later sync in an older-shaped entity — e.g. an `SDManualDay` with no `dayKey`, or an `SDDismissedIssue` with an epoch `key` — that the marker-gated migration won't re-run to fix, so it silently drifts onto the wrong day / reappears as a dismissed issue. Current stopgap only patches manual-day reads/clears: `SwiftDataStore.keylessManualDays` folds `dayKey == nil` rows into `manualDays(in:)` / `clear(...)` / `clearManualDay(_:)`, and `SDManualDay.toValue()` + `DayPresence` decode UTC-recover a legacy instant. Dismissal-key drift is *not* stopgapped. Replace all of it with a general mechanism:
	- Make record→value conversion (`SD….toValue()`) a version-aware **upcaster**: each `@Model` carries its written schema version, and `toValue()` applies an ordered, pure, idempotent `vN → vN+1` chain, so every read is correct regardless of stored version — no import hook or scan needed (there is no per-record CloudKit import callback anyway). This is the "lazy migration / event-sourcing upcaster" pattern; the existing `toValue()` recovery + `CalendarDayMigration` are its `v0 → v1` seed.
	- Persist a **minReaderVersion** per entity, not just a version. Additive (expand/contract) changes leave it low so old builds keep reading via the retained old field (tolerant reader); only a genuinely forward-incompatible change bumps it. Readers exclude entities whose `minReaderVersion > appVersion` and surface a "some data needs a newer app" warning — the only case that actually needs exclusion.
	- Durable write-back is **read-repair**, decoupled from read correctness: opportunistically (batched, on `.NSPersistentStoreRemoteChange` + launch) rewrite stale records to the current version and stamp it, so old builds can honor exclusion. Transforms must be deterministic + commutative so two devices healing the same record via CloudKit converge (LWW-safe).
	- Reconcile with the existing whole-context `StoreMigration`: keep the marker for one-time *global* ops; per-record shape convergence is driven by the per-entity version, not the global marker.
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
