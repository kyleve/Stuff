# Swift Module Audit Report

Read-only review of all **14 SPM library targets**, **6 Tuist app/extension targets**, and the repo-owned **Bumper Bowling** architecture rules (~359 source / ~198 test Swift files across shipped targets, plus 2 unwired prototype sources). No code was changed.

**Date:** July 26, 2026  
**Method:** Read-only verification of every open July 19 finding against current source; file-count refresh; new-surface review of the week's landings (Periscope migration #94, Settings drill-in #111, developer HUD #115, navigation restructure #119, log-viewer tooling #107, String Catalog symbols #124, Gregorian calendars `fe99dde`, previews `52f0136`, Bumper Bowling #127, catalog serialization #135).  
**Prior audit:** July 19, 2026 (~308 source / ~189 test).  
**Follow-ups:** See [TODO](#todo) for actionable checklist items.

---

## Executive summary

| Severity | Count |
|----------|------:|
| Critical | 0 |
| High | 5 |
| Medium | 44 |
| Low | 48 |
| **Total** | **97** |

| Category | Count |
|----------|------:|
| bug | 21 |
| test | 27 |
| convention | 24 |
| performance | 7 |
| duplication | 3 |
| localization | 4 |
| docs | 8 |
| design | 3 |

**Overall:** A heavy week of landings. `LogKit` and `LogViewerUI` are **gone** — Periscope replaced them (#94) — so the target count drops to 14 SPM libraries while WhereUI grew 84 → 113 sources and WhereCore 70 → 87. Several long-standing findings closed for real: the Where app's `README.md`, the `.undetermined` launch-reason state machine, `SharedItemLoader` warning logs, `#Preview` coverage across WhereUI/WhereWidgets, and the String Catalog symbol migration (a typo'd key is now a compile error). The three **high** findings carried from July 19 are all still open — daily-summary staleness, the WhereUI tracking-toggle race, and the LifecycleKit terminal-phase race — and two new **high** ones landed: `CalendarDay.displayDate` resolves day labels through `Calendar.current`, and the brand-new `where.gregorian_calendar` Bumper rule that exists to catch exactly that is blind to the form the drift actually takes.

---

## Top 10 highest-impact findings

| # | Sev | Module | Issue |
|---|-----|--------|-------|
| 1 | **high** | Bumper Bowling | `where.gregorian_calendar` matches only an explicit `Calendar.current` base, so it misses every implicit `.current` in the tree — the rule is green while 7 production sites drift |
| 2 | **high** | WhereUI | `CalendarDay.displayDate` resolves through `Calendar.current`, so day labels on a non-Gregorian device render a date ~543 years off |
| 3 | **high** | WhereCore | `DailySummaryReconciler.reconcile()` is still absent from the post-day-change fan-out — the notification body stays stale until a foreground re-`configure` |
| 4 | **high** | WhereUI | Tracking toggle race — `trackingEnabled`'s setter spawns unserialized `Task`s; a slow `startTracking()` can finish after a later `stopTracking()` |
| 5 | **high** | LifecycleKit | Cancel during the *last* step's `minVisible` hold isn't observed before `runSteps` returns `.completed`, so a superseded drive can set `phase = .ready` |
| 6 | **medium** | WhereCore | `setPrimaryRegions(_:)` commits atomically but skips `reconcileAfterDayChange()` — widgets/reminders/summary stale after a picker commit |
| 7 | **medium** | WhereCore | `SwiftDataStore.setTrackedRegion(false)` hard-deletes the row; the picker and Settings region editor now reach it, so past-year re-attribution risk is live rather than latent |
| 8 | **medium** | PeriscopeCore | Orphan sweep treats a `SpanBegan` whose payload won't decode as an orphan-close candidate, silently overriding `survivesRelaunch` |
| 9 | **medium** | WhereUI | Load-state UI is duplicated across four views with no shared `ReportLoadGate`; `PresenceTimelineList` renders the *empty* state while the year is still loading |
| 10 | **medium** | BroadwayCatalog | The Broadway showcase app never seeds a Broadway root, and its test bundle is an empty `struct` wired into the CI scheme |

---

## Cross-cutting themes

### The Gregorian rule has a blind spot, and the catalog says otherwise

`.bumper/RULES.md` states the tree "intentionally contains three violations" of `where.gregorian_calendar`, left visible so the live lint demonstrates enforcement. It doesn't: the rule filters `MemberAccessExprSyntax` on `base == "Calendar"`, which matches the spelled-out `Calendar.current` but **not** the implicit-member form (`calendar: Calendar = .current`, `startOfDay(in: .current)`) — and after `fe99dde` the implicit form is the *only* one left. CI runs `bumper lint` as a hard `severity: .error` gate and is green, which confirms it: the rule reports nothing while seven production sites drift. The same paragraph's claim about preview-coverage violations is also stale (`52f0136` closed those). A rule that reads as enforced but enforces nothing is worse than a documented convention, because it stops anyone from looking.

### Reconciliation: same two holes, one now user-reachable

`reconcileAfterDayChange()` still fans out to issue state and widgets only. **Daily summary** remains outside it, and **`setPrimaryRegions(_:)`** still commits without calling it. Related and newly urgent: untracking a region hard-deletes its row, and the shipped onboarding picker plus the Settings region editor both route into that path, so the past-year re-attribution risk the `SwiftDataStore` TODO describes is now something a user can trigger.

### Presentation-layer calendar drift outlived the fix

`fe99dde` moved the view call sites onto explicit Gregorian calendars, but the drift relocated into shared helpers: `CalendarDay.displayDate` hardcodes `.current`, and `DateRangeFormatting.abbreviated` / `PresenceTimeline.stints` *default* to it — with `PresenceTimelineList` not passing the report's calendar. Because these are the helpers every day label flows through, one line reaches the relabel, logged-days, resolution, and region drill-in screens.

### The navigation restructure moved the duplication, not the shape

Locations / Your Year / Settings replaced the old four-tab shell, so the `PrimaryView` / `SecondaryView` / `CalendarView` load-state triplicate is gone — but the same `YearReportModel.loadState` gate is now copy-pasted across `LocationsView`, `ElsewhereView`, `ResolutionView`, and `CalendarContentView`, and `PresenceTimelineList` skipped the gate entirely (it shows "no stays" during load). A `ReportLoadGate` would now save four sites rather than three.

### Periscope's durability gaps are the oldest open work in the repo

Three items — `survivesRelaunch` resume mechanics, journaling the pre-store-attach window, and multi-process journal coordination — remain P0/P1 in `Shared/Periscope/TODOs.md` and are all confirmed unimplemented. The store-side half of relaunch policy landed (the sweep leaves surviving spans open), but nothing re-seeds `Periscope.openSpans`, so `end(for:)` in the new process still warns "without a matching begin".

### PeriscopeTools grew fast; its live models rebuild from scratch

+9 sources / +9 tests this week (span tree, hierarchy, span history, density, Broadway stylesheet). The incremental **fetch** landed (`LogQuery.afterSequence`), but `SpanTreeModel.load` / `LogHierarchyModel.load` still rebuild the whole forest from all accumulated events on every `changes()` ping, `LogInspectorModel` re-queries full subtrees, and the new drill-ins re-read row density from `.standard` rather than the injectable `defaults` the viewer threads through.

### Extension/app targets still defer tests to libraries

WhereWidgets (7/0), WhereShareExtension (5/0), and RegionViewer (1/0) ship no test bundle by design; BroadwayCatalog ships an empty one. `ShareEvidenceModel.buildPendingEvidence()` and `WhereWidgetProvider`'s midnight timeline policy remain the two gaps that are worth closing regardless of the pattern.

### Localization architecture is now compiler-enforced

The String Catalog symbol migration (#124) is complete and the hand-maintained key facades are gone, so a removed key breaks the build. Remaining slips are individual, not architectural: a raw `String(localized: "region.other")` in RegionKit, a hardcoded caption in `IntentSnippets`, the parallel `share.form.*` / `evidence.form.*` namespaces, and the four auto-extracted literals catalogued in `Where/TODOs.md`.

### Infrastructure that is genuinely done

Periscope replaced LogKit/LogViewerUI outright; `.undetermined` replaced the cold-launch guess with a state that can't lie; `#Preview` coverage is complete across WhereUI/WhereWidgets; `@_spi(Testing)` is the norm for test seams (the only `…ForTesting` API is itself behind it); the SwiftData browser shipped into Settings → Developer; String Catalogs are serialized the way Xcode writes them and linted (`./xcstrings`); and `./simulator` now resolves destinations by UDID for `profile` / `flaky` / CI.

---

## Quick wins vs needs design

Summary buckets — every open TODO below is tagged **`quick-win`** or **`needs-design`**.

### Quick wins (localized, low-risk)

- Widen `where.gregorian_calendar` to the implicit `.current` form and correct `.bumper/RULES.md`'s two stale "intentional violations" paragraphs
- Give `CalendarDay.displayDate` an explicit calendar (and drop the `.current` defaults on `DateRangeFormatting` / `PresenceTimeline`)
- Gate `PresenceTimelineList` on `report.loadState` so loading doesn't read as empty
- Add `DailySummaryReconciler.reconcile()` to the fan-out + a regression test
- Route `setPrimaryRegions(_:)` through `reconcileAfterDayChange()` (or document why picker commits defer)
- Add the LifecycleKit supersede-during-`minVisible` regression test
- Add `GeoJSONTests.swift` with malformed/unsupported fixture snippets
- Add `ShareEvidenceModelTests` with in-memory storage
- Replace the 3 remaining `waitForOneRunloop()` call sites with predicate polling
- Log the `SpanEnded` / `SpanBegan` payload decode failures in the Periscope tools and sweep
- Seed `.broadwayRoot()` in BroadwayCatalog and give its test bundle at least a launch smoke test
- Log `AppIconCatalog` and `LocationNamer` failures at `warning`

### Needs design / broader refactor

- Serialize **WhereSession** tracking mutations and split `wantsTracking` from `isTracking`
- Gate LifecycleKit's terminal `.ready` on the active drive (generation token or post-hold cancellation check)
- Unify **daily summary** into the `reconcileAfterDayChange()` policy (or document the deferral)
- Soft-delete untracked regions now that the picker and region editor reach the hard delete
- Incremental year-report reads for the widget/reminder/summary hot paths
- Extract a shared **ReportLoadGate** and one region-selection form for manual/relabel
- **Periscope**: `survivesRelaunch` resume, pre-attach bootstrap journal, multi-process claim mechanism
- **PeriscopeTools**: incremental tree/forest rebuilds; hierarchy count vs. subtree drill-in semantics
- **WhereSession** / **YearReportModel** split (tracked in `Where/TODOs.md`)
- Per-entity schema versioning (tracked in `Where/TODOs.md`)
- ShareEvidence vs AddEvidence form consolidation

---

## TODO

Actionable follow-ups from this audit. Items marked `[x]` were open in the July 19 audit and are now verified fixed.

| Tag | Meaning |
|-----|---------|
| **Severity** | `high` / `medium` / `low` — impact from this audit |
| **quick-win** | Localized, low-risk; can land in a small PR |
| **needs-design** | Broader refactor, policy choice, or cross-module contract |

### High priority

- [ ] **Bumper Bowling** — Widen `where.gregorian_calendar` to match the implicit-member `.current` form; it currently only matches an explicit `Calendar` base (**high**, bug, **quick-win** — new this week)
- [ ] **Bumper Bowling** — Correct `.bumper/RULES.md`: neither the "three calendar violations" nor the preview-coverage violations exist (**medium**, docs, **quick-win** — pairs with the above)
- [ ] **WhereUI** — Give `CalendarDay.displayDate` an explicit Gregorian calendar; it drives every day label (**high**, bug, **quick-win** — new this week)
- [ ] **WhereCore** — Call `DailySummaryReconciler.reconcile()` from the unified post-day-change fan-out (GPS ingest hook, `reconcileAfterDayChange()`, backup `onImport`) (**high**, bug, **needs-design** — extend fan-out vs. document foreground-only policy)
- [ ] **WhereCore** — Add test: mutate data → summary notification body updates without re-`configure` (**high**, test, **quick-win** — pairs with item above)
- [ ] **WhereUI** — Serialize `WhereSession.trackingEnabled` mutations (cancel/coalesce in-flight start/stop tasks) (**high**, bug, **needs-design**)
- [ ] **WhereUI** — Split toggle binding: `wantsTracking` for intent vs `isTracking` for effective GPS state (**high**, bug, **needs-design** — `wantsTracking` exists internally; the public toggle still binds effective state both ways)
- [ ] **LifecycleKit** — Gate the terminal `phase = .ready` on the active drive; `runSteps` returns `.completed` after a cancelled *final* step's `hold()` because the loop's `Task.isCancelled` check is at the top of the next iteration (**high**, bug, **needs-design**)
- [ ] **LifecycleKit** — Add test superseding a drive during `minVisible` (teardown/enterForeground while the hold is active) (**high**, test, **quick-win**)

### Medium priority — WhereCore

- [ ] **WhereCore** — Route `setPrimaryRegions(_:)` through `reconcileAfterDayChange()` after picker commits (**medium**, bug, **needs-design**)
- [ ] **WhereCore** — Soft-delete untracked regions; `setTrackedRegion(false)` / `setPrimaryRegions` hard-delete rows and both the picker and Settings region editor now reach that path (**medium**, bug, **needs-design** — promoted from low; the picker shipped)
- [ ] **WhereCore** — Route `DayJournal.ingest` / `addManualSample` paths through reminder reconcile when ingest changes presence, or mark them `@_spi(Testing)` (**medium**, bug, **needs-design**)
- [ ] **WhereCore** — Handle durable outbox save failure without silent sample loss on relaunch (**medium**, bug, **needs-design**)
- [ ] **WhereCore** — Add test for outbox *save* failure (load failure is covered) (**medium**, test, **quick-win**)
- [ ] **WhereCore** — Fail or surface partial state when `BackupService` import can't read an evidence asset; it currently logs and continues with `blob: nil` (**medium**, bug, **quick-win** — new this week)
- [ ] **WhereCore** — `ReminderReconciler`'s issue-scan failure returns a badge count of `0`, indistinguishable from "no issues" (**medium**, bug, **quick-win** — new this week)
- [ ] **WhereCore** — Review retry-queue capacity policy / user-visible degradation at eviction (**medium**, bug, **needs-design**)
- [ ] **WhereCore** — Consider incremental year-report reads or memoization for widget/reminder/summary hot paths (**medium**, performance, **needs-design**)
- [ ] **WhereCore** — Remove the default parameter from `DayJournal.addEvidence`; also `WherePreferences.init(store:)`, `SwiftDataStore.make(storage:)`, `WidgetDataReader`'s aggregator/attributor (**medium**, convention, **quick-win**)
- [ ] **WhereCore** — Add `WherePreferencesTests` over `InMemoryKeyValueStore` (**medium**, test, **quick-win** — new this week)

### Medium priority — WhereUI

- [ ] **WhereUI** — Extract shared `ReportLoadGate`; the same `loadState` gate is duplicated across `LocationsView`, `ElsewhereView`, `ResolutionView`, `CalendarContentView` (**medium**, duplication, **needs-design**)
- [ ] **WhereUI** — Gate `PresenceTimelineList` on `report.loadState`; it shows the empty state during load and year switches (**medium**, bug, **quick-win** — new this week)
- [ ] **WhereUI** — Drop the `Calendar = .current` defaults on `DateRangeFormatting.abbreviated` and `PresenceTimeline.stints`, and pass `report.calendar` from `PresenceTimelineList` (**medium**, convention, **quick-win** — new this week)
- [ ] **WhereUI** — Extract one shared region-selection form; `DayRelabelView` renders a flat list where `ManualDayView` has grouped sections + `loadGrouping()` (**medium**, duplication, **needs-design**)
- [ ] **WhereUI** — Batch or cap concurrent geocoding in `RegionDaysView` day rows (**medium**, performance, **needs-design**)
- [ ] **WhereUI** — Make `LocationNamer` itself cancellation-aware; `ElsewhereView` only guards after the await (**medium**, bug, **needs-design**)
- [ ] **WhereUI** — Localize the `IntentSnippets` production caption (hardcoded `" in "` / `" · "`) (**medium**, localization, **quick-win** — new this week)
- [ ] **WhereUI** — Add an adversarial test for tracking-toggle ordering (stop while a slow start is in flight) (**medium**, test, **quick-win**)
- [ ] **WhereUI** — Remove the 3 remaining `waitForOneRunloop()` call sites (`OnboardingTests`, `LaunchSplashViewTests`) (**medium**, test, **quick-win** — also `Where/TODOs.md` P0)

### Medium priority — Periscope, LifecycleKit, SwiftDataInspector

- [ ] **PeriscopeCore** — Orphan sweep must not close a span whose `survivesRelaunch` policy can't be decoded; log the failure and prefer leaving it open (**medium**, bug, **quick-win** — new this week)
- [ ] **PeriscopeCore** — Implement `SpanRelaunchPolicy.survivesRelaunch` resume mechanics; the store leaves spans open but nothing re-seeds `openSpans` (**medium**, design, **needs-design** — P0 in `Shared/Periscope/TODOs.md`)
- [ ] **PeriscopeCore** — Journal from process start so the pre-store-attach window isn't lost (**medium**, bug, **needs-design** — P0 there)
- [ ] **PeriscopeCore** — Multi-process journal ingest coordination / claim mechanism (**medium**, bug, **needs-design** — P1 there)
- [ ] **PeriscopeTools** — Reconcile hierarchy subtree counts (`primaryScope`-only, uncapped) with the `.subtree` drill-in (any linked scope, capped at 500), or document the asymmetry (**medium**, bug, **needs-design** — P1 there)
- [ ] **PeriscopeTools** — Rebuild the hierarchy/span forests incrementally; only the fetch is bounded today (**medium**, performance, **needs-design** — P2 there)
- [ ] **PeriscopeTools** — Give `LogInspectorModel` the same `afterSequence` cursor; it re-queries full subtrees on every commit (**medium**, performance, **needs-design** — new this week)
- [ ] **PeriscopeTools** — Drive `SpanTreeRow` from `\.logRowDensity` and thread the injectable `defaults` into every drill-in (**medium**, convention, **quick-win** — P2 there)
- [ ] **PeriscopeTools** — Drive `SpanTreeModel` duration and open-state from one source so a decode failure can't render an ended span as running (**medium**, bug, **quick-win** — P2 there)
- [ ] **PeriscopeTools** — Log the error on `LogHierarchyModel` / `SpanTreeModel` / `SpanHistoryModel` `.failed` states (**medium**, convention, **quick-win** — P2 there)
- [ ] **SwiftDataInspector** — Add test for bare `PersistentIdentifier` to-one relationship resolution (**medium**, test, **quick-win**)
- [ ] **SwiftDataInspector** — Split the 759-line omnibus test file; optional hosted UI smoke tests (**medium**, test, **needs-design**)

### Medium priority — extensions, hosts, Broadway

- [ ] **WhereIntents** — Test the per-intent `perform()` glue (guards, snippet wiring, error→dialog mapping) or note in `README.md` that only the reader/writer seams are unit-testable (**medium**, test, **quick-win** — the seams themselves are now well covered)
- [ ] **WhereShareExtension** — Add `ShareEvidenceModelTests` (**medium**, test, **quick-win**)
- [ ] **WhereShareExtension** — Consolidate the share/add evidence form and its parallel `share.form.*` / `evidence.form.*` keys (**medium**, duplication, **needs-design**)
- [ ] **WhereWidgets** — Unit-test the midnight timeline policy with an injectable calendar/store (**medium**, test, **needs-design**)
- [ ] **RegionKit** — Add `GeoJSONTests.swift` for unsupported geometry and malformed coordinates (**medium**, test, **quick-win**)
- [ ] **RegionKit** — Test that a missing/corrupt manifest degrades to an empty catalog at runtime, not just at the log-event level (**medium**, test, **quick-win**)
- [ ] **BroadwayCatalog** — Seed `.broadwayRoot()`; the showcase renders without a `BContext` (**medium**, bug, **quick-win** — new this week)
- [ ] **BroadwayCatalog** — Replace the empty `struct BroadwayCatalogTests {}` with a launch smoke test; it is wired into the CI scheme and asserts nothing (**medium**, test, **quick-win**)
- [ ] **BroadwayUI** — Fix nested `BRootViewController` duplicate trait observers (**medium**, bug, **needs-design** — latent; Where uses `whereBroadwayRoot()` / `BRootView` only)
- [x] **Where app** — Add module-level `Where/Where/README.md` (**medium**, docs) — *added; accurately describes the three-file shell*
- [x] **LifecycleKit** — Replace the cold-launch `applicationState` guess with `LifecycleReason.undetermined` (**high**, bug) — *#109; `WhereTests` pins `.undetermined`, `completedStepIDs` keeps promotion from re-running work*
- [x] **WhereUI** — Ship a `#Preview` in every previewable source file (**medium**, convention) — *`52f0136`; `where.preview_coverage` now finds nothing*
- [x] **WhereUI/WhereCore** — Replace hand-maintained string-key facades with generated catalog symbols (**medium**, localization) — *#124; a removed key is a compile error*
- [x] **WhereUI** — Ship the in-app SwiftData browser (**medium**, feat) — *`SwiftDataInspectorView` in Settings → Developer*
- [x] **WhereWidgets** — Document the post-midnight stale-snapshot policy as intentional degradation (**medium**, bug) — *documented in provider + README + AGENTS*
- [x] **WhereShareExtension** — Log `SharedItemLoader` load failures at `warning` (**low**, convention)

### Low priority / polish

- [ ] **WhereCore** — Log `WidgetSnapshotStore.read()` decode failures at `warning` on the app write path (**low**, convention, **quick-win**)
- [ ] **WhereCore** — Surface the `applicationSupport()` → `NoOpLocationOutbox` fallback; it silently disables cross-launch retry durability (**low**, bug, **quick-win**)
- [ ] **WhereCore** — Fix the stale `LocationIngestor` comment claiming `os.Logger`; it emits typed `WhereLog` events (**low**, docs, **quick-win**)
- [ ] **WhereCore** — Narrow the two `README.md` claims the code no longer honors (every write reconciles; errors never swallowed) (**low**, docs, **quick-win**)
- [ ] **WhereUI** — Log AppIcon catalog and `LocationNamer` failures instead of collapsing to `[]` / `nil` (**low**, convention, **quick-win**)
- [ ] **WhereUI** — Update the `RootView` doc comment; it still describes four top-level screens (**low**, docs, **quick-win**)
- [ ] **WhereUI** — Profile the `RegionSummaryCard` Canvas rosette (uncapped ring count) (**low**, performance, **needs-design**)
- [ ] **WhereUI** — Localize the `IntentSnippets` `#Preview` button (**low**, localization, **quick-win**)
- [ ] **WhereUI** — Add tests for `LocationNamer` (cache/coalescing) and `CalendarContentView`'s scroll-reveal gate (**low**, test, **quick-win**)
- [ ] **WhereIntents** — Register `LogTripIntent` in `WhereShortcuts` or document Shortcuts-only discovery (**low**, convention, **quick-win**)
- [ ] **WhereIntents** — Use `Calendar.whereIntents` for `LogDayIntent`'s default day instead of `Date()` (**low**, convention, **quick-win** — `DayJournal` still buckets Gregorian, so no data impact)
- [ ] **WhereIntents** — Log the App Group open failure behind `WhereIntentReader.todaySnapshot`'s `try?` (**low**, convention, **quick-win**)
- [ ] **WhereIntents** — Test `RegionSpotlightIndexer` and `WhereIntentReader.recentActivity` (**low**, test, **quick-win**)
- [ ] **WhereShareExtension** — Log the discarded provider `error` in `SharedItemLoader.loadDataRepresentation` (**low**, convention, **quick-win**)
- [ ] **RegionKit** — Reference a generated symbol for `region.other` instead of a raw `String(localized:)` key (**low**, convention, **quick-win**)
- [ ] **RegionViewer** — Wrap `RegionMapView` in `.whereBroadwayRoot()` for faithful dev styling (**low**, convention, **quick-win**)
- [ ] **RegionViewer** — Refresh `README.md`; it describes a monolithic `us-states.geojson` and a hand-listed region set (**low**, docs, **quick-win**)
- [ ] **BroadwayCore/UI** — Guard the `BContext` / `BRootViewController` `didSet`s on unchanged `Equatable` values (**low**, convention, **quick-win**)
- [ ] **BroadwayCore** — Evict the stylesheet cache on memory pressure (documented `TODO`) (**low**, performance, **needs-design**)
- [ ] **BroadwayCore/UI** — Add 1:1 tests for `UIViewControllerTraitObserver`, `EquatableIgnored`, `BTraitOverrides+SwiftUI` (**low**, test, **quick-win**)
- [ ] **BroadwayCatalog** — Build the component gallery `README.md` promises, or narrow the README (**low**, docs, **quick-win**)
- [ ] **LifecycleKit** — Replace the fixed 50 ms negative-assertion sleep with bounded polling; add a duplicate-step-ID fail-fast test (**low**, test, **quick-win**)
- [ ] **JournalKit** — Stop discarding append errors with `try?` in the concurrent-append test; exercise `.full` sync durability (**low**, test, **quick-win**)
- [ ] **StuffTestHost** — Document or split the WhereCore-always-embedded build trade-off; the scene name is duplicated between `AppDelegate` and `Project.swift` (**low**, performance, **needs-design**)
- [ ] **StuffCore** — Replace the tautological `version` test when real API exists (**low**, test, **quick-win**)
- [ ] **PeriscopeTools** — Log `SpanHistoryModel`'s `SpanEnded` decode failures; pin open-span containment semantics with a test (**low**, test, **quick-win** — P2 in `Shared/Periscope/TODOs.md`)
- [ ] **PeriscopeCore** — Note the pre-attach journaling gap in `PeriscopeCore/README.md`'s crash-durability section (**low**, docs, **quick-win**)

### Summary by effort

| Effort | Open | Done (since July 19) |
|--------|-----:|---------------------:|
| **quick-win** | ~38 | ~7 |
| **needs-design** | ~24 | ~1 |

Filter tips: search `quick-win` for bite-sized PRs; search `needs-design` for items to discuss or spec before coding.

---

## Per-module findings

### Bumper Bowling — architecture lint (2 open, new surface)

The repo-owned rule set (`BumperBowling.swift`, `.bumper/Sources`, catalog in `.bumper/RULES.md`) covers **Where production sources only**: layer boundaries and forbidden imports, graph integrity, production store opening, checked-concurrency escape hatches, composition ownership (`WhereServices`, live `LocationSource`), the Gregorian calendar, the `store.perform` transaction boundary, `AppShortcutsProvider` ownership, the logging facade and logging-type placement, and `#Preview` coverage. Mutation tests live in `.bumper/Tests`; CI runs `config`, `test`, and `lint --timings` with every rule at `severity: .error`.

**High**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `.bumper/Sources/WhereProjectRules.swift:121` | `where.gregorian_calendar` filters on `base?.trimmedDescription == "Calendar"`, so the implicit-member form (`= .current`, `in: .current`) — the only form left in the tree — never matches | Also match `MemberAccessExprSyntax` with no base where the contextual type is `Calendar`, or add a lexical `.current` check scoped to calendar parameters/arguments |

**Medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| docs | `.bumper/RULES.md:101`, `:143` | Claims three calendar violations and preview-coverage violations are "left visible during this bootstrap"; CI's hard lint gate is green, so neither exists | Delete both paragraphs (and re-add the calendar one only if the widened rule genuinely finds drift) |

**Verified OK:** rule IDs and scopes in `RULES.md` match `WhereProjectRules.swift`; the component graph matches `BumperBowling.swift` / `WhereArchitecture.swift`; Broadway is forbidden on WhereIntents/WhereWidgets via `forbidden_import`, matching `Project.swift`.

**Files:** 4 rule/test sources · RULES.md ✓

---

### WhereCore (17 open / 4 verified fixed)

**High**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `DailySummaryReconciler.swift:45` (only caller is `configure`); `DayJournal.reconcileAfterDayChange():63` | Daily summary never reconciled on data changes | Add `await summary.reconcile()` to the fan-out; test without re-`configure` |

**Medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `WhereServices.setPrimaryRegions(_:):285` | Picker commit pings `changes()` but skips the reminder/widget/summary fan-out | Route through `reconcileAfterDayChange()` or document the deferral |
| bug | `SwiftDataStore.swift:773`, `:838` | Untracking hard-deletes the row; the shipped picker and region editor both reach it, risking past-year re-attribution to `.other` | Soft-delete (retain for attribution, hide from pickers) |
| bug | `DayJournal.swift:70`, `:82`, `:93` | `ingest(_:)`, bulk ingest, and `addManualSample` publish widgets but skip reminder/issue reconcile | Route through the fan-out or mark `@_spi(Testing)` |
| bug | `LocationOutbox.swift:86`; `LocationIngestor.swift:343` | Outbox save failure is logged and swallowed, so a process death loses the in-memory sample | Degraded-state handling + a relaunch test |
| bug | `LocationIngestor.swift:348` | FIFO eviction at capacity drops samples with a warning only | User-visible degradation or a documented policy |
| bug | `BackupService.swift:188` | Import skips unreadable evidence assets and continues with `blob: nil` | Throw a typed `BackupError` or surface partial-import state |
| bug | `ReminderReconciler.swift:193` | Issue-scan failure contributes `0` to the badge, reading as "all clear" | Preserve the last good count or expose a scan-failed state |
| performance | `ReportReader.yearReport:27`; `WidgetDataReader.snapshot:85` | Full-year re-aggregation on widget/reminder/summary paths | Memoize or read incrementally |
| convention | `DayJournal.addEvidence:216`; `WherePreferences.swift:14`; `SwiftDataStore.make:179`; `WidgetDataReader.swift:74` | Parameter defaults on Core APIs | Explicit call-site arguments |
| test | summary / outbox / preferences | No test for summary refresh without `configure`, outbox *save* failure, or `WherePreferences` | Spy scheduler; failing-outbox double; `InMemoryKeyValueStore` |

**Low**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| convention | `WidgetSnapshotStore.read():62` | `try?` makes a decode failure indistinguishable from "never written" | Log at `warning` on the app write path |
| bug | `LocationOutbox.swift:52` | Falling back to `NoOpLocationOutbox` silently disables retry durability | Surface to launch wiring or treat as a programmer error |
| docs | `LocationIngestor.swift:334`; `README.md:48`, `:161` | Comment claims `os.Logger`; README claims every write reconciles and errors are never swallowed | Update all three |
| test | 28 of 70 implementation files | No namesake `*Tests.swift` (notably `FoundationModelSummaryGenerator`, `WherePreferences`, `WidgetTimelineRefresher`, `BackupArchive`); `WhereCoreTests.swift` is an omnibus holding `YearReportTests` | Split by concern as files change |

**Verified OK:** backup import → full fan-out via `onImport`; summary format args (guarded by `summaryBodyContainsNoFormatPlaceholders`); `BackupError` localization; drain-only ingest skipping the full reminder reconcile; no raw-string/`os.Logger` logging left; no PII in `.public` events; `RecentActivitySummarizer`'s typed unavailability and segment cap.

**Files:** 87 source / 58 test · README ✓ · AGENTS ✓

---

### WhereUI (17 open / 4 verified fixed)

**High**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `DateRangeFormatting.swift:33` | `CalendarDay.displayDate` resolves `DateComponents(year:month:day:)` in `Calendar.current`, so a Buddhist/Japanese-era device renders a date centuries off across relabel, logged-days, resolution, and region drill-in | Take an explicit calendar (default Gregorian + current time zone) |
| bug | `WhereSession.swift:441` | `trackingEnabled`'s setter spawns an unserialized `Task` per assignment; `startTracking()` never re-reads intent before `reconcileTracking()` | One in-flight task / generation token; re-check `wantsTracking` |

**Medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| duplication | `LocationsView.swift:59`, `ElsewhereView.swift:49`, `ResolutionView.swift:57`, `CalendarContentView.swift:58` | The same `loadState` gate copy-pasted four ways | Extract `ReportLoadGate` |
| bug | `PresenceTimelineList.swift:10` | Returns `[]` when `report.report == nil`, so loading renders the empty state | Gate on `report.loadState` |
| convention | `PresenceTimeline.swift:37`; `DateRangeFormatting.swift:6`, `:19`; `PresenceTimelineList.swift:12` | `Calendar = .current` defaults, and the list doesn't pass `report.calendar` | Require an explicit calendar |
| duplication | `ManualDayView.swift:212` vs `DayRelabelView.swift:106` | Relabel renders a flat region list; manual has grouped sections + `loadGrouping()` | One shared region-form section |
| performance | `RegionDaysView.swift:125` | Per-row `.task` geocode with no concurrency cap | Batch unique coordinates on the parent |
| bug | `ElsewhereView.swift:33`; `LocationNamer.swift:64` | View-level cancel guard only; the namer itself isn't cancellation-aware | Make `name(for:)` cancellation-aware |
| localization | `IntentSnippets.swift:63` | Production caption composes hardcoded `" in "` / `" · "` | Catalog key with placeholders, via `WhereFormat` |
| test | `WhereSessionTrackingTests.swift` | No coverage of rapid on/off ordering | Adversarial test with a slow scripted start |
| test | `OnboardingTests.swift:43`, `LaunchSplashViewTests.swift:11`, `:19` | `waitForOneRunloop()` flake risk (3 sites) | Predicate polling |

**Low**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| convention | `AppIconModel.swift:73`, `AppIconOption.swift:89`, `LocationNamer.swift:86` | `try?` collapses catalog/geocode failure into an empty picker or `nil` | Log at `warning`; keep the honest empty state |
| docs | `RootView.swift:10` | Still documents "four top-level screens (Primary, Elsewhere, Resolve, Settings)" | Describe the three-tab `MainTabs` shell |
| performance | `RegionSummaryCard.swift:98` | `ringCount` derives from size with no cap | Profile, then cap or pre-render |
| localization | `IntentSnippets.swift:190` | `Button("Log today here")` in a `#Preview` | Use the `snippet.logTodayHere` symbol |
| test | `LocationNamer.swift`, `CalendarContentView.swift` | No namesake tests; the zoom/scroll-reveal path has hosting smoke only | Cache/coalescing tests; `scrolledForYear` gate test |

**Verified OK:** no closure `Binding(get:set:)` anywhere in the module (`SaveErrorAlertState`, `AddEvidenceModel`, `AppIconModel` expose computed `get`/`set`); every load-state `switch` enumerates its cases; `MainTabs` drives `YearReportModel.activate()` / `deactivate()` off `scenePhase`; every previewable `View`/`Widget` ships an in-file `#Preview`; `README.md` and `AGENTS.md` are current on the three-tab shape.

**Files:** 113 source / 36 test · README ✓ · AGENTS ✓

---

### LifecycleKit (2 open / 5 verified fixed)

**High / medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `LifecycleRunner.runStep:284`; `runSteps:223`, `:251`; `drive:198` | `runStep` returns `.completed` unconditionally after `presentation.hold()`, and `runSteps`' cancellation check sits at the *top* of the loop — so a cancel during the **final** step's hold is never observed and the superseded drive sets `phase = .ready` | Check `Task.isCancelled` after the hold, and gate the terminal phase on an active-drive token |
| test | `LifecycleRunnerTests.swift:430` | `minVisible` hold is tested, but nothing supersedes a drive *during* the hold | Add a teardown/`enterForeground()`-mid-hold test |

**Low:** one fixed 50 ms sleep as a negative-assertion window (`LifecycleRunnerTests.swift:174`); no test that duplicate step IDs trap.

**Verified OK:** cancel-and-drain no longer waits out the full `minVisible` window; duplicate step-ID `precondition`; localized `LifecycleFailureView`; background *and* `.undetermined` promotion container tests. The `.undetermined` state machine (#109) holds up: `completedStepIDs` records only steps that ran to completion, so a promotion re-drive skips finished work while still running newly-applicable steps, and promotion/teardown both funnel through the same cancel-and-drain.

**Files:** 9 source / 11 test · README ✓ · AGENTS ✓

---

### SwiftDataInspector (2 open)

**Medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| test | `SwiftDataReflection.swift:132` | The bare-`PersistentIdentifier` branch is untested; the existing relationship test faults a materialized model | Fixture test over an unmaterialized slot |
| test | `Tests/SwiftDataInspectorTests.swift` | One 759-line file for 13 sources | Split by concern; optional hosted smoke |

**Low:** `try?` on fetches yields empty rows/counts (documented DEBUG degradation); bare `default:` in `defaultFormat` over `Any` (open-type dispatch, acceptable).

**Verified OK:** pagination + lazy rendering with regression tests; relationship resolution for materialized models.

**Files:** 13 source / 1 test · README ✓ · AGENTS ✓

---

### PeriscopeCore (4 open)

**Medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `PeriscopeStore.swift:221` | A `SpanBegan` whose payload won't decode skips the `survivesRelaunch` branch and becomes an orphan-close candidate | Log the decode failure; leave the span open, or persist the policy columnar |
| design | `SpanExit.swift:86`; `LogSpan.swift:568` | The sweep honors `survivesRelaunch` but nothing re-seeds `Periscope.openSpans`, so `end(for:)` warns "without a matching begin" | Async bootstrap that re-opens unmatched surviving spans, with wall-clock durations |
| bug | `Periscope.swift:192`; `PeriscopeStore.make:84` | Events emitted before the store is attached reach neither store nor journal | Short-lived bootstrap journal ingested (and deleted) at attach |
| bug | `PeriscopeStoreJournalIngest.swift:12` | An app launch would ingest and delete a *live* extension session's journal | Claim file / skip-live-claims, designed with App Group store sharing |

**Low:** `LogJournalEntry.swift:101` still cliffs attachments at 64 KB (external-storage plan is P1); `PeriscopeCore/README.md`'s crash-durability section doesn't mention the pre-attach gap.

**Verified OK:** Broadway does not leak below PeriscopeTools; no test touches `Periscope.shared`; `@_spi(Testing)` used for injection hooks; span-pair floors, rollback-on-failed-save, and the seeded lifecycle fuzz all still in place.

**Files:** 35 source / 31 test · README ✓ · AGENTS ✓

---

### PeriscopeUI & PeriscopeTools (6 open)

**PeriscopeUI:** thin DEBUG bridge — no issues. **Files:** 1 source / 2 test · README ✓ · AGENTS ✓

**PeriscopeTools medium:** hierarchy subtree counts tally `primaryScope` only and uncapped while the drill-in matches any linked scope capped at 500 (`LogHierarchyModel.swift:89` vs `LogInspectorModel.swift:59`, `ScopeEventsView.swift:23`) — the asymmetry is pinned by a test, so it's a decision to revisit rather than a slip; `SpanTreeModel.swift:145` derives duration from `try? decode(SpanEnded)` while `exitMode` reads the stored column, so a decode failure renders an exit chip *and* "running"; `SpanTreeView.swift:25`/`:79` seeds `\.logRowDensity` but hard-codes `comfortable`, and `ScopeEventsView`/`LogInspectable`/`SpanHistoryView` re-read density from `.standard` instead of the injectable `defaults`; `load` rebuilds the whole forest per `changes()` ping although the fetch is incremental; `LogInspectorModel` has no cursor at all; `.failed` states set honest UI without logging.

**PeriscopeTools low:** `SpanHistoryModel.swift:155` buckets a corrupt `SpanEnded` under a message-derived name with no log; no test pins whether two concurrent *open* spans should nest (today `.distantFuture` makes the later one a child); no 1:1 tests for the small `*+Display` extensions.

**Files:** PeriscopeTools 24 source / 22 test · README ✓ · AGENTS ✓

---

### JournalKit, StuffCore, TestHostSupport, StuffTestHost (0–2 open each)

**JournalKit:** strong fuzz/truncation coverage. Low: the concurrent-append test discards errors with `try?` (`JournalTests.swift:186`), so it could pass with fewer entries than asserted; `.full` sync durability is exercised by a single append. **Files:** 2/3 · README ✓ · AGENTS ✓

**StuffCore:** intentional scaffold; tautological version test. **Files:** 1/1 · README ✓ · AGENTS ✓

**TestHostSupport:** dependency-free UIKit helpers; no dedicated bundle by design (exercised via hosted bundles). **Files:** 1/0 · README ✓ · AGENTS ✓

**StuffTestHost:** the WhereCore-always-embedded trade-off is documented and verified load-bearing in `Project.swift:256`; the scene configuration name is duplicated between `AppDelegate.swift:11` and `Project.swift:244`; smoke test lives in `LifecycleKitTests`. **Files:** 2/0 · README ✓ · AGENTS ✓

---

### BroadwayCore & BroadwayUI (5 open)

**Medium:** nested `BRootViewController` still registers duplicate trait observers (`BRootViewController.swift:92` `TODO`) — latent, since Where reaches Broadway only through `whereBroadwayRoot()` / `BRootView`.

**Low:** stylesheet cache never evicts on memory pressure (`BStylesheets.swift:90` `TODO`); `BContext.swift:34` and `BRootViewController.swift:37` run `didSet` work without an unchanged-value guard; bare `default:` mapping unknown `UIContentSizeCategory` to `.large` (`BTraits+Values.swift:125`, a deliberate fallback); no 1:1 tests for `UIViewControllerTraitObserver`, `EquatableIgnored`, `BTraitOverrides+SwiftUI`.

**Verified OK:** stylesheet/trait/cycle behavior well tested; trait registration pairs with teardown.

**Files:** BroadwayCore 17/10 · BroadwayUI 6/4 · README ✓ · AGENTS ✓

---

### BroadwayCatalog (3 open)

**Medium:** `BroadwayApp.swift:6` never seeds `.broadwayRoot()`, so the Broadway showcase renders with no `BContext` and `@Environment(\.bContext)` falls back; `Tests/BroadwayCatalogTests.swift:4` is `struct BroadwayCatalogTests {}` — an empty suite wired into the `Stuff-iOS-Tests` scheme.

**Low:** `README.md` promises a "living catalog" the placeholder `ContentView` doesn't provide; hardcoded English (accepted for an internal showcase).

**Files:** 2/1 · README ✓ · AGENTS ✓

---

### RegionKit & RegionViewer (5 open)

**RegionKit medium:** no `GeoJSONTests.swift` — the unsupported-geometry throw (`GeoJSON.swift:62`) and malformed-coordinate drop (`:124`) are untested; `RegionCatalog.loadFromBundle()`'s degrade-to-empty behavior (`RegionCatalog.swift:98`) is asserted only at the log-event level in `RegionLogTests`. **Low:** `RegionCatalog.swift:65` uses a raw `String(localized: "region.other")` rather than a generated symbol; `README.md:144` claims GeoJSON decoding is covered.

**RegionViewer low:** `RegionViewerApp.swift:15` omits `.whereBroadwayRoot()`, so the map uses default styling; `README.md:14` describes a monolithic `us-states.geojson` and a hand-listed region set, while `RegionMapView` uses `RegionAttributor.all` over the per-region catalog. No test bundle by design.

**Files:** RegionKit 13/8 · RegionViewer 1/0 · README ✓ · AGENTS ✓

---

### WhereIntents (6 open)

**Medium:** the per-intent `perform()` glue (guards, snippet wiring, error→dialog mapping) is untested — by design, since `@Dependency` traps outside the perform flow, so the fix is either a thin extracted seam or a `README.md` sentence saying so.

**Low:** `LogTripIntent` is missing from `WhereShortcuts` (`WhereShortcuts.swift:11` registers five); `LogDayIntent.swift:39` defaults to `Date()` instead of `Calendar.whereIntents` (no data impact — `DayJournal` buckets Gregorian); `WhereIntentReader.swift:17` swallows an App Group open failure in `try?`; `RegionSpotlightIndexer` and `WhereIntentReader.recentActivity` have no tests.

**Verified OK:** reader/writer seams well tested (`WhereIntentReaderTests`, `WhereIntentWriterTests`); `IntentServices` handoff still covered by `IntentServicesTests` (install/park/cancel/replace) with no self-creating fallback; no Broadway double-link.

**Files:** 17/9 · README ✓ · AGENTS ✓

---

### WhereWidgets & WhereShareExtension (5 open)

**WhereWidgets medium:** `WhereWidgetProvider.swift:36`'s midnight reload policy — the extension's core scheduling logic — has no test in any target. **Low:** no test bundle (documented). The post-midnight stale snapshot is now explicitly documented as intentional degradation in the provider, `README.md`, and `AGENTS.md`.

**WhereShareExtension medium:** `ShareEvidenceModel.buildPendingEvidence()` is exposed for testing with no bundle to test it; `ShareEvidenceView.swift:65` and `AddEvidenceView.swift:85` remain parallel implementations over parallel catalog namespaces (`share.form.*` / `evidence.form.*`). **Low:** `SharedItemLoader.swift:80` discards the provider `error` (only nil-data logs); `AGENTS.md:21` credits the write path to "the WhereUI compose model" when production uses this target's `ShareEvidenceModel`.

**Verified OK:** `SharedItemLoader` logs load failures at `warning`; widget gallery strings localized; `@unknown default:` on widget-family switches; no Broadway double-link in either target.

**Files:** WhereWidgets 7/0 · WhereShareExtension 5/0 · README ✓ · AGENTS ✓

---

### Where app (0 open)

**Verified OK:** `Where/Where/README.md` now exists and matches the three-file shell; `WhereTests` pins `.undetermined` as the launch reason under the UIScene lifecycle; delegate wiring smoke test; no Broadway double-link.

**Files:** 3/1 · README ✓ · AGENTS ✓

---

## Limitations

- Static analysis only — no `tuist test`, `bumper lint`, or simulator runs in this pass (the Cloud agent runs Linux; the full suite requires macOS CI). CI status on `main` was read via `gh` and is green, which is what lets the "the Gregorian rule finds nothing" conclusion stand.
- Some findings (the LifecycleKit terminal-phase race, the tracking toggle, outbox relaunch loss) need runtime confirmation.
- Severity counts are approximate — several low-severity 1:1 test gaps are folded into module summaries rather than listed individually.
- DEBUG-only surfaces (PeriscopeTools, SwiftDataInspector) are held to a lighter standard for `try?` degradation, per their module docs.
- `Shared/Periscope/Prototypes/JournalBenchmark` (2 sources) is wired into no target and is excluded from the counts below.

---

## Modules reviewed

### SPM library targets

| Module | Path | Source | Test | README | AGENTS |
|--------|------|-------:|-----:|:------:|:------:|
| StuffCore | `Shared/StuffCore/` | 1 | 1 | ✓ | ✓ |
| LifecycleKit | `Shared/LifecycleKit/` | 9 | 11 | ✓ | ✓ |
| JournalKit | `Shared/JournalKit/` | 2 | 3 | ✓ | ✓ |
| PeriscopeCore | `Shared/Periscope/PeriscopeCore/` | 35 | 31 | ✓ | ✓ |
| PeriscopeUI | `Shared/Periscope/PeriscopeUI/` | 1 | 2 | ✓ | ✓ |
| PeriscopeTools | `Shared/Periscope/PeriscopeTools/` | 24 | 22 | ✓ | ✓ |
| SwiftDataInspector | `Shared/SwiftDataInspector/` | 13 | 1 | ✓ | ✓ |
| TestHostSupport | `Shared/TestHostSupport/` | 1 | 0 | ✓ | ✓ |
| BroadwayCore | `Shared/Broadway/BroadwayCore/` | 17 | 10 | ✓ | ✓ |
| BroadwayUI | `Shared/Broadway/BroadwayUI/` | 6 | 4 | ✓ | ✓ |
| RegionKit | `Where/RegionKit/` | 13 | 8 | ✓ | ✓ |
| WhereCore | `Where/WhereCore/` | 87 | 58 | ✓ | ✓ |
| WhereUI | `Where/WhereUI/` | 113 | 36 | ✓ | ✓ |
| WhereIntents | `Where/WhereIntents/` | 17 | 9 | ✓ | ✓ |

### Tuist app / extension targets

| Target | Path | Source | Test | README | AGENTS |
|--------|------|-------:|-----:|:------:|:------:|
| Where | `Where/Where/` | 3 | 1 | ✓ | ✓ |
| WhereWidgets | `Where/WhereWidgets/` | 7 | 0 | ✓ | ✓ |
| WhereShareExtension | `Where/WhereShareExtension/` | 5 | 0 | ✓ | ✓ |
| RegionViewer | `Where/RegionViewer/` | 1 | 0 | ✓ | ✓ |
| StuffTestHost | `Shared/StuffTestHost/` | 2 | 0 | ✓ | ✓ |
| BroadwayCatalog | `Shared/Broadway/BroadwayCatalog/` | 2 | 1 | ✓ | ✓ |

**Totals:** ~359 source · ~198 test Swift files across shipped targets (plus 4 Bumper rule/test sources and 2 unwired prototype sources).

---

## Changes since July 19, 2026 audit

| Area | July 19 state | July 26 state |
|------|---------------|---------------|
| Target count | 16 SPM + 6 Tuist | **14 SPM** + 6 Tuist — LogKit and LogViewerUI deleted, replaced by Periscope (#94) |
| File count | ~308 source / ~189 test | ~359 source / ~198 test (WhereUI 84 → 113, WhereCore 70 → 87, PeriscopeTools 15 → 24, RegionKit 9 → 13) |
| Architecture lint | — | Bumper Bowling (#127): Where component graph + 10 source-level rules, hard-gated in CI — with a Gregorian blind spot and a stale catalog |
| Navigation | Primary / Elsewhere / Resolve / Settings | Locations / Your Year / Settings (#119); Elsewhere is a card, Resolve a toolbar action, data screens under Settings |
| Settings | Flat list | iOS-style drill-in screens with search (#111) |
| Developer surfaces | LogViewerUI + overlay | Liquid Glass HUD (#115), Periscope viewer with hierarchy / span tree / span history / density (#107), in-app SwiftData browser |
| Launch reason | `applicationState` guess (cold launch read as headless) | `LifecycleReason.undetermined` + promotion, with `completedStepIDs` preventing re-runs (#109) |
| Localization | Hand-maintained key facades | Generated String Catalog symbols; a removed key is a compile error (#124); catalogs serialized as Xcode writes them and linted (#135) |
| Calendars | `Calendar.current` in view call sites | Fixed at the call sites (`fe99dde`) — but relocated into `CalendarDay.displayDate` and two helper defaults |
| Preview coverage | Gaps across WhereUI | Complete; enforced by `where.preview_coverage` (`52f0136`) |
| Simulator handling | Name-based destinations | `./simulator` resolves a UDID and boots it; `profile` / `flaky` / CI all go through it (#130) |
| Device installs | Xcode UI | `./Where/install` (#110, #112) |
