# Swift Module Audit Report

Read-only review of all **15 SPM library targets**, **6 Tuist app/extension targets**, and the **BroadwayCatalog** showcase app (~308 source / ~189 test Swift files). No code was changed.

**Date:** July 19, 2026  
**Method:** Read-only spot-check of July 17 findings against current source; file-count refresh; new-surface review (region-picking PR #95).  
**Prior audit:** July 17, 2026 (~298 source / ~182 test).  
**Follow-ups:** See [TODO](#todo) for actionable checklist items.

---

## Executive summary

| Severity | Count |
|----------|------:|
| Critical | 0 |
| High | 3 |
| Medium | 39 |
| Low | 51 |
| **Total** | **93** |

| Category | Count |
|----------|------:|
| bug | 14 |
| test | 28 |
| convention | 22 |
| performance | 12 |
| duplication | 10 |
| localization | 5 |
| docs | 2 |

**Overall:** The codebase has roughly doubled in size since the June audit and gained substantial new surface area (Broadway, Periscope, RegionKit, WhereIntents, share extension, TestHostSupport, region-picking onboarding). Most June/July quick-wins landed — backup import reconciliation, `IntentServices` handoff tests, scene-scoped `YearReportModel` (closing the headless `observeDataChanges` leak), LogViewerUI caching, SwiftDataInspector pagination, TestHostSupport split, module docs, and many convention fixes are done. The strongest **remaining** themes are **daily-summary notification staleness** after data changes, the **tracking-toggle race** in WhereUI, a **residual LifecycleKit phase race** during `minVisible` cancellation, **`setPrimaryRegions` skipping the reconcile fan-out** after picker commits, and **thin test coverage** on several extension/app shells and glue files.

---

## Top 10 highest-impact findings

| # | Sev | Module | Issue |
|---|-----|--------|-------|
| 1 | **high** | WhereCore | `DailySummaryReconciler.reconcile()` is never called from GPS ingest, journal writes, or backup import — notification body can stay stale until foreground re-`configure` |
| 2 | **high** | WhereUI | Tracking toggle race — rapid on/off spawns unserialized `Task`s; slow `startTracking()` can finish after a later `stopTracking()` |
| 3 | **high** | LifecycleKit | Residual cancel-during-`minVisible` race — superseded drive can still reach `.ready` before the new drive completes |
| 4 | **medium** | WhereCore | `DayJournal.ingest(_:)` / bulk ingest paths publish widgets but skip reminder/issue reconcile (test/bulk paths only; live GPS goes through `LocationIngestor`) |
| 5 | **medium** | WhereCore | `setPrimaryRegions(_:)` commits atomically but skips `reconcileAfterDayChange()` — widgets/reminders/summary not refreshed until foreground/configure |
| 6 | **medium** | PeriscopeCore | Multi-process journal ingest race when app and extension share a store — tracked in `Shared/Periscope/TODOs.md` |
| 7 | **medium** | WhereIntents | Individual `AppIntent.perform()` bodies untested despite README implying intent-level coverage (`IntentServices` handoff is now tested) |
| 8 | **medium** | WhereShareExtension | `ShareEvidenceModel.buildPendingEvidence()` is testable but has no test bundle |
| 9 | **medium** | RegionKit | `GeoJSON` decoder paths (unsupported geometry, malformed coordinates) untested |
| 10 | **medium** | WhereUI | Duplicated load-state UI across Primary / Secondary / Calendar tabs — no shared `ReportLoadGate` |

---

## Cross-cutting themes

### Reconciliation mostly unified (WhereCore)

Since June, backup import and day-mutating writes funnel through `DayJournal.reconcileAfterDayChange()` → scanner invalidate, reminders, issue alerts, widgets. **Daily summary** remains the outlier — it only refreshes on launch/foreground `configure` and settings edits, not on data changes. **`setPrimaryRegions(_:)`** (region-picker commit) is a new gap: it pings `changes()` but does not call the reconcile fan-out.

### Extension/app targets defer tests to libraries

WhereWidgets, WhereShareExtension, RegionViewer, and BroadwayCatalog intentionally have no (or minimal) test bundles. Behavior is covered in WhereCore/WhereUI where possible, but ShareEvidenceModel and BroadwayCatalog are gaps relative to that pattern.

### Scene-scoped presentation models (WhereUI)

`YearReportModel` is now owned by `MainTabs` and subscribes to store changes only while the scene is active (`activate()` / `deactivate()` on `scenePhase`). This closes the headless-relaunch rescan leak that previously wired `observeDataChanges()` through the launch sequence. The `WhereSession` coordinator is slimmer (~460 lines) but still mixes always-on concerns with some presentation mirrors — full split tracked in `Where/TODOs.md`.

### Broadway duplicate-linking discipline

WhereWidgets, WhereIntents snippets, and the main app reach Broadway only through WhereUI (`whereBroadwayRoot()`). RegionViewer and ShareExtension omit it (fallback/default styling) — acceptable for dev/share surfaces today.

### Localization architecture is consistent

Module-owned `Localizable.xcstrings` resolved through Xcode's generated `LocalizedStringResource` symbols (`STRING_CATALOG_GENERATE_SYMBOLS`); composition/plural/switch logic lives in small helpers (`WhereFormat`, `IntentStrings`). RegionKit dynamic region names are the deliberate exception (data-driven catalog).

### 1:1 test-file convention holds for libraries, slips for glue

PeriscopeTools row components, RegionKit GeoJSON, Broadway UIKit helpers, WhereIntents `perform()` bodies, and several WhereCore sources lack namesake test files — coverage often exists via integration suites instead.

### Infrastructure is in good shape

LifecycleKit cancel-and-drain during `minVisible` **hang** is fixed; LogViewerUI caching fixed; SwiftDataInspector pagination/lazy rendering fixed; WhereTesting split into dependency-free `TestHostSupport` + `@_spi(Testing) InMemoryKeyValueStore` in WhereCore; all library targets now ship `README.md` + `AGENTS.md`.

### Evidence compose duplication

Share extension and in-app add-evidence flows share domain (`Evidence.composed`) but duplicate form layout and parallel string keys (`share.form.*` vs `evidence.form.*`).

---

## Quick wins vs needs design

Summary buckets — every open TODO below is tagged **`quick-win`** or **`needs-design`**.

### Quick wins (localized, low-risk)

- Add `DailySummaryReconciler.reconcile()` to the unified post-day-change fan-out + regression test
- Route `setPrimaryRegions(_:)` through `reconcileAfterDayChange()` (or document why picker commits defer)
- Add LifecycleKit regression test for superseding drive during `minVisible` hold
- Add SwiftDataInspector test for bare `PersistentIdentifier` relationship slots
- Add `GeoJSONTests.swift` with malformed/unsupported fixture snippets
- Add `ShareEvidenceModelTests` with in-memory storage
- Replace `waitForOneRunloop()` in UI tests with predicate polling
- Fix `Calendar.current` usage in WhereUI year/day math (use report calendar)
- Log `SharedItemLoader` load failures at `warning` — *done (July 19 spot-check)*
- Add `Where/Where/README.md` pointing at feature docs

### Needs design / broader refactor

- Serialize **WhereSession** tracking mutations
- Fix **LifecycleKit** residual `.ready` race after cancel during `minVisible`
- Unify **daily summary** into `reconcileAfterDayChange()` policy (or document intentional deferral)
- Incremental year-report reads for widget/reminder/summary hot paths
- Extract shared **ReportLoadGate** and manual/relabel form component
- **Periscope** multi-process journal coordination before more extensions journal
- **WhereSession** / **YearReportModel** split (tracked in `Where/TODOs.md`)
- Per-entity schema versioning (tracked in `Where/TODOs.md`)
- ShareEvidence vs AddEvidence form consolidation

---

## TODO

Actionable follow-ups from this audit. Items marked `[x]` were open in the June audit and are now verified fixed.

| Tag | Meaning |
|-----|---------|
| **Severity** | `high` / `medium` / `low` — impact from this audit |
| **quick-win** | Localized, low-risk; can land in a small PR |
| **needs-design** | Broader refactor, policy choice, or cross-module contract |

### High priority

- [ ] **WhereCore** — Route `setPrimaryRegions(_:)` through `reconcileAfterDayChange()` after picker commits (**medium**, bug, **needs-design** — new since PR #95)
- [ ] **WhereCore** — Call `DailySummaryReconciler.reconcile()` from the unified post-day-change fan-out (GPS ingest hook, `reconcileAfterDayChange()`, backup `onImport`) (**high**, bug, **needs-design** — extend fan-out vs. document foreground-only policy)
- [ ] **WhereCore** — Add test: mutate data → summary notification body updates without re-`configure` (**high**, test, **quick-win** — pairs with item above)
- [ ] **WhereUI** — Serialize `WhereSession.trackingEnabled` mutations (cancel/coalesce in-flight start/stop tasks) (**high**, bug, **needs-design**)
- [ ] **WhereUI** — Split toggle binding: `wantsTracking` for intent vs `isTracking` for effective GPS state (**high**, bug, **needs-design** — pairs with tracking serialization)
- [ ] **LifecycleKit** — After cancel during `minVisible`, check `Task.isCancelled` in `runStep`/`hold()` so superseded drive cannot set `phase = .ready` (**high**, bug, **needs-design**)
- [ ] **LifecycleKit** — Add test superseding drive during `minVisible` (teardown/enterForeground while hold is active) (**high**, test, **quick-win**)

### Medium priority — WhereCore

- [ ] **WhereCore** — Route `DayJournal.ingest` paths through reminder reconcile when ingest changes presence (**medium**, bug, **needs-design**)
- [ ] **WhereCore** — Handle durable outbox save failure without silent sample loss on relaunch (**medium**, bug, **needs-design**)
- [ ] **WhereCore** — Review retry-queue capacity policy / user-visible degradation at eviction (**medium**, bug, **needs-design**)
- [ ] **WhereCore** — Consider incremental year-report reads or memoization for widget/reminder/summary hot paths (**medium**, performance, **needs-design**)
- [x] **WhereCore** — Reconcile reminders, badge, and widgets after `BackupCoordinator.importBackup` (**medium**, bug) — *fixed via `onImport` → `reconcileAfterDayChange()`*
- [x] **WhereCore** — Fix `DailySummaryReconciler.summaryFragment` format args (**high**, localization, **quick-win**)
- [x] **WhereCore** — Localize `BackupError.errorDescription` (**medium**, localization, **quick-win**)
- [x] **WhereCore** — Skip full `reminders.reconcile()` on drain-only ingest with empty `changedDays` (**medium**, performance, **quick-win**)

### Medium priority — WhereUI

- [ ] **WhereUI** — Extract shared `ReportLoadGate` for duplicated load-state UI across tabs (**medium**, duplication, **needs-design**)
- [ ] **WhereUI** — Extract shared region-selection form logic from `ManualDayView` / `DayRelabelView` (**medium**, duplication, **needs-design** — partial: shared subviews exist)
- [ ] **WhereUI** — Batch or cap concurrent geocoding in `RegionDaysView` day rows (**medium**, performance, **needs-design**)
- [ ] **WhereUI** — Make `SecondaryView.loadPlaceNames()` cancellation-aware (generation token / `.task(id:)`) (**medium**, bug, **needs-design** — partially mitigated: `.task(id: report.report)` + post-geocode `Task.isCancelled` guard; `LocationNamer` still not cancellation-aware)
- [ ] **WhereUI** — Replace `Calendar.current` with report/injected Gregorian calendar in year/day math (**medium**, convention, **quick-win**)
- [ ] **WhereUI** — Remove `waitForOneRunloop()` from UI tests (**medium**, test, **quick-win** — also in `Where/TODOs.md` P0)
- [x] **WhereUI** — Replace closure `Binding(get:set:)` save-error alerts (**medium**, convention, **quick-win**)
- [x] **WhereUI** — Enumerate all load-state cases (remove bare `default:`) (**medium**, convention, **quick-win**)
- [x] **WhereUI** — Scene-scoped data refresh via `YearReportModel.activate()` / `deactivate()` (**medium**, bug, **needs-design**)

### Medium priority — LifecycleKit, SwiftDataInspector, extensions

- [ ] **SwiftDataInspector** — Add test for bare `PersistentIdentifier` to-one relationship resolution (**medium**, test, **quick-win**)
- [ ] **SwiftDataInspector** — Split monolithic test file; optional hosted UI smoke tests (**medium**, test, **needs-design**)
- [ ] **WhereIntents** — Add `perform()` tests per intent or update README to reflect seam-only coverage (**medium**, test, **quick-win**)
- [x] **WhereIntents** — Test `IntentServices` process-wide cache (**medium**, test, **quick-win**) — *`IntentServicesTests.swift` covers install/park/cancel/replace*
- [ ] **WhereShareExtension** — Add `ShareEvidenceModelTests` (**medium**, test, **quick-win**)
- [x] **WhereShareExtension** — Log `SharedItemLoader` load failures at `warning` (**low**, convention, **quick-win**)
- [ ] **RegionKit** — Add `GeoJSONTests.swift` (**medium**, test, **quick-win**)
- [ ] **BroadwayUI** — Fix nested `BRootViewController` duplicate trait observers (**medium**, bug, **needs-design** — latent; not used in Where today)
- [ ] **PeriscopeCore** — Multi-process journal ingest coordination (**medium**, bug, **needs-design** — see `Shared/Periscope/TODOs.md`)
- [x] **SwiftDataInspector** — Resolve bare `PersistentIdentifier` to-one relationships (**high**, bug, **quick-win**)
- [x] **SwiftDataInspector** — Paginate/lazy-render `EntityTableView` (**high**, performance, **quick-win**)
- [x] **LifecycleKit** — Localize `LifecycleFailureView` via module catalog (**medium**, localization, **quick-win**)

### Medium priority — Where app & widgets

- [ ] **WhereWidgets** — Optional unit test for timeline/midnight policy with injectable store (**medium**, test, **needs-design**)
- [ ] **WhereWidgets** — Handle stale snapshot after midnight in provider or document UI graceful degradation (**medium**, bug, **needs-design** — product decision)
- [x] **Where app** — Add module-level `Where/Where/README.md` (**medium**, docs, **quick-win**) — *added alongside `Where/Where/AGENTS.md`*
- [x] **Where app** — Replace placeholder `WhereTests` with launch-reason smoke tests (**medium**, test, **quick-win**)
- [x] **WhereWidgets** — Add `README.md` and `AGENTS.md` (**medium**, convention, **quick-win**)
- [x] **WhereWidgets** — Localize widget gallery strings (**medium**, localization, **quick-win**)

### Low priority / polish

- [ ] **WhereCore** — Soft-delete for untracked regions when region picker ships (**low**, bug, **needs-design** — open TODO in `SwiftDataStore`)
- [ ] **WhereUI** — Profile `RegionSummaryCard` Canvas rosette (**low**, performance, **needs-design**)
- [ ] **WhereUI** — Log AppIcon catalog load failures (**low**, convention, **quick-win**)
- [ ] **WhereIntents** — Register `LogTripIntent` in `WhereShortcuts` or document Shortcuts-only discovery (**low**, convention, **quick-win**)
- [ ] **RegionViewer** — Wrap `RegionMapView` in `.whereBroadwayRoot()` for faithful dev styling (**low**, convention, **quick-win**)
- [ ] **BroadwayCatalog** — Add launch smoke test or document empty-test intent (**low**, test, **quick-win**)
- [ ] **StuffTestHost** — Document or split WhereCore-always-embedded build trade-off (**low**, performance, **needs-design**)
- [ ] **StuffCore** — Replace tautological `version` test when real API exists (**low**, test, **quick-win**)
- [ ] **Where/TODOs.md** — Track architectural items: `WhereSession` split, `YearReportModel` split, per-entity schema versioning (**low**, docs)

### Summary by effort

| Effort | Open | Done (since June) |
|--------|-----:|------------------:|
| **quick-win** | ~17 | ~92 |
| **needs-design** | ~23 | ~10 |

Filter tips: search `quick-win` for bite-sized PRs; search `needs-design` for items to discuss or spec before coding.

---

## Per-module findings

### WhereCore (13 open / many fixed)

**High**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `WhereServices.swift` — `onPersisted`; `DayJournal.reconcileAfterDayChange()` | Daily summary notification never reconciled on data changes | Add `await summary.reconcile()` to unified fan-out; test without re-`configure` |

**Medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `WhereServices.setPrimaryRegions(_:)` | Picker commit pings `changes()` but skips reminder/widget/summary reconcile | Route through `reconcileAfterDayChange()` or document deferral |
| bug | `DayJournal.swift` — `ingest(_:)`, bulk ingest | Widget publish without reminder/issue reconcile | Route through reconcile or document test-only scope |
| bug | `LocationOutbox.swift` — `save(_:)` | Outbox save failure → relaunch sample loss | Degraded-state handling + relaunch test |
| bug | `LocationIngestor.swift` — retry queue eviction | Silent drop at capacity with warning only | User-visible degradation or policy doc |
| performance | `WidgetDataReader` / `ReportReader.yearReport` | Full-year re-aggregation on hot paths | Memoize or incremental reads |
| convention | `DayJournal.addEvidence` | Default parameter on Core API | Remove default; explicit call sites |
| test | Import/summary integration | No test for summary refresh after import/ingest | Spy scheduler test |

**Low**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `SwiftDataStore.setTrackedRegion(false)` | Untrack deletes row; past-year re-attribution risk | Soft-delete when picker ships |
| convention | `WidgetSnapshotStore.read()` | `try?` hides decode failures | Log at `warning` on app write path |
| test | ~68 source files | Strict 1:1 test mapping not followed | Integration suites cover most paths; document or split |

**Verified OK:** Backup import → reminders/badge/widgets via `reconcileAfterDayChange`; GPS ingest → throttled reminder reconcile; summary format strings; `BackupError` localization; `WhereStore.perform` boundary; enum switches with `@unknown default`; post-write fan-out single owner in `DayJournal`.

**Files:** 70 source / 57 test · README ✓ · AGENTS ✓

---

### WhereUI (10 open / many fixed)

**High**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `WhereSession.swift` — `trackingEnabled` setter | Unserialized async start/stop tasks | Serialize mutations; split intent vs effective state |

**Medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| duplication | `PrimaryView`, `SecondaryView`, `CalendarView` | Duplicated load-state UI | Extract `ReportLoadGate` |
| duplication | `ManualDayView`, `DayRelabelView` | Parallel form chrome despite shared subviews | Shared form model or subview |
| convention | `ManualDayView`, `PresenceTimelineView`, `RegionSummaryCard` | `Calendar.current` for year/day math | Use report Gregorian calendar |
| performance | `RegionDaysView` — `DayRow` | Per-row geocode `.task` | Prefetch unique coordinates |
| bug | `SecondaryView.loadPlaceNames()` | Stale geocode after year switch | Partially mitigated (`.task(id:)` + cancel guard); `LocationNamer` still not cancellation-aware |
| test | UI tests | `waitForOneRunloop()` flake risk | Predicate polling |

**Low**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| convention | `AppIconOption` / `AppIconModel` | Silent empty picker on catalog load failure | Log + honest empty state |
| performance | `RegionSummaryCard` Canvas | Many concentric rings | Profile before optimizing |
| localization | `IntentSnippets` preview button | Hardcoded English in snippet preview | Route through a catalog symbol if shipped |

**Verified OK:** `SaveErrorAlertState` replaces closure bindings; `YearReportModel.LoadState` modeling; scene-scoped refresh; `#Preview` coverage; `ScreenHostingTests` for manual/relabel; Core logic stays in models/services.

**Files:** 84 source / 35 test · README ✓ · AGENTS ✓

---

### LifecycleKit (2 open / cancel hang fixed)

**High / medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `LifecycleRunner.runStep` → `ActivePresentation.hold()` | Cancel during `minVisible` can still return `.completed`; superseded drive may set `.ready` | Check `Task.isCancelled` after hold; gate terminal phase on active drive |
| test | `LifecycleRunnerTests` | No supersede-during-hold regression | Add teardown/enterForeground mid-hold test |

**Verified OK:** Cancel-and-drain no longer blocks full `minVisible` window; fuzz tests; duplicate step ID fail-fast; module localization; background→foreground container test.

**Files:** 9 source / 10 test · README ✓ · AGENTS ✓

---

### SwiftDataInspector (2 open / scalability fixed)

**Medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| test | `SwiftDataReflection.classify` | Bare `PersistentIdentifier` path untested | Add fixture test |
| test | `Tests/` | Single omnibus file vs 13 sources | Split by concern; optional hosted smoke |

**Low:** Client-side search over loaded prefix only; unstable row order by design; `try?` on fetch yields empty (acceptable for DEBUG tool).

**Verified OK:** Pagination + lazy rendering; relationship resolution for materialized models; AGENTS scenarios largely tested at reader layer.

**Files:** 13 source / 1 test · README ✓ · AGENTS ✓

---

### LogKit & LogViewerUI (0 open)

**Verified OK (all June findings addressed):** `LogStore.changes()` race fixed; cancellation/multi-observer tests; `LogViewerModel` filtered-entry and category caching; search uses display names; empty-filter vs store-empty distinction; deferred export; hosting tests strengthened.

**Files:** LogKit 4/3 · LogViewerUI 4/2 · README ✓ · AGENTS ✓

---

### JournalKit, StuffCore, TestHostSupport, StuffTestHost (0–1 open each)

**JournalKit:** Strong fuzz/truncation coverage. Low: concurrent append test uses `try?`; `.full` sync lightly exercised. **Files:** 2/3 · README ✓ · AGENTS ✓

**StuffCore:** Intentional scaffold; tautological version test. **Files:** 1/1 · README ✓ · AGENTS ✓

**TestHostSupport:** Dependency-free UIKit helpers; no dedicated bundle (by design). **Files:** 1/0 · README ✓ · AGENTS ✓

**StuffTestHost:** WhereCore embed trade-off documented; smoke test in LifecycleKit. Low: scene plist duplication. **Files:** 2/0 · README ✓ · AGENTS ✓

---

### BroadwayCore & BroadwayUI (3 open)

**Medium:** Nested `BRootViewController` duplicate trait observers (latent). **Low:** Missing 1:1 tests for `UIViewControllerTraitObserver`, `EquatableIgnored`, `BTraitOverrides+SwiftUI`; stylesheet cache never evicts on memory pressure (documented TODO).

**Verified OK:** Stylesheet/trait/cycle behavior well tested; Where uses SwiftUI `whereBroadwayRoot()` entry point.

**Files:** BroadwayCore 17/10 · BroadwayUI 6/4 · README ✓ · AGENTS ✓

---

### BroadwayCatalog (2 open)

**Medium:** Empty test struct. **Low:** Placeholder UI vs README promise; hardcoded English (acceptable for internal showcase).

**Files:** 2/1 · README ✓ · AGENTS ✓

---

### PeriscopeCore, PeriscopeUI, PeriscopeTools (4 open)

**PeriscopeCore medium:** Multi-process journal ingest race (P1 in `Shared/Periscope/TODOs.md`); orphan sweep `try?` decode may close surviving span. **Low:** Fixed `Task.sleep` in tests; strong overall coverage (34/31).

**PeriscopeUI:** Thin DEBUG bridge — no issues. **Files:** 1/2 · README ✓ · AGENTS ✓

**PeriscopeTools low:** Row/display components untested; NDJSON export `try?` acceptable for dev tool. **Files:** 15/13 · README ✓ · AGENTS ✓

---

### RegionKit & RegionViewer (3 open)

**RegionKit medium:** `GeoJSON.swift` decoder untested. **Low:** Catalog load failure paths; dynamic localization trade-off documented.

**RegionViewer low:** Missing `.whereBroadwayRoot()` — map uses default stylesheet; no test bundle by design.

**Files:** RegionKit 9/6 · RegionViewer 1/0 · README ✓ · AGENTS ✓

---

### WhereIntents (4 open)

**Medium:** No `perform()` tests. **Low:** `LogTripIntent` not in shortcuts provider; `LogDayIntent` default day uses `Date()` vs calendar consistency; Spotlight indexer untested.

**Verified OK:** Reader/writer seams well tested; `IntentServices` handoff (`IntentServicesTests`); duplicate-linking discipline via WhereUI only.

**Files:** 16/9 · README ✓ · AGENTS ✓

---

### WhereWidgets & WhereShareExtension (3 open)

**WhereWidgets low:** No extension test bundle (documented); midnight stale snapshot policy; provider timeline untested at boundary.

**WhereShareExtension medium:** `ShareEvidenceModel` untested. **Low:** form duplication vs `AddEvidenceView`.

**Verified OK:** `SharedItemLoader` logs load failures at `warning`; gallery strings localized; widget rendering tested in WhereUI; App Group read path aligned with Core publisher.

**Files:** WhereWidgets 7/0 · WhereShareExtension 5/0 · README ✓ · AGENTS ✓

---

### Where app (1 open)

**Low:** No `Where/Where/README.md` (feature-level `Where/AGENTS.md` covers layering).

**Verified OK:** Launch-reason mapping tested; thin shell (`WhereApp`, `AppDelegate`, `WhereShortcuts`); delegate wiring smoke test.

**Files:** 3/1 · README ✗ · AGENTS ✗ (feature doc at `Where/AGENTS.md`)

---

## Limitations

- Static analysis only — no `tuist test` or simulator runs in this pass (Cloud agent runs Linux; full test suite requires macOS CI).
- Some findings (LifecycleKit phase race, tracking toggle, outbox relaunch) need runtime confirmation.
- Severity counts are approximate — several low-severity 1:1 test gaps are folded into module summaries rather than individually listed.
- DEBUG-only localization (LogViewerUI, PeriscopeUI) flagged at low severity per module docs.

---

## Modules reviewed

### SPM library targets

| Module | Path | Source | Test | README | AGENTS |
|--------|------|-------:|-----:|:------:|:------:|
| StuffCore | `Shared/StuffCore/` | 1 | 1 | ✓ | ✓ |
| LifecycleKit | `Shared/LifecycleKit/` | 9 | 10 | ✓ | ✓ |
| JournalKit | `Shared/JournalKit/` | 2 | 3 | ✓ | ✓ |
| LogKit | `Shared/LogKit/` | 4 | 3 | ✓ | ✓ |
| LogViewerUI | `Shared/LogViewerUI/` | 4 | 2 | ✓ | ✓ |
| SwiftDataInspector | `Shared/SwiftDataInspector/` | 13 | 1 | ✓ | ✓ |
| TestHostSupport | `Shared/TestHostSupport/` | 1 | 0 | ✓ | ✓ |
| BroadwayCore | `Shared/Broadway/BroadwayCore/` | 17 | 10 | ✓ | ✓ |
| BroadwayUI | `Shared/Broadway/BroadwayUI/` | 6 | 4 | ✓ | ✓ |
| PeriscopeCore | `Shared/Periscope/PeriscopeCore/` | 34 | 31 | ✓ | ✓ |
| PeriscopeUI | `Shared/Periscope/PeriscopeUI/` | 1 | 2 | ✓ | ✓ |
| PeriscopeTools | `Shared/Periscope/PeriscopeTools/` | 15 | 13 | ✓ | ✓ |
| RegionKit | `Where/RegionKit/` | 9 | 6 | ✓ | ✓ |
| WhereCore | `Where/WhereCore/` | 70 | 57 | ✓ | ✓ |
| WhereUI | `Where/WhereUI/` | 84 | 35 | ✓ | ✓ |
| WhereIntents | `Where/WhereIntents/` | 16 | 9 | ✓ | ✓ |

### Tuist app / extension targets

| Target | Path | Source | Test | README | AGENTS |
|--------|------|-------:|-----:|:------:|:------:|
| Where | `Where/Where/` | 3 | 1 | ✓ | ✓ |
| WhereWidgets | `Where/WhereWidgets/` | 7 | 0 | ✓ | ✓ |
| WhereShareExtension | `Where/WhereShareExtension/` | 5 | 0 | ✓ | ✓ |
| RegionViewer | `Where/RegionViewer/` | 1 | 0 | ✓ | ✓ |
| StuffTestHost | `Shared/StuffTestHost/` | 2 | 0 | ✓ | ✓ |
| BroadwayCatalog | `Shared/Broadway/BroadwayCatalog/` | 2 | 1 | ✓ | ✓ |

**Totals:** ~308 source · ~189 test Swift files across the tree.

---

## Changes since June 2026 audit

| Area | June state | July state |
|------|------------|------------|
| Target count | 11 | 22 (16 SPM + 6 Tuist) |
| Module docs | 4 targets missing | All libraries/extensions documented; Where app target only gap |
| WhereTesting | Monolithic; forced WhereCore link | Split → `TestHostSupport` + `@_spi(Testing) InMemoryKeyValueStore` |
| Backup import reconcile | Widgets only | Full fan-out via `reconcileAfterDayChange()` |
| Daily summary `%` placeholders | Broken | Fixed + tested |
| LogViewerUI search perf | Recomputed every keystroke | Cached |
| SwiftDataInspector table | Main-thread stall on wide schemas | Paginated + lazy |
| LifecycleKit minVisible cancel | Hung for full hold duration | Cooperative cancel; residual `.ready` race remains |
| Where app tests | Placeholder `#expect(true)` | Launch-reason smoke tests |
| New modules | — | Broadway*, Periscope*, RegionKit, WhereIntents, share extension, RegionViewer |

## Changes since July 17, 2026 audit

| Area | July 17 state | July 19 state |
|------|---------------|---------------|
| File count | ~298 source / ~182 test | ~308 source / ~189 test |
| Region picking | — | PR #95: onboarding picker, `PrimaryRegionSelectionModel`, `setPrimaryRegions` API |
| Scene-scoped refresh | `observeDataChanges()` in launch `syncAuth` | `YearReportModel.activate()` / `deactivate()` in `MainTabs` on `scenePhase` |
| `IntentServices` tests | Cache untested | `IntentServicesTests` covers install/park/cancel/replace |
| `SharedItemLoader` | Silent load failures | Logs at `warning` on failed provider loads |
| `SecondaryView` geocode | No cancellation | `.task(id: report.report)` + post-await cancel guard |
| Reconcile gap | Daily summary only | `setPrimaryRegions(_:)` also skips fan-out |
| Dev tooling | — | PR #102: `./flaky` flaky-test detector + `FLAKY_TESTS.md` |
