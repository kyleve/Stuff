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
- Add snapshot images to a new test target

## P1s (Should do)
- fix: `WhereServices.setPrimaryRegions(_:)` commits atomically but skips `DayJournal.reconcileAfterDayChange()` — widgets/reminders/summary don't refresh until foreground/configure. Route picker commits through the unified fan-out (or document intentional deferral).
- fix: The Elsewhere entry card renders raw inflection markup instead of an agreed region count — it shows literally `^[3 region](inflect: true)`. `locations.elsewhere.subtitle` is authored for automatic grammar agreement (`^[%lld region](inflect: true)`), but the string-catalog compiler passes that markup through **verbatim** into the compiled `Localizable.strings` (unlike a real plural such as `primary.elsewhereOnly.description`, which compiles to an `NSStringLocalizedFormatKey` dict), and flattening the resource to a `String` never runs the inflection engine. Pre-existing — the catalog entry is byte-identical on `main` and predates the String Catalog symbol migration. Fix by either rendering the resource directly so SwiftUI applies inflection (`Text(.locationsElsewhereSubtitle(regionCount))` in `ElsewhereSummaryCard`, dropping the `WhereFormat` hop) or replacing the markup with an explicit plural variation. `WhereFormatTests.elsewhereCardSubtitleInflectsTheRegionCount` pins the expected output behind `withKnownIssue`, so it trips as soon as this is fixed.
- `WhereModel` is also getting quite large. Break it up into one parent with children we can pass down.
- refactor: Split `WhereSession` into an always-on coordinator + a presentation view-model whose lifetime scopes its subscriptions. **Partial progress (July 2026):** `YearReportModel` is now scene-scoped in `MainTabs` — `activate()` / `deactivate()` on `scenePhase` drive `observeDataChanges()` and refresh, closing the headless-relaunch rescan leak that previously wired the subscription through launch `syncAuth`. `ResolveModel`, `BackupModel`, and `RemindersSettingsModel` are already view-scoped. Remaining: the coordinator is still ~460 lines mixing tracking intent, authorization, reset, and region-style mirrors; finish extracting presentation collaborators and drive any leftover reactive work from scene lifetime. Pairs with the `WhereModel` break-up below.
- Rewrite controller layer to be a state machine so invariants can’t exist
- SwiftData browser
- What’s with all the `.accessibilityIdentifier(…)` modifiers, do we need them?
- Add a UI that represents where you currently are? Maybe a border on the current location card?
- refactor: Per-entity schema versioning + lazy upcasting for CloudKit sync drift. There is intentionally **no** boot-time data migration or on-read legacy recovery (removed pre-release as over-built for a single dev's data). Today a data-shape change relies solely on a one-time manual backup **export → transform (`Tools/upgrade-backup.rb`) → replace-import** to rewrite rows into the current shape; `SD….toValue()` reads only the current shape and drops (fault-logs) a row it can't place (e.g. an `SDManualDay` with no `dayKey`). Gaps this leaves, which a general mechanism should close: an old-build device can sync in an old-shaped entity at any time (not just at launch), and until it's re-imported such a row is dropped on read rather than upcast. Replace with:
	- Make record→value conversion (`SD….toValue()`) a version-aware **upcaster**: each `@Model` carries its written schema version, and `toValue()` applies an ordered, pure, idempotent `vN → vN+1` chain, so every read is correct regardless of stored version — no import hook or scan needed (there is no per-record CloudKit import callback anyway). This is the "lazy migration / event-sourcing upcaster" pattern. Make the *filtered* reads (`manualDays(in:)`) upcast-aware too, so a not-yet-rewritten row isn't dropped by a column predicate.
	- Persist a **minReaderVersion** per entity, not just a version. Additive (expand/contract) changes leave it low so old builds keep reading via the retained old field (tolerant reader); only a genuinely forward-incompatible change bumps it. Readers exclude entities whose `minReaderVersion > appVersion` and surface a "some data needs a newer app" warning — the only case that actually needs exclusion.
	- Durable write-back is **read-repair**, decoupled from read correctness: opportunistically (batched, on `.NSPersistentStoreRemoteChange` + launch) rewrite stale records to the current version and stamp it, so old builds can honor exclusion. Transforms must be deterministic + commutative so two devices healing the same record via CloudKit converge (LWW-safe).
	- Open question: the exclusion UX — an older device progressively hiding days a newer device has touched — needs a deliberate warning surface, not a silent drop.

## P2s (Nice to have)
- feat: Bound the Periscope log store by size, not just age (PR #94 review). `WhereLaunch.bootstrapLogging` prunes events older than the retention window (now 100 days); with the built-in ambient sources emitting continuously, a heavy-logging device could still grow the store large within the window. Add a count cap alongside the time prune — `PeriscopeStore.pruneEvents(keepingNewest:)` already exists — so the store is bounded regardless of volume.
- refactor: Make the scene-scoped model wiring compiler-checked rather than an `@Environment` lookup that fails silently. `WhereSession` (the always-on coordinator) is read from the environment, so a screen mounted without a parent injecting it resolves to a runtime fallback/precondition instead of a compile error. The scoped models (`YearReportModel`, `ResolveModel`, `BackupModel`, `RemindersSettingsModel`) are already constructor-injected; explore threading the coordinator the same way (or a non-defaulting typed `EnvironmentKey`) so a broken wiring can't build. Follow-up from the `WhereSession` split.
- refactor: Split `YearReportModel` further. Post-split it still fuses several roles for the selected year: the loaded report + everything derived from it (ranking, missing days, calendar inputs, tracked-day count), the Resolve badge *count*, the day-write intents (`setManualDay(s)`, `overrideDay`, `clearManualDay`, `clearSelectedYear`), and the Elsewhere drill-in reads (`days(in:)`, `locations(in:)`, `representativeCoordinates()`). The read-only presentation state and the write-intent/drill-in surface could be separate collaborators so a view only holds what it uses. Follow-up from the `WhereSession` split.
- The `guard let controller else { return }` in the WhereModel in WhereUI is weird
- refactor: Move `RegionDays` / `RegionRanking` down from `WhereUI` into `WhereCore` so `DataIssueScanner` can derive primary regions itself instead of `WhereSession` passing `primaryRegions` in. Reverses the current "ranking is a presentation concept" placement; check the widget/UI call sites still compile.
- feat: Animate the Locations ranking reorder. `RegionSummaryCard` now morphs its day count when it changes on screen (`DayCountMorph`), but a change that also flips the two primary regions' order still snaps the cards into their new positions — an animated count landing in a hard-cut reorder. Needs an `.animation(_:value:)` keyed on the ranking around the `ForEach` in `LocationsView`, checked against the card's `matchedTransitionSource` zoom so the two don't fight.
- Raw data browser (similar to SD browser)
- Move `let calendar = Calendar.current` into a var on the controller? There’s a few of these
- Move test only code behind @_spi
- Add comments to strings in xcstrings files
- fix: Four literals in source get auto-extracted into the catalogs as value-less entries, which is why an IDE build had anything to write back at all (see the serialization normalization PR). They're committed as Xcode writes them; removing an entry for good means removing the literal. `Marker("", coordinate:)` in `RecordedPointsMap` produces the empty `""` key (an unlabeled dev-map pin — `Annotation` with an explicit accessibility label would say what it means); `Text("\(group.outlineCount)")` in `RegionMapView` and `Text("\(day.dayOfMonth)")` in `CalendarContentView` produce `%lld` and bypass `WhereFormat`'s number styling; and a `Button("Log today here")` in an `IntentSnippets` `#Preview` hardcodes copy the `snippet.logTodayHere` symbol already owns. `App content` comes from a `LifecycleContainer` `#Preview` in LifecycleKit.

# Completed issues

## P0s (Must do)


## P1s (Should do)
- fix: `WhereLaunch.lifecycleReason` misclassified every scene-based cold launch as headless (`UIApplication.applicationState` reads `.background` at `didFinishLaunchingWithOptions` under the UIScene lifecycle even for a user tap). Replaced the guess with a first-class `LifecycleReason.undetermined`: the app launches `.undetermined` (renders no view tree, runs only the background-safe steps to service a possible location wake), and `RootView`'s existing `enterForeground()` promotes it to `.userForeground` once a scene activates — the one trustworthy foreground signal. A genuine headless wake honestly stays `.undetermined` (no fabricated `.background(.location)` cause). `LifecycleRunner` now tracks completed step IDs so the promotion re-drive skips finished work, so a foreground cold launch no longer re-walks the work steps.
- refactor: Live-refresh the Primary / Calendar / Resolve UI off a single store-change signal. Every committed write (manual edit, live GPS, CloudKit remote import) emits `WhereStore.changes()`; `YearReportModel.observeDataChanges()` (scene-scoped via `MainTabs.activate()` / `deactivate()`) re-pulls report + data issues, so the UI can't go stale behind an out-of-band write.
- Export / import system (JSON? Zip?)
- feat: Include data-resolution dismissals (`SDDismissedIssue`) in the backup export/import format, so a replace-import doesn’t silently re-surface issues the user already dismissed. (`BackupArchive.dismissedIssues` round-trips `DismissedIssue` value types, preserving `dismissedAt`.)
- Schedule local push notifications if we haven’t recorded for the day yet
- refactor: `WhereController` is getting quite big. Break it up into one parent controller with children. (dissolved into `WhereServices` + focused collaborators)
- Remove `caption(forRank rank: Int) -> String?`, I don’t want the caption

## P2s (Nice to have)
- refactor: Code-gen the strings so keys aren't referenced manually — adopted Xcode's String Catalog `LocalizedStringResource` symbol generation across the app (`STRING_CATALOG_GENERATE_SYMBOLS`), deleted the hand-maintained `Strings`/`ShareStrings`/`WidgetStrings` facades in favor of generated symbols + the `WhereFormat`/`IntentStrings` composition helpers, so a typo'd or removed key is now a compile error. (RegionKit region names stay data-driven by design.)
- refactor: Remove get/set closure-based `Binding` values from SwiftUI views — replaced with computed properties on `@Observable` models (e.g. `SaveErrorAlertState`).
- refactor: Clean up and centralize loggers into a logging module — added the `LogKit` facade (`WhereLog.channel`) and a DEBUG-only in-app log viewer (`LogViewerUI`, Settings → Developer → Logs)
