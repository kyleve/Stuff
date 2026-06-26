# Swift Module Audit Report

Read-only review of all **11 Swift targets** (~178 source/test files). No code was changed.

**Date:** June 23, 2026  
**Method:** One read-only Composer subagent per module; findings merged and deduplicated.  
**Follow-ups:** See [TODO](#todo) for actionable checklist items.

---

## Executive summary

| Severity | Count |
|----------|------:|
| Critical | 0 |
| High | 9 |
| Medium | 52 |
| Low | 48 |
| **Total** | **109** |

| Category | Count |
|----------|------:|
| bug | 22 |
| test | 28 |
| convention | 24 |
| performance | 15 |
| duplication | 14 |
| localization | 7 |
| formatting | 3 |

**Overall:** No critical defects found. The strongest themes are **notification/reconciliation gaps** in WhereCore, **concurrency/lifecycle edge cases** (LifecycleKit, WhereUI tracking toggle), **thin test coverage** on infrastructure modules, and **missing module docs** on several targets.

---

## Top 10 highest-impact findings

| # | Sev | Module | Issue |
|---|-----|--------|-------|
| 1 | **high** | WhereCore | Daily summary notification body may show literal `%1$@` / `%2$@` placeholders — format args never passed to `String(localized:)` |
| 2 | **high** | WhereCore | Backup import only publishes widgets; reminders, badge, and daily-summary notifications stay stale |
| 3 | **high** | LifecycleKit | Cancel-and-drain broken during `minVisible` hold — superseded drive can still reach `.ready` |
| 4 | **high** | WhereTesting | `show()` child VC lifecycle order wrong — appearance callbacks may not match UIKit contract |
| 5 | **high** | WhereTesting | Generic `show`/`waitFor` bundled with `InMemoryKeyValueStore` → every hosted test bundle links WhereCore |
| 6 | **high** | WhereUI | Tracking toggle race — rapid on/off can leave GPS running after user turns it off |
| 7 | **high** | SwiftDataInspector | To-one relationships resolving to bare `PersistentIdentifier` show empty rows |
| 8 | **high** | SwiftDataInspector | Wide schemas × many rows in `EntityTableView` can stall main thread |
| 9 | **high** | LogViewerUI | Search/filter recomputes full buffer on every keystroke |
| 10 | **medium** | WhereWidgets | After midnight, Today widget can show yesterday's regions until app republishes |

---

## Cross-cutting themes

### Missing module documentation

Four targets lack required `README.md` / `AGENTS.md`: **StuffCore**, **WhereTesting**, **WhereWidgets**, **StuffTestHost**. Several other modules reference these as contracts (hosted tests, widget refresh policy) without local docs.

### Reconciliation not wired end-to-end (WhereCore)

Three related gaps share one root cause — post-write side effects are inconsistent:

- Backup import → widgets only, not reminders/summary
- GPS ingest / some `DayJournal` paths → widgets but not `DailySummaryReconciler`
- `DayJournal.ingest` variants → no `ReminderReconciler.reconcile()`

### Localization gaps

- **WhereCore:** `BackupError` hardcoded English; daily summary format strings missing args
- **WhereUI:** DEBUG-only strings bypass `Strings.swift`
- **WhereWidgets:** Widget gallery name/description hardcoded; in-widget copy is localized
- **LifecycleKit:** `LifecycleFailureView` uses app bundle, not module catalog (tracked TODO)

### Convention violations (repo rules)

- **Bare `default:` on enums:** WhereUI `LoadState` switches; WhereWidgets `WidgetFamily` switches
- **Closure `Binding(get:set:)`:** WhereUI `ManualDayEntryView`, `DayRelabelView`
- **Test support duplication:** `iso(_:)` / `calendar()` in WhereCore tests; `waitUntil` in LifecycleKit tests; run-loop polling in LifecycleKit vs WhereTesting

### Infrastructure test gaps

- **Where** app tests are a placeholder (`#expect(true)`)
- **WhereWidgets** has no test bundle
- **SwiftDataInspector:** 11 source files, 1 test file; AGENTS.md scenarios untested
- **StuffCoreTests** missing dedicated `testScheme` in `Project.swift`

---

## Quick wins vs needs design

Summary buckets — every TODO below is tagged **`quick-win`** or **`needs-design`**. See [TODO](#todo) for the full checklist.

### Quick wins (localized, low-risk)

- Remove unused `import LogKit` in Where `AppDelegate`
- Fix `DailySummaryReconciler.summaryFragment` format args
- Add `@unknown default:` / enumerate cases in WhereUI `LoadState` and widget `WidgetFamily` switches
- Add `testScheme(name: "StuffCoreTests")` to `Project.swift`
- Log expected "no snapshot yet" as `warning` not `error` in WhereWidgets
- Cache `LogViewerModel.filteredEntries` / `categories`

### Needs design / broader refactor

- Split **WhereTesting** into UIKit-only helpers vs Where-specific store double
- Serialize **WhereSession** tracking mutations
- Fix **LifecycleKit** cancel-and-drain during `minVisible`
- Unify **WhereCore** post-write reconcile policy across all mutation paths
- **SwiftDataInspector** column virtualization / search debouncing
- **Where** launch-reason mapping + `UIBackgroundModes` for location relaunch
- Module doc pass for scaffold/infrastructure targets

---

## TODO

Actionable follow-ups from the audit.

| Tag | Meaning |
|-----|---------|
| **Severity** | `high` / `medium` / `low` — impact from the audit |
| **quick-win** | Localized, low-risk; can land in a small PR without architectural debate |
| **needs-design** | Broader refactor, policy choice, or cross-module contract — decide approach first |

### High priority

- [x] **WhereCore** — Fix `DailySummaryReconciler.summaryFragment` to pass format args for `summary.notification.regionDays` and plural `summary.notification.dayCount`; add test asserting notification body has no `%` placeholders (**high**, localization, **quick-win**)
- [ ] **WhereCore** — Reconcile reminders, badge, and daily summary after `BackupCoordinator.importBackup` (not just widgets) (**high**, bug, **needs-design** — part of unified post-write reconcile policy)
- [ ] **LifecycleKit** — Fix cancel-and-drain during `minVisible` hold in `LifecycleRunner` (treat cancellation after `hold()`, gate `.ready` on current drive) (**high**, bug, **needs-design**)
- [ ] **LifecycleKit** — Add test superseding drive during `minVisible` (teardown/enterForeground while hold is active) (**high**, test, **quick-win** — after LifecycleKit fix lands)
- [x] **WhereTesting** — Fix `show()` child VC lifecycle order (`addChild` → attach → `didMove`; reverse on teardown) (**high**, bug, **quick-win**)
- [ ] **WhereTesting** — Split UIKit-only test helpers from `InMemoryKeyValueStore` so hosted bundles need not link WhereCore (**high**, convention, **needs-design**)
- [ ] **WhereUI** — Serialize `WhereSession.trackingEnabled` mutations (cancel/coalesce in-flight start/stop tasks) (**high**, bug, **needs-design**)
- [x] **SwiftDataInspector** — Resolve to-one relationships when value is bare `PersistentIdentifier` (fall back to schema destination type) (**high**, bug, **quick-win**)
- [ ] **SwiftDataInspector** — Improve `EntityTableView` scalability for wide schemas (cap/virtualize columns or row summary drill-in) (**high**, performance, **needs-design**)
- [x] **LogViewerUI** — Cache `filteredEntries` (and invalidate on entry/filter changes) instead of recomputing on every body pass/keystroke (**high**, performance, **quick-win**)

### Medium priority — WhereCore

- [ ] Call `DailySummaryReconciler.reconcile()` from GPS ingest hook and presence-changing `DayJournal` write paths (**medium**, bug, **needs-design** — part of unified post-write reconcile policy)
- [ ] Call `ReminderReconciler.reconcile()` from `DayJournal.ingest` / `addManualSample` paths that change presence (**medium**, bug, **needs-design** — part of unified post-write reconcile policy)
- [x] Skip full `reminders.reconcile()` on `LocationIngestor.start()` when drain yields empty `changedDays` (**medium**, performance, **quick-win**)
- [ ] Consider incremental year-report reads or memoization for widget/reminder hot paths (**medium**, performance, **needs-design**)
- [x] Localize `BackupError.errorDescription` strings in `Localizable.xcstrings` (**medium**, localization, **quick-win**)
- [ ] Handle durable outbox save failure without silent sample loss on relaunch (**medium**, bug, **needs-design**)
- [ ] Review retry-queue capacity policy / user-visible degradation at 1000-sample eviction (**medium**, bug, **needs-design**)
- [x] Remove raw `Date` values from production log messages in `DayJournal` / `WidgetSnapshotPublisher` (**medium**, convention, **quick-win**)
- [x] Add test for retry-queue FIFO eviction at capacity 1000 (**low**, test, **quick-win**)
- [ ] Add tests for post-import reconcile and summary body updates without re-`configure` (**low**, test, **quick-win**)
- [x] Break ties deterministically in `DayAggregator.representativeCoordinates` (**low**, bug, **quick-win**)
- [x] Fix `SDLocationSample.toValue()` corrupt `sourceRaw` handling (prefer fault or `.unknown`) (**low**, bug, **quick-win**)
- [x] Consolidate duplicated `iso(_:)` / `calendar()` test helpers into shared WhereCore test support (**low**, duplication, **quick-win**)
- [x] Replace bare `default:` in `LoggingReminderSchedulerTests` fake with explicit cases + `@unknown default` (**low**, convention, **quick-win**)

### Medium priority — WhereUI

- [x] Replace closure `Binding(get:set:)` save-error alerts in `ManualDayEntryView` and `DayRelabelView` with computed properties (**medium**, convention, **quick-win**)
- [x] Replace closure `binding(for:)` region toggles with observable bindable state (**medium**, convention, **quick-win**)
- [x] Enumerate all `WhereSession.LoadState` cases in `PrimaryView` / `SecondaryView` (remove bare `default:`) (**medium**, convention, **quick-win**)
- [x] Add `#Preview` for `AppIconImage` and elsewhere-only `PrimaryView` state (**medium**, convention, **quick-win**)
- [x] Add DEBUG SwiftData Inspector strings to catalog and `Strings.swift` (**medium**, localization, **quick-win**)
- [ ] Extract shared `ReportLoadGate` for duplicated load-state UI across tabs (**medium**, duplication, **needs-design**)
- [ ] Extract shared region-selection form logic from `ManualDayEntryView` / `DayRelabelView` (**medium**, duplication, **needs-design**)
- [ ] Batch or cap concurrent geocoding in `RegionDaysView` day rows (**medium**, performance, **needs-design**)
- [x] Add `ScreenHostingTests` coverage for `ManualDayEntryView` (default and prefill modes) (**medium**, test, **quick-win**)

### Medium priority — LifecycleKit

- [ ] Extend fuzz tests to cover interactive steps, cancel-and-drain, `enterForeground`, and teardown (**medium**, test, **needs-design**)
- [x] Localize `LifecycleFailureView` via module string catalog + `bundle: .module` (**medium**, localization, **quick-win**)
- [x] Add container test: background launch → `.ready` → `enterForeground()` → content renders (**medium**, test, **quick-win**)
- [x] Fail fast on duplicate step IDs in release builds (**medium**, bug, **quick-win**)
- [x] Add regression test or assertion for background `.work` step calling `waitForResolution()` (**medium**, test, **quick-win**)

### Medium priority — SwiftDataInspector

- [ ] Debounce or off-main search filtering in `EntityTableView` (**medium**, performance, **needs-design**)
- [x] Skip redundant `inspectorCount` when fetch proves truncation (**medium**, performance, **quick-win**)
- [x] Add tests for AGENTS.md gaps: schema reflection, `columnCharacterCounts`, batch fetch, unknown relationships, non-array to-many (**medium**, test, **quick-win**) *(partial — top 3 AGENTS.md gaps)*
- [x] Align `Sendable` docs with type conformances (**medium**, convention, **quick-win**)
- [x] Document or guard `rowLimit: nil` unbounded fetch footgun (**medium**, performance, **quick-win**)
- [ ] Split monolithic test file; add hosted UI smoke tests for major views (**medium**, test, **needs-design**)

### Medium priority — LogKit & LogViewerUI

- [x] Fix `LogStore.changes()` registration race (initial yield vs concurrent `record`) (**medium**, bug, **quick-win**)
- [x] Add test: cancelled `changes()` stream unregisters via `onTermination` (**medium**, test, **quick-win**)
- [x] Add concurrent stress test for monotonic snapshot delivery (**medium**, test, **quick-win**)
- [x] Defer `LogViewer` export string generation until share is initiated (**medium**, performance, **quick-win**)
- [x] Search `LogViewerModel` using `categoryDisplayName`, not raw category id (**medium**, bug, **quick-win**)
- [x] Fix empty state when filters match nothing (distinct from store-empty) (**medium**, bug, **quick-win**)
- [x] Add async test for `LogViewerModel.observe()` live updates (**medium**, test, **quick-win**)
- [x] Strengthen hosting tests beyond `view != nil` (**medium**, test, **quick-win**)
- [x] Cache `LogViewerModel.categories` alongside `entries` updates (**medium**, performance, **quick-win**)

### Medium priority — WhereWidgets & Where app

- [ ] Handle stale widget snapshot after midnight in `WhereWidgetProvider.loadEntry` (**medium**, bug, **needs-design** — product decision on empty-today vs stale display)
- [x] Localize widget gallery `configurationDisplayName` / `description` (**medium**, localization, **quick-win**)
- [ ] Add WhereWidgets test target or extract testable timeline helpers (**medium**, test, **needs-design**)
- [x] Add `Where/WhereWidgets/README.md` and `AGENTS.md` (**medium**, convention, **quick-win**)
- [ ] Make `AppDelegate.launcher` safe before SwiftUI reads it (non-optional or gated `WindowGroup`) (**medium**, bug, **needs-design**)
- [x] Replace placeholder `WhereTests` with real app-shell / launch-reason tests (**medium**, test, **quick-win**)
- [ ] Extract and test `WhereLaunch.reason(from launchOptions:)` (**medium**, test, **needs-design** — pairs with launch wiring refactor)
- [ ] Map additional UIKit launch options to `LifecycleReason` or document supported set (**medium**, bug, **needs-design**)
- [ ] Verify/add `UIBackgroundModes` location for CoreLocation background relaunch (**medium**, bug, **needs-design**)
- [ ] Pick single owner for `launcher.run()` (AppDelegate vs `RootView.task`) (**medium**, duplication, **needs-design**)

### Medium priority — infrastructure modules

- [x] Add `README.md` and `AGENTS.md` to StuffCore, WhereTesting, WhereWidgets, StuffTestHost (**medium**, convention, **quick-win**)
- [x] Add `testScheme(name: "StuffCoreTests")` to `Project.swift` (**medium**, test, **quick-win**)
- [x] Document StuffTestHost `Bundle.module` embedding contract in module AGENTS.md (**medium**, convention, **quick-win**)
- [x] Add StuffTestHost smoke test (key window + root VC after launch) (**medium**, test, **quick-win**)
- [x] Fix `WhereTesting.show()` `layer.speed` reset on trap (defer at function entry) (**medium**, bug, **quick-win**)
- [ ] Add `WhereTestingTests` for store fidelity, `show` failure, and `waitFor` timeout (**medium**, test, **needs-design** — may follow WhereTesting split)
- [x] Move `LifecycleContainerTests.renders(within:_:)` polling into WhereTesting (**medium**, duplication, **quick-win**)

### Low priority / polish

#### WhereCore
- [x] Reorder `DayAggregator` doc comments (`yearInterval` vs `CellTally`) (**low**, formatting, **quick-win**)

#### WhereUI
- [x] Add `PreviewSupport.sampleWidgetSnapshot(...)` and use in widget previews (**low**, convention, **quick-win**)
- [x] Add named `#Preview`s for distinct visual states (failure, empty timeline, prefill, etc.) (**low**, convention, **quick-win**)
- [x] Add `RootView` preview with `PreviewSupport.loadedModel()` for logged-in shell (**low**, convention, **quick-win**)
- [x] Extract shared date-range formatting from `PresenceTimelineView` / `MissingDaysView` (**low**, duplication, **quick-win**)
- [x] Reuse `PreviewSupport.previewServices()` in onboarding tests (**low**, duplication, **quick-win**)
- [ ] Profile `RegionSummaryCard` Canvas rosette; cache or reduce rings if needed (**low**, performance, **needs-design** — optimize only if profiling warrants)
- [ ] Make `LocationNamer` cancellation-aware (**low**, performance, **needs-design**)
- [x] Standardize `Strings.swift` localization call style (**low**, formatting, **quick-win**)
- [x] Update stale `WhereModel` comments in `RegionSummaryCard` (**low**, convention, **quick-win**)
- [x] Remove redundant `.environment(session)` on sheets if not required (**low**, convention, **quick-win**)

#### LifecycleKit
- [ ] Extract shared drive scaffolding in `LifecycleRunner` (**low**, duplication, **needs-design** — touch carefully alongside cancel-and-drain fix)
- [x] Handle unmatched failed step ID in `retry()` explicitly (**low**, bug, **quick-win**)
- [x] Review `LifecycleRunnerProxy` Sendable / MainActor isolation (**low**, convention, **quick-win**)
- [x] Move shared `waitUntil` to LifecycleKit test support file (**low**, test, **quick-win**)
- [x] Assert per-step attempt counts in flaky-retry fuzz test (**low**, test, **quick-win**)

#### SwiftDataInspector
- [x] Extract shared optional-unwrapping helper (**low**, duplication, **quick-win**)
- [x] Fix `relatedReferences` early return → `continue` on keypath miss (**low**, bug, **quick-win**)
- [x] Update `InspectorRowSet.isTruncated` doc comment (**low**, formatting, **quick-win**)
- [x] Move `ModelContext` fetch helpers out of reflection file (**low**, convention, **quick-win**)
- [x] Add direct `binaryDescription` and pinned `Date` format tests (**low**, test, **quick-win**)
- [x] Clarify `modelTypes: nil` vs `[]` in public docs (**low**, convention, **quick-win**)
- [x] Improve column width heuristic for wide characters (**low**, performance, **quick-win**)

#### LogKit
- [x] Gate `LogChannelTests` store assertions with `#if DEBUG` (**low**, test, **quick-win**)
- [ ] Consider ring buffer for `LogStore` eviction (**low**, performance, **needs-design**)
- [x] Add multi-observer `changes()` test (**low**, test, **quick-win**)
- [x] Restrict or document direct `LogStore.record` DEBUG-only contract (**low**, convention, **quick-win**)

#### LogViewerUI
- [x] Close init snapshot vs `.task` observation gap (**low**, bug, **quick-win**)
- [x] Add combined-filter and mapped-export model tests (**low**, test, **quick-win**)
- [x] Deduplicate level label formatting (**low**, duplication, **quick-win**)
- [x] Hoist ISO8601 formatter to static property (**low**, performance, **quick-win**)
- [x] Group model tests in struct suite for consistency (**low**, convention, **quick-win**)
- [x] Add explicit `@Bindable` in `LogViewer.body` (**low**, convention, **quick-win**)

#### WhereWidgets
- [x] Downgrade expected empty snapshot log to `warning`; distinguish entitlement failures (**low**, convention, **quick-win**)
- [x] Replace bare `default:` on `WidgetFamily` with explicit cases + `@unknown default` (**low**, convention, **quick-win**)
- [x] Centralize `WidgetSnapshot` fixture factory (**low**, duplication, **quick-win**)
- [x] Reuse shared `Calendar` instead of new `DayAggregator()` per load (**low**, performance, **quick-win**)
- [ ] Add cross-process publish/read integration test or document gap (**low**, test, **needs-design**)

#### Where app
- [ ] Move launch-reason mapping into WhereUI; thin `AppDelegate` (**low**, convention, **needs-design** — pairs with launch wiring refactor)
- [x] Deduplicate launch logging between AppDelegate and `WhereLaunch` (**low**, duplication, **quick-win**)
- [x] Remove unused `import LogKit` from AppDelegate (**low**, formatting, **quick-win**)
- [x] Add test for production `WhereApp` → `RootView(model:launcher:)` wiring (**low**, test, **quick-win**)

#### StuffCore
- [x] Document scaffold intent / wire first consumer when shared code lands (**low**, convention, **quick-win**)
- [ ] Replace tautological `version` test when real API exists (**low**, test, **quick-win**)

#### WhereTesting
- [x] Harden or remove `UIView.recursiveDescription` force-cast (**medium**, bug, **quick-win**)
- [x] Extract duplicate window lookup into `hostKeyWindow()` (**low**, duplication, **quick-win**)
- [x] Remove unused public API (`determineAverage`, completion `waitFor`, etc.) (**low**, convention, **quick-win**)
- [x] Consolidate `ShowError` / `WaitError` (**low**, duplication, **quick-win**)
- [x] Add hosted test asserting appearance/onAppear contract (**low**, test, **quick-win**)
- [x] Reorder `WaitError` next to `waitFor` helpers (**low**, formatting, **quick-win**)

#### StuffTestHost
- [ ] Deduplicate scene configuration (plist vs `configurationForConnecting`) (**medium**, duplication, **needs-design**)
- [x] Rename `TestHostApp.swift` ↔ `AppDelegate` for consistency (**low**, convention, **quick-win**)
- [x] Align `@MainActor` on host delegates with production app (**low**, convention, **quick-win**)
- [ ] Document or split WhereCore-always-embedded build trade-off (**medium**, performance, **needs-design**)

### Summary by effort

| Effort | Count |
|--------|------:|
| **quick-win** | 89 done / 3 deferred |
| **needs-design** | 32 |


**Quick-win progress (fix/module-audit-quick-wins):** 89 completed, 3 deferred/skipped, 1 partial — see branch commits `06eea39`…`2655cbe`.

Filter tips: search `quick-win` for bite-sized PRs; search `needs-design` for items to discuss or spec before coding.

---

## Per-module findings

### WhereCore (18 findings)

**High**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| localization | `DailySummaryReconciler.swift` — `summaryFragment(region:days:)` (~100–110) | `String(localized: "summary.notification.regionDays", …)` resolves catalog value `"%1$@ in %2$@"` without format arguments | Pass `count` and `region.localizedName` into the formatting API; add test asserting no `%` tokens in composed body |
| bug | `BackupCoordinator.swift` — `importBackup(from:strategy:onProgress:)` (~124) | After import, only `widgets.publish()` runs; badge, per-day reminders, and daily-summary notification are not reconciled | Invoke same post-write reconcile sequence as `DayJournal` after successful import |

**Medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `WhereServices.swift` — `onPersisted` hook; `DailySummaryReconciler` | GPS ingest and `DayJournal` writes reconcile reminders/widgets but never call `DailySummaryReconciler.reconcile()` | Add `summary.reconcile()` to ingest hook and presence-changing write paths |
| bug | `DayJournal.swift` — `ingest(_:)`, `ingest(_ samples:)`, `addManualSample(_:)` (~33–58) | These writes publish widgets but do not call `ReminderReconciler.reconcile()` | Call `await reminders.reconcile()` after successful writes, or restrict APIs to non–presence-changing use |
| performance | `WhereServices.swift` (~92–93); `LocationIngestor.swift` — `start()` (~123–128) | Every `start()` fires `onPersisted` with `liveSample: nil`, always running full `reminders.reconcile()` | Skip reconcile for drain-only outcomes with empty `changedDays` |
| performance | `WidgetDataReader.swift` — `snapshot(asOf:)`; `ReportReader.swift` — `yearReport(for:)` | Each widget publish and reminder reconcile reloads and re-aggregates entire calendar year | Consider incremental reads or memoizing current-year report with invalidation keyed by changed day keys |
| localization | `DailySummaryReconciler.swift` — `summaryFragment` (~101–105) | `summary.notification.dayCount` plural rules may not apply — `days` never passed to localization API | Use catalog plural/interpolation API with `days` as quantity argument |
| localization | `Backup/BackupService.swift` — `BackupError.errorDescription` (~40–46) | User-visible backup error strings are hardcoded English | Move messages into `Localizable.xcstrings` |
| bug | `Location/LocationOutbox.swift` — `save(_:)` (~80–92) | If durable outbox persistence fails, in-memory retry queue holds samples but on-disk mirror may be empty — relaunch can drop queued GPS samples | Treat outbox save failure as degraded state; add relaunch test |
| bug | `LocationIngestor.swift` — `enqueueForRetry` / `retryQueueCapacity` (~247–254) | At capacity, oldest samples dropped with only a warning — silent data loss during prolonged persistence outage | Surface user-visible degradation or add FIFO eviction test at 1000 |
| convention | `DayJournal.swift`; `WidgetSnapshotPublisher.swift` | Log messages interpolate raw `Date` values; messages are `.public` | Log opaque identifiers instead of absolute timestamps |

**Low**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| test | `LocationIngestorTests.swift` | No test for retry-queue capacity FIFO eviction | Add test enqueueing 1001 failing samples |
| test | `BackupCoordinatorTests.swift`; `DailySummaryReconcilerTests.swift` | No tests for post-import reconcile or summary body updates without re-`configure` | Extend harness with spy schedulers |
| bug | `DayAggregator.swift` — `representativeCoordinates` (~92–95) | Tie for max sample count picks nondeterministic winner | Break ties deterministically |
| formatting | `DayAggregator.swift` (~138–150) | Doc comment for `yearInterval` interrupted by `CellTally` block | Reorder declarations |
| duplication | Multiple test files | Repeated private `iso(_:)` parsers and `calendar()` factories | Consolidate into shared test support file |
| bug | `Persistence/SwiftDataStore.swift` — `SDLocationSample.toValue()` (~484–488) | Corrupt/missing `sourceRaw` silently decodes as `.manual` | Prefer `nil` + fault or explicit `.unknown` source |
| convention | `LoggingReminderSchedulerTests.swift` — `FakeNotificationReminderCenter` (~105–110) | Bare `default:` on `UNAuthorizationStatus` | Enumerate known cases + `@unknown default` |

**Verified OK:** `WhereStore.perform` boundary; LocationIngestor retry bounds; DayAggregator calendar rules; reminder/widget idempotency; GeoJSON load caching.

---

### WhereUI (21 findings)

**High**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `Model/WhereSession.swift` — `trackingEnabled` setter (700–704) | Rapid toggle spawns unserialized `Task`s — slow `startTracking()` can finish after later `stopTracking()` | Serialize tracking mutations or bind to persisted intent with separate status UI |

**Medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| convention | `Settings/ManualDayEntryView.swift`; `Secondary/DayRelabelView.swift` — save-error alerts | Closure-based `Binding(get:set:)` for alert presentation | Add computed properties on view/model; bind directly |
| convention | `ManualDayEntryView.swift`; `DayRelabelView.swift` — `binding(for:)` | Region toggles use closure-based `Binding` helpers | Extract `@Observable` helper with bindable properties |
| convention | `Primary/PrimaryView.swift`; `Secondary/SecondaryView.swift` — `screen` switch | Bare `default:` over `WhereSession.LoadState` | Enumerate `.idle`, `.loading`, `.loaded` |
| convention | `Settings/AppIconView.swift` — `AppIconImage` (250–271) | Public `View` without `#Preview` | Add `#Preview` at bottom of file |
| convention | `Primary/PrimaryView.swift` — `#Preview` block (257–271) | No preview for elsewhere-only branch despite `PreviewSupport.elsewhereOnlySession()` | Add `#Preview("Elsewhere only")` |
| localization | `Settings/SettingsView.swift` (406); `Model/WhereSession.swift` (718) | DEBUG-only strings bypass `Strings.swift` and catalog | Add catalog entries and `Strings` accessors |
| duplication | `Primary/PrimaryView.swift`; `Secondary/SecondaryView.swift` — `screen` | Loading spinner and failed-state UI duplicated across tabs | Extract shared `ReportLoadGate` helper |
| duplication | `ManualDayEntryView.swift`; `DayRelabelView.swift` | Region-toggle binding, save-error alert, async save logic copy-pasted | Extract shared form component or model |
| performance | `Secondary/RegionDaysView.swift` — `DayRow` (154–157) | Each row fires independent `.task` for reverse geocoding | Batch geocoding or prefetch once per coordinate set |
| test | `Tests/ScreenHostingTests.swift` | `ManualDayEntryView` not covered by host test | Add host tests for default and `prefill:` modes |

**Low**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| convention | Widget preview files | `#Preview` blocks hand-roll inline `WidgetSnapshot` values | Add `PreviewSupport.sampleWidgetSnapshot(...)` variants |
| convention | Multiple views | Missing previews for distinct visual states | Add named previews per state |
| convention | `RootView.swift` — `#Preview` (88–91) | Preview uses full launch runner, not logged-in shell | Add preview with `PreviewSupport.loadedModel()` |
| duplication | `PresenceTimelineView.swift`; `MissingDaysView.swift` | Duplicated abbreviated date-range formatting | Shared helper on `Date` or `ClosedRange<Date>` |
| duplication | `Tests/OnboardingTests.swift`; `Preview/PreviewSupport.swift` | Tests manually construct `WhereServices` inline | Reuse `PreviewSupport.previewServices()` |
| performance | `Primary/RegionSummaryCard.swift` — `stampPaper` Canvas (65–100) | Many concentric rings per card in `ScrollView` | Profile; consider caching or reducing ring count |
| performance | `Secondary/SecondaryView.swift` — `loadPlaceNames()`; `Shared/LocationNamer.swift` | `LocationNamer` not cancellation-aware | Propagate task cancellation or use generation token |
| formatting | `Shared/Strings.swift` | Mix of `localized(_:)` helper and inline `String(localized:defaultValue:bundle:)` | Standardize on one style |
| convention | `Primary/RegionSummaryCard.swift` — comments (16–22) | Comments reference `WhereModel` though callers pass `WhereSession` | Update comments |
| convention | `Primary/PrimaryView.swift` — sheet modifiers (56–63) | Redundant `.environment(session)` re-injection | Remove unless regression requires it |

---

### LifecycleKit (12 findings)

**High**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `LifecycleRunner.swift` — `ActivePresentation.hold()` (~299–305), `runStep`, `drive`/`driveTeardown` | Cancel-and-drain broken during `minVisible`: superseded drive can set `phase = .ready` | After `hold()`, treat `Task.isCancelled` as `.cancelled`; gate `.ready` on drive still being current |

**Medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| test | `Tests/LifecycleRunnerFuzzTests.swift` (~51–139) | Fuzz only uses `LifecycleStep.work` — cancel-and-drain, interactive, `enterForeground`, teardown untested | Extend generator/model with those paths |
| test | `Tests/LifecycleRunnerTests.swift`; `LifecycleRunnerCancellationTests` | No test superseding drive during `minVisible` hold | Add teardown/enterForeground during hold; assert cancelled drive doesn't reach `.ready` |
| localization | `LifecycleFailureView.swift` (~15–26) | Hard-coded English strings resolved against app bundle, not module | Add string catalog to LifecycleKit target |
| test | `Tests/LifecycleContainerTests.swift` (~88–103) | No container test that `enterForeground()` promotion builds `content` | Drive background runner to `.ready`, call `enterForeground()`, assert content renders |
| bug | `LifecycleSteps.swift` — `assertUniqueIDs` (~59–66) | Duplicate step IDs only `assert` in debug | Fail fast in release or deduplicate at init |
| test | `Tests/` (no matching test) | `.work` step with `modes: .all` calling `waitForResolution()` on background launch hangs | Add regression test or debug assertion |

**Low**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| duplication | `LifecycleRunner.swift` — `drive` / `driveTeardown` | Cancel-and-drain scaffolding duplicated | Extract shared `startDrive(reason:)` helper |
| bug | `LifecycleRunner.swift` — `retry()` (~124) | Failed step ID absent from sequences silently restarts at index 0 | No-op or assert when ID cannot be matched |
| convention | `LifecycleContainer.swift` — `LifecycleRunnerProxy` (~24–35) | `Sendable` holding `@MainActor` class reference | Mark access `@MainActor` or document isolation |
| test | `Tests/LifecycleRunnerTests.swift` (~10–21) | Shared `waitUntil` in one file, used across test files | Move to shared test-support file |
| performance | `LifecycleStep.swift`; `LifecycleStepUIBridge.swift` | `AnyView` type erasure on every presentation swap | Acceptable; optimize only if profiling shows cost |
| test | `Tests/LifecycleRunnerFuzzTests.swift` (~98–138) | Flaky-retry fuzz doesn't assert per-step attempt counts | Record attempt totals in model |

**Verified OK:** EmptyView on background launch; interactive default `.foreground`; interactive cancel-and-drain while parked; fuzz model parity for work steps.

---

### SwiftDataInspector (16 findings)

**High**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `SwiftDataReflection.swift` — `classify(_:)` (99–100); `SwiftDataInspectorReader.swift` — `relatedRows(...)` (99–105) | Bare `PersistentIdentifier` → `destinationType` nil → empty related rows | Fall back to relationship destination type from schema metadata |
| performance | `EntityTableView.swift` — `cellRow(_:)`, `table(rows:)` (114–165) | Each row builds `HStack` with one `Text` per column — wide schemas stall main thread | Cap columns, collapse to summary, or virtualize horizontally |

**Medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| performance | `EntityTableView.swift` — `filtered(_:)` (211–217) | Search scans all rows synchronously on main actor per keystroke | Debounce, move filtering off-main, or precompute searchable blob |
| performance | `SwiftDataInspectorReader.swift` — `rows(for:pageCount:)` (60–76) | Every load runs both `inspectorFetch` and `inspectorCount` | Skip count when fetch returns fewer rows than limit |
| test | `Tests/SwiftDataInspectorTests.swift` vs `AGENTS.md` (177–193) | AGENTS.md scenarios untested: schema reflection, `columnCharacterCounts`, batch fetch helpers, unknown relationships, non-array to-many | Add focused tests per gap |
| convention | `InspectorEntity.swift`; `InspectorRow.swift`; `SwiftDataInspectorReader.swift` | Docs claim `Sendable` but types don't declare conformance | Add explicit conformances or soften docs |
| performance | `SwiftDataInspectorConfiguration.swift`; `SwiftDataInspectorReader.swift` | `rowLimit: nil` fetches every row with no guardrail | Document footgun; consider explicit `.unlimited` opt-in |
| test | `Tests/SwiftDataInspectorTests.swift`; `InspectorPreviewData.swift` | Single 625-line test file; preview hosts exercise UI paths unit tests never touch | Split tests by concern; add hosted UI smoke tests |

**Low**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| duplication | `SwiftDataReflection.swift` — `unwrapOptional`; `SwiftDataInspectorReader.swift` — `unwrap` | Identical optional-unwrapping logic | Extract shared helper |
| performance | `SwiftDataInspectorReader.swift` — `loadEntities()` (37–50) | N sequential count queries per model type | Batch counts or cache for duration of call |
| bug | `SwiftDataReflection.swift` — `relatedReferences(of:named:)` (73–74) | Early `return .none` instead of `continue` on failed keypath lookup | Replace with `continue` |
| formatting | `InspectorRow.swift` — `InspectorRowSet.isTruncated` doc (30–31) | Comment references offset-based pagination that doesn't exist | Update to prefix-based truncation |
| convention | `SwiftDataReflection.swift` — `ModelContext` extension (163–241) | Fetch helpers live in reflection file | Move to reader file or dedicated extension |
| test | `Tests/SwiftDataInspectorTests.swift` | No direct `binaryDescription` or pinned `Date` format tests | Add direct unit tests |
| convention | `SwiftDataInspectorConfiguration.swift`; `InspectorPreviewData.swift` | `modelTypes: nil` vs `[]` easy to confuse | Document or use dedicated enum |
| performance | `EntityTableView.swift` — `width(of:)` (205–225) | Column width from char count × `"0"` width — inaccurate for UUIDs/CJK | Size on actual max cell string |

---

### LogKit (9 findings)

**Medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `LogStore.swift` — `changes()` (66–78) | Observer registered under lock; concurrent `record()` can yield newer snapshot before initial yield — out-of-order delivery | Snapshot and yield initial before registering, or use monotonic generation |
| test | `Tests/LogStoreTests.swift` | No test that cancelled `changes()` stream removes continuation via `onTermination` | Add async cancellation test |
| test | `Tests/LogStoreTests.swift` — `changesYieldsInitialThenUpdates` (38–55) | Registration/initial-yield race with concurrent `record()` untested | Add stress test asserting monotonic snapshots |

**Low**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| test | `Tests/LogChannelTests.swift` — `channelRecordsEachLevelIntoStore` (4–20) | Test depends on `#if DEBUG` in `LogChannel.emit` — fails in Release | Gate with `#if DEBUG` or split tests |
| performance | `LogStore.swift` — `record(_:)` (36–38) | Eviction uses `removeFirst(overflow)` — O(n) per overflow | Ring buffer for O(1) append/eviction |
| test | `Tests/LogStoreTests.swift` | `capacity > 0` precondition untested | Document or add test |
| test | `Tests/LogStoreTests.swift` | Multiple simultaneous `changes()` consumers untested | Add multi-observer test |
| convention | `LogStore.swift` — `record(_:)` (29–45) | Direct `LogStore.record` bypasses DEBUG guard in `LogChannel` | Document DEBUG-only contract or restrict API |
| duplication | `LogChannel.swift` — level methods (26–48) | Six thin wrappers around `emit` | Accept as idiomatic API |

**Verified OK:** `#if DEBUG` store guard in `LogChannel`; lock scope and yield-outside-lock in `LogStore`; `onTermination` self-unregister implementation.

---

### LogViewerUI (14 findings)

**High**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| performance | `LogViewerModel.swift` — `filteredEntries` (38–46); `LogViewer.swift` — `List` (38) | Every filter change allocates reversed copy and scans all entries | Cache filtered results; invalidate on entry/filter changes only |

**Medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| performance | `LogViewer.swift` — `ShareLink` (79–80) | Export string built synchronously when opening menu | Defer export until share initiated |
| bug | `LogViewerModel.swift` — `filteredEntries` search branch (43–44) | Search matches raw `entry.category`, not `categoryDisplayName` | Include mapped name in search |
| bug | `LogViewer.swift` — `content`; `LogViewerModel.isEmpty` (48–49) | `isEmpty` reflects store buffer, not filtered results — active filters matching nothing show blank list | Branch on `filteredEntries.isEmpty` with distinct copy |
| test | `Tests/` — no `observe()` test | Live `LogStore.changes()` integration untested | Add async test recording while `observe()` runs |
| test | `Tests/LogViewerHostingTests.swift` (9–27) | Hosting tests only assert `hosted.view != nil` | Assert hierarchy content or strengthen model tests |
| performance | `LogViewerModel.swift` — `categories` (33–35) | Category picker rebuilds from all entries on every toolbar render | Cache alongside `entries` updates |

**Low**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `LogViewer.swift` — init + `.task` (16–18, 26) | Brief window between init snapshot and `.task` where store updates aren't reflected | Rely solely on `changes()` or start observation in init |
| test | `Tests/LogViewerModelTests.swift` | No tests for mapped export, combined filters, filter-no-match vs store-empty | Add focused model tests |
| duplication | `LogLevel+Display.swift`; `LogViewer.swift`; `LogViewerModel.swift` | Level label formatting duplicated | Single internal helper |
| performance | `LogViewerModel.swift` — `exportText` (59) | New `Date.ISO8601FormatStyle` per export call | Hoist to static let |
| localization | `LogViewer.swift`; `LogLevel+Display.swift` | Hardcoded English (acceptable for DEBUG-only per module docs) | Move to catalog if shipped beyond DEBUG |
| convention | Test files | Inconsistent suite organization | Group model tests in struct suite |
| performance | `LogViewerModel.swift` — `observe()` (27–28) | Full snapshot copy on each log line | Acceptable at 1000-entry cap |
| convention | `LogViewer.swift` — `$model` bindings | Missing explicit `@Bindable` in body | Add `@Bindable var model = model` for consistency |

---

### WhereWidgets (9 findings)

**Medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `WhereWidgetProvider.swift` — `getTimeline` (33–41), `loadEntry` (44–65) | After midnight, timeline reloads but stale snapshot still served — Today widget shows yesterday until app republishes | Detect `snapshot.day < today` and synthesize empty-today view or adjust display |
| localization | `TodayWidget.swift` (16–17); `YearTotalsWidget.swift` (16–17) | Widget gallery name/description hardcoded English; in-widget copy localized | Add catalog keys for picker strings |
| test | `WhereWidgetProvider.swift`; no `Where/WhereWidgets/Tests/` | Timeline provider logic untested | Add test target or extract testable helpers |
| convention | `Where/WhereWidgets/` module root | Missing `README.md` and `AGENTS.md` | Add module docs covering App Group read path and refresh contract |

**Low**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| convention | `WhereWidgetProvider.swift` (54) | Expected "no snapshot yet" logged at `error`; entitlement failures conflated with missing file | Split paths: `warning` for nil read, `error` only when `shared()` throws |
| convention | `TodayWidget.swift` (28–42); `YearTotalsWidget.swift` (28–38) | Bare `default:` on `WidgetFamily` | Enumerate supported families + `@unknown default` |
| duplication | `WhereWidgetProvider.swift` (57–83); `WidgetPreviewFixtures.swift` (21–36) | `WidgetSnapshot` fixture construction duplicated | Centralize factory |
| performance | `WhereWidgetProvider.swift` (35, 55, 73) | New `DayAggregator()` per load for calendar | Hold shared `Calendar` aligned with app |
| test | `WhereCore/Tests/WidgetSnapshotPublisherTests.swift` | No cross-process contract test for publish → provider read | Add integration test or document gap in AGENTS.md |

**Verified OK:** App publish path and widget read path aligned; `.after(nextMidnight)` complements app-side throttled refresh.

---

### Where app (10 findings)

**High / medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `AppDelegate.swift:24` — `launcher`; `WhereApp.swift:10` | `launcher` is IUO passed to `RootView` — trap if accessed before delegate sets it | Build default runner in init or gate `WindowGroup` on non-nil launcher |

**Medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| test | `Tests/WhereTests.swift:3–6` | Only test is `#expect(true)` — doesn't import Where module | Add real smoke tests and launch-reason mapping tests |
| test | `AppDelegate.swift:35–37` | Location launch-options mapping untested | Extract `WhereLaunch.reason(from:)` into WhereUI and test |
| bug | `AppDelegate.swift:35–37` | Binary launch reason — `.remoteNotification`, `.backgroundTask`, `.other` never mapped | Map additional keys or document supported paths |
| bug | `AppDelegate.swift:35–39`; `Project.swift:80–89` | CoreLocation background relaunch assumes `launchOptions[.location]` but Info.plist may lack `UIBackgroundModes` / `location` | Add location background mode to Where app Info.plist |
| duplication | `AppDelegate.swift:50`; `RootView.swift:72–73` | `launcher.run()` started from both delegate and RootView | Single driver — delegate for production, RootView for previews only |

**Low**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| convention | `AppDelegate.swift:35–48` | Launch logic in app target instead of WhereUI | Move reason mapping to `WhereLaunch` API |
| duplication | `AppDelegate.swift:38–42,49`; `WhereLaunch.swift:63` | Overlapping launch log lines | Log once at boundary |
| formatting | `AppDelegate.swift:2` | Unused `import LogKit` | Remove import |
| test | `Tests/WhereTests.swift`; `WhereApp.swift:5–11` | Production `WhereApp` → delegate → `RootView(model:launcher:)` path untested | Add app-target or hosted test |

---

### StuffCore (4 findings)

**Medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| convention | `Shared/StuffCore/` module root | Missing `README.md` and `AGENTS.md` | Add minimal docs; run `./sync-agents` |
| test | `Project.swift` — `schemes` vs `StuffCoreTests` (174–179, 223–231) | No `testScheme(name: "StuffCoreTests")` | Add scheme for isolated `tuist test StuffCoreTests` |

**Low**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| convention | `Sources/StuffCore.swift` — `StuffCore` | Not imported by any production target | Document scaffold intent |
| test | `Tests/StuffCoreTests.swift` — `versionIsDefined` (4–7) | Tautological version test | Replace when real API lands |
| convention | `Sources/StuffCore.swift` — `version` (3) | Undocumented integer constant | Document or use semver string |

---

### WhereTesting (14 findings)

**High**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `WhereTesting.swift` — `show(_:loadAndPlaceView:perform:)` (39–54) | Child VC lifecycle order wrong — `addChild`/attach/`didMove` and teardown order don't match UIKit contract | Reorder to match Apple container-VC contract |
| convention | `Package.swift` — `WhereTesting`; `Project.swift` — `unitTests` (36–39) | `InMemoryKeyValueStore` pulls WhereCore into every hosted bundle | Split UIKit-only helpers from Where-specific store double |

**Medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| bug | `WhereTesting.swift` — `show` (38, 48–55) | `layer.speed = 100` not reset if test traps — `defer` skipped | Reset speed in defer at top of function |
| convention | `Where/WhereTesting/` module root | Missing `README.md` and `AGENTS.md` | Add module docs |
| test | `Where/WhereTesting/` — no `Tests/` | No self-tests for store, `show` failure, `waitFor` timeout | Add `WhereTestingTests` bundle |
| duplication | `WhereTesting.swift` — `waitFor` (65–78); `LifecycleKit/Tests/LifecycleContainerTests.swift` — `renders(within:_:)` (42–48) | Run-loop polling duplicated | Move into WhereTesting as shared API |
| bug | `WhereTesting.swift` — `UIView.recursiveDescription` (134–136) | KVC + force-cast can trap | Return `String?` or mark debug-only |
| duplication | `WhereTesting.swift` — window lookup (25–32) | Duplicate key-window traversal | Extract `hostKeyWindow()` |

**Low**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| convention | `WhereTesting.swift` — `determineAverage`, `recursiveDescription`, completion `waitFor` | Unused public API | Remove or relocate dead symbols |
| bug | `WhereTesting.swift` — `waitFor(timeout:block:)` (81–88) | Completion-handler overload invokes block every poll iteration | Document single-shot or remove |
| duplication | `ShowError` (4–10); `WaitError` (123–129) | Identical error wrappers | Consolidate into one error type |
| performance | `InMemoryKeyValueStore.swift` — `set` / `roundTripped` (27–64) | Plist round-trip on every set | Acceptable for fidelity; use plain dict in hot paths if needed |
| localization | `WhereTesting.swift` — error strings | Hardcoded English (fine for test module) | Optional: add file/function context to timeout errors |
| formatting | `WhereTesting.swift` (77–129) | `WaitError` separated from `waitFor` helpers | Group in same MARK section |
| test | `WhereTesting.swift` — doc comment (12–15) | Claims full appearance lifecycle but tests only check `view != nil` | Add test asserting appearance/onAppear side effect |

---

### StuffTestHost (8 findings)

**High (convention)**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| convention | `Shared/StuffTestHost/` module root | Missing `README.md` and `AGENTS.md` | Document host scope, `SceneDelegate` invariant, `Bundle.module` embedding rule |

**Medium**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| convention | `Project.swift` — StuffTestHost dependencies (~164–172) | `Bundle.module` contract only in comment | Move to AGENTS.md with checklist for new modules |
| performance | `Project.swift` — StuffTestHost → WhereCore | Every hosted bundle embeds WhereCore even when unused | Document trade-off or split hosts |
| duplication | `Project.swift` (149–158); `TestHostApp.swift` (10–15) | Scene setup declared in plist and `configurationForConnecting` | Single source of truth for configuration name |
| test | `Shared/StuffTestHost/`; `WhereTesting.swift` — `show` (34–36) | Host invariants untested directly | Add smoke test asserting key window and root VC |

**Low**

| Category | Location | Issue | Suggestion |
|----------|----------|-------|------------|
| convention | `TestHostApp.swift` — `AppDelegate` | File named `TestHostApp.swift` but defines `AppDelegate` | Rename file or type |
| duplication | `Project.swift` (155–157); `TestHostApp.swift` (14) | Redundant delegate registration in plist and code | Drop redundant path after verifying launch |
| convention | `TestHostApp.swift`; `SceneDelegate.swift` | Missing `@MainActor` vs production `AppDelegate` | Align isolation or document difference |
| test | `Project.swift` — StuffTestHost (141–173) | No test target for host itself | Add smoke test or document delegated verification |

---

## Limitations

- Static analysis only — no `tuist test` or simulator runs in this pass
- Some findings (LifecycleKit race, Where background relaunch) need runtime confirmation
- DEBUG-only localization (LogViewerUI) flagged at low severity per module docs

---

## Modules reviewed

| Module | Path | Source files | Test files |
|--------|------|-------------:|-----------:|
| StuffCore | `Shared/StuffCore/` | 1 | 1 |
| LifecycleKit | `Shared/LifecycleKit/` | 9 | 7 |
| LogKit | `Shared/LogKit/` | 4 | 3 |
| LogViewerUI | `Shared/LogViewerUI/` | 4 | 2 |
| SwiftDataInspector | `Shared/SwiftDataInspector/` | 11 | 1 |
| WhereCore | `Where/WhereCore/` | 39 | 24 |
| WhereUI | `Where/WhereUI/` | 37 | 20 |
| WhereTesting | `Where/WhereTesting/` | 2 | — |
| Where | `Where/Where/` | 2 | 1 |
| WhereWidgets | `Where/WhereWidgets/` | 5 | — |
| StuffTestHost | `Shared/StuffTestHost/` | 2 | — |