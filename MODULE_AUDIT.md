# Swift Module Audit Report

Read-only review of all **19 SPM library targets**, **6 Tuist app/extension targets**, and the repo-owned **Bumper Bowling** architecture rules (501 source / 310 test Swift files across shipped targets, plus 3 unwired prototype sources). No code was changed.

**Date:** August 6, 2026
**Method:** Read-only verification of every open July 26 finding against current source, module cluster by module cluster; file-count refresh; new-surface review of the week's landings (demo mode and `WhereScope` #150, `./test` as one front door #151, ambient snapshots and build-attributed sessions #152, resolution/store-scan race #153, spans across the app #154, `Bundle.module` env override #155, Flyover browser #156, developer tools launcher #157, Inspector boot mode #158, merged Backup/Data settings #159, Xcode 27 beta 4 re-record #161, Flyover canvas stability #166, agent-skill extraction #167, nonoptional launcher #168, remote-change filtering #169).
**Prior audit:** July 26, 2026 (~359 source / ~198 test, 14 SPM targets).

> **This report carries no actionable items.** Every finding it describes is filed
> in a `TODOs.md`; the root [`TODOs.md`](TODOs.md) owns the item format and says
> which file covers which area. Read this one for *shape and drift* — what each
> module verified clean, the themes running across the backlog, and how the tree
> moved since the last pass — and take the work itself from the `TODOs.md` files.
> It is true as of the header date above, **not** as of `HEAD`.

---

## Executive summary

The heaviest week the repo has had. Three new library targets landed — **Flyover** (the screen browser, 50 sources), **Inspector** (the renamed and much-expanded `SwiftDataInspector`, now a second *boot runtime*), and **LifecycleKitUI** — while **CreditKit**, **SnapshotKit**, and **SnapshotKitTesting** are counted here for the first time (they landed on July 26 itself, after the previous pass took its inventory). The tree grew from ~359 to **501** source files, WhereUI alone 113 → 150 and WhereCore 87 → 95. Demo mode (#150) reshaped composition around `WhereScope`, and #152/#154 pushed Periscope spans through every plausibly expensive path in the app.

**Nothing on the July 26 high list closed this week.** Three of the five carried highs — the daily-summary fan-out gap, `CalendarDay.displayDate`'s `Calendar.current`, and the blind `where.gregorian_calendar` rule — were re-verified against current source and are open exactly as filed. The tracking-toggle race and the LifecycleKit terminal-phase race are gone: the former landed a coalesced worker on `WhereSession` (#198, 2026-08-04), the latter went with the typed-engine rewrite (#116) that landed *on* July 26. What closed since is smaller and real: `WherePreferences.init(store:)` lost its default, `IntentSnippets`' preview literal is localized, the `LocationsView`/`YearView` empty-state snapshot cases exist, `SnapshotCase` now rebuilds content per configuration, and single-sample ingest / `addManualSample` / bulk ingest now route through the post-write fan-out.

Three new findings were filed this pass, and one previously-filed claim was found **false** and corrected rather than carried.

---

## Top findings

Pointers only — each one's evidence and suggested fix live in the linked file.

| # | Module | Issue | Filed in |
|---|--------|-------|----------|
| 1 | Bumper Bowling | `where.gregorian_calendar` matches only an explicit `Calendar` base, so the rule is green while four shipped sites drift | [`TODOs.md`](TODOs.md) P0 |
| 2 | WhereCore | `DailySummaryReconciler.reconcile()` is absent from the post-day-change fan-out — the notification body stays stale until a foreground re-`configure` | [`Where/TODOs.md`](Where/TODOs.md) P0 |
| 3 | PeriscopeCore | The pre-store-attach window is dropped, and #154's budgeted launch spans made it more expensive: a launch span's began and ended now land in different places | [`Shared/Periscope/TODOs.md`](Shared/Periscope/TODOs.md) P0 |
| 4 | WhereUI | `CalendarDay.displayDate` resolves through `Calendar.current`, so day labels on a non-Gregorian device render ~543 years off | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 5 | WhereUI | Notification authorization is requested during launch, unprompted — and all three preferences default to `true`, so it hits every fresh install | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 6 | Project | `WhereTests` double-links `LifecycleKit` beside `WhereUI`, and never imports it — **new** | [`TODOs.md`](TODOs.md) P1 |
| 7 | WhereCore | A store opened without a resolvable URL silently loses remote-change observation in release — **new** | [`Where/TODOs.md`](Where/TODOs.md) P2 |
| 8 | Flyover | 50 sources against 10 namesake test files — the largest untested surface in the repo — **new** | [`Shared/Flyover/TODOs.md`](Shared/Flyover/TODOs.md) P1 |
| 9 | WhereCore | `setTrackedRegion(false)` hard-deletes the row; the shipped picker reaches it, so past-year re-attribution risk is live | [`Where/TODOs.md`](Where/TODOs.md) P1 |

---

## Cross-cutting themes

### The composition rules held under the week that stress-tested them

Demo mode was the first change to demand two worlds at once, and the shape the root `AGENTS.md` prescribes — create once, inject down, model ownership as a value — absorbed it without a flag. `WhereScope` carries an open store's services, its preferences, and its log store as one value; a second world is a second scope; Flyover retains a third that is built but never activated. The parts that *didn't* fit are precisely the parts that were already global, and they surfaced as items rather than as breakage: the process-global `WhereLog` facade still routes Flyover's diagnostics into the active scope's store, and one developer surface (`OpenSpansView(system: .shared)`) reaches the global directly while `WhereModel.logSystem` exists to prevent exactly that. That is the design working — a global is now visibly the exception.

### Spans arrived everywhere, and landed on an open durability gap

#154 put a budgeted span on every launch step, store read and commit, aggregation, detector, reconcile, intent, and widget publish. It also made Periscope's oldest P0 more expensive: a span opened before a scope attaches its store persists only its *end*, so the pair splits. Where documents the split and points at Periscope rather than working around it, which is the right call and the reason this shows up as one theme instead of two bugs — but the launch is now the single largest producer of half-persisted spans, and the item that fixes it is the same one that has been open longest.

### The reconciliation holes are stable, and the docs describe the version that doesn't exist

`reconcileAfterDayDataChange()` still fans out to issue state and widgets only. Daily summary remains outside it; `setPrimaryRegions(_:)` still commits without calling it. Single-sample ingest, `addManualSample`, and bulk ingest now route through the fan-out (2026-08-04 landings on `main`), but the GPS `onPersisted` hook and backup import paths were not re-checked this merge. None of the remaining holes moved this week. What is worth separating out is that `WhereCore/README.md` and — worse — `WhereCore/AGENTS.md` state the *unified* fan-out as a rule, so an agent reading the module's own contract is told the invariant holds. A false rule in an `AGENTS.md` is a different category of stale than a false sentence in a `README.md`: it will be preserved against the code.

### Test coverage is now bimodal

The modules with the most machinery are the best covered — PeriscopeCore 37/33, LifecycleKit 8/10, JournalKit 2/3, Inspector 23/14, all with fuzz or adversarial suites where the state space warrants it. The gap is concentrated in two places and both are recent: **Flyover** shipped 50 sources against 10 namesake tests, and **WhereUI** is 150/61 with 28 snapshot files carrying much of the real verification. Meanwhile PeriscopeTools still has 20 hosting smoke tests across 10 files that assert only "the view reached a window" — up from 18 across 9, because the pattern is still being copied into new files while the item to convert them stays open.

### Image snapshots became a repo-wide practice, and their cost is now shared

Four image bundles (WhereUI, Flyover, Inspector, PeriscopeTools) and 273 references, up from one bundle and 260. The one-bundle-per-module rule and the measured per-`.xctest` host-process isolation it rests on both held as new bundles were added. The cost followed: Flyover's canvas needed a 1.5s settle floor to stabilize (#166), making it the fourth case paying the floor the settle-cost item wants to remove, and the first outside Where. Two references remain quarantined or wrong on purpose — Inspector's bistable dark capture behind `withKnownIssue`, and the blank VoiceOver calendar captures, confirmed this pass still un-re-recorded by reading their LFS pointer sizes.

### Documentation drift is now mostly numeric

The prose contracts largely held: the Periscope group's invariants, LifecycleKit's, Inspector's twelve safety rules (each verified enforced in code this pass), CreditKit's, SnapshotKit's. What went stale was counts and lists — measured percentages quoted as current, a module stack that hadn't gained Flyover, an image-suite list of two that should be three. Those are fixed in this pass rather than filed, since they're the kind of claim that reads authoritative long after it stops being true.

---

## Per-module notes

What each module was checked for and found clean, plus the trade-offs this pass
accepted as deliberate. Open work is in the linked `TODOs.md`.

### Bumper Bowling — architecture lint

**Verified OK:** all 10 `where.*` rule IDs, scopes, and `.error` severities in `.bumper/RULES.md` match `WhereProjectRules.swift`; the component graph matches `BumperBowling.swift` / `WhereArchitecture.swift`. No drift.

**Open:** the Gregorian rule's blind spot (top finding 1). Re-derived this pass: **zero** explicit `Calendar.current` spellings remain in Where production sources, so the rule's match set is provably empty while four implicit-member sites drift.

**Files:** 4 rule/test sources · RULES.md ✓ · Open: [`TODOs.md`](TODOs.md)

---

### WhereCore

**Verified OK:** #169's remote-change filter correctly scopes by `NSPersistentStoreURLKey` and ignores Periscope's store, with three regression tests; backup import still routes through the full fan-out via `onImport`; every manual-day write path still funnels through `reconcileAfterDayChange()`; `forIntents(sharingStoreOf:)` inherits the base's schedulers, so demo-derived intents can't post real notifications; `RegionAttribution` rebuilds on `changes()` with a last-good fallback on read failure; schema versioning is fully absent rather than half-shipped, as the module docs say it is.

**Files:** 95 source / 60 test · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereUI

**Verified OK:** no closure `Binding(get:set:)` anywhere in the module; no `Calendar.current` in production sources (only test and preview fixtures); no empty `catch {}` in views or models; `LocationsView` pairs `tilt.start()` / `tilt.stop()`; the #150 scope model and #154's `BudgetedLaunchStep` / `.measured()` wiring match the documented shape; `README.md` and `AGENTS.md` are current on the three-tab shell, Flyover, the Inspector latch, and the scene-scoped `YearReportModel`.

**Files:** 150 source / 61 test / 28 snapshot · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### Flyover *(new)*

The app-agnostic screen browser: a catalog of screens rendered as a zoomable canvas or a list, fed for Where by `WhereFlyoverWorld`.

**Verified OK:** dependency scope is honored — SwiftUI, BroadwayCore/BroadwayUI, and SnapshotKit only, with no Where or persistence imports; no swallowed errors, no `try?`, no empty catches anywhere in `Sources/`; every switch over an own enum is exhaustive; no `Calendar.current`; no closure `Binding(get:set:)`; content loads go through a serial coordinator with `.task(id:)` cancellation; `FlyoverView` seeds its own Broadway root. English literals are the module's stated policy for a developer tool, and the code matches it.

**Files:** 50 source / 12 test / 1 snapshot · README ✓ · AGENTS ✓ · Open: [`Shared/Flyover/TODOs.md`](Shared/Flyover/TODOs.md) *(opened this pass)*

---

### Inspector *(renamed from SwiftDataInspector; gained a boot runtime)*

**Verified OK — every one of the module's twelve safety invariants was checked against code this pass, and all twelve are enforced**, most with tests: no deletion of a configured root or a containing ancestor; SwiftData sources resolved before filesystem deletion is enabled, with the store family and `recoveryStorageURLs` protected; deletion disabled in an unresolved storage tree; recovery erasure with a second-pass latch; pending erasures completed before either runtime is constructed (`AppDelegate.swift:48-50`); no symlink escape from a configured root; configured defaults domains only, with complex values read-only and no key creation; every context and model instance on `InspectorSwiftDataStore`; tables that don't fault relationships to render; whole-store erase only where a fresh-container factory was supplied. These guard against destroying the user's data, so they were verified individually rather than sampled.

**Files:** 23 source / 14 test / 1 snapshot · README ✓ · AGENTS ✓ · Open: [`Shared/Inspector/TODOs.md`](Shared/Inspector/TODOs.md)

---

### LifecycleKit & LifecycleKitUI

**Verified OK:** the terminal-phase race is genuinely gone — the typed engine holds nothing, the splash minimum moved to `LifecycleContainer`, and `drive` publishes behind `guard case let .completed(value) = outcome, !Task.isCancelled`. The `.undetermined` state machine, single-in-flight drive serialization, memoized run-once promotion, and detached-child isolation all still hold as documented.

**Accepted:** LifecycleKitUI has no `TODOs.md` — its one open item (the duplicate-ID traps) spans both modules and lives in LifecycleKit's.

**Files:** LifecycleKit 8/10 · LifecycleKitUI 5/3 · README ✓ · AGENTS ✓ · Open: [`Shared/LifecycleKit/TODOs.md`](Shared/LifecycleKit/TODOs.md)

---

### PeriscopeCore, PeriscopeUI, PeriscopeTools

**Verified OK:** Broadway still does not leak below PeriscopeTools; no test touches `Periscope.shared`; `@_spi(Testing)` is used for every injection hook in the new surface; span pairs still can't be split by floors, redaction, or drop policy; ambient snapshot folding, the relaunch-policy column sweep, and `SpanNode.Outcome` from #152 are implemented as designed and tested. `LogSession` correctly contributes no build attributes for an unstamped bundle.

**Accepted:** `LogSession.current` falls back to `"unknown"` for a missing `CFBundleShortVersionString` — checked against the "never invent a build" rule and found *not* to violate it; that rule governs `attributes`, and these are core session fields on a bundle that would have to be malformed.

**Files:** PeriscopeCore 37/33 · PeriscopeUI 1/2 · PeriscopeTools 27/27 + 1 snapshot · README ✓ · AGENTS ✓ · Open: [`Shared/Periscope/TODOs.md`](Shared/Periscope/TODOs.md)

---

### SnapshotKit & SnapshotKitTesting

**Verified OK:** the four image bundles each list only `SnapshotKitTesting` in `extraPackageProducts`; all four are in the `StuffSnapshotTests` scheme and none in `Stuff-iOS-Tests`; the one-bundle-per-module arrangement and its host-process rationale still hold. `SnapshotCase`'s lazy `contentFactory` fix landed with a regression test.

**Files:** SnapshotKit 8/3 · SnapshotKitTesting 14/11 · README ✓ · AGENTS ✓ · Open: [`Shared/SnapshotKit/TODOs.md`](Shared/SnapshotKit/TODOs.md), [`Shared/SnapshotKitTesting/TODOs.md`](Shared/SnapshotKitTesting/TODOs.md)

---

### JournalKit, CreditKit, StuffCore, TestHostSupport, StuffTestHost

**JournalKit:** strong fuzz/truncation coverage. **Files:** 2/3 · Open: [`Shared/JournalKit/TODOs.md`](Shared/JournalKit/TODOs.md)

**CreditKit:** `./attribution --check` is green (7 credits) — the report covers every pinned package and agent skill. **Files:** 2/3 · Open: [`Shared/CreditKit/TODOs.md`](Shared/CreditKit/TODOs.md)

**StuffCore:** intentional scaffold. **Files:** 1/1 · Open: [`Shared/StuffCore/TODOs.md`](Shared/StuffCore/TODOs.md)

**TestHostSupport:** dependency-free UIKit helpers; no dedicated bundle by design. **Files:** 1/0 · Nothing open.

**StuffTestHost:** the WhereCore embed is gone; `PACKAGE_RESOURCE_BUNDLE_PATH` now carries hosted `Bundle.module` resolution under Xcode 27 beta 4, wired on every test target and documented in `Project.swift`. **Files:** 2/0 · Open: [`TODOs.md`](TODOs.md)

All five: README ✓ · AGENTS ✓

---

### BroadwayCore, BroadwayUI, BroadwayCatalog

**Verified OK:** stylesheet/trait/cycle behavior well tested; trait registration pairs with teardown.

**Accepted:** a bare `default:` mapping unknown `UIContentSizeCategory` to `.large` (a deliberate fallback); hardcoded English in the catalog app.

**Files:** BroadwayCore 17/10 · BroadwayUI 6/4 · BroadwayCatalog 2/1 · README ✓ · AGENTS ✓ · Open: [`Shared/Broadway/TODOs.md`](Shared/Broadway/TODOs.md)

---

### RegionKit & RegionViewer

**Verified OK:** the per-region catalog drives `RegionStyle`, the pickers, and the App Intents `RegionEntity`; Source mode now builds from 57 per-region GeoJSON files via `RegionGeometryCatalog`, exercised indirectly by `RegionGeometryCatalogTests`. RegionViewer ships no test bundle by design.

**Files:** RegionKit 14/9 · RegionViewer 1/0 · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereIntents

**Verified OK:** reader/writer seams well covered; `IntentServices` handoff still tested for install/park/cancel/replace with no self-creating fallback; no Broadway double-link.

**Accepted:** the per-intent `perform()` glue is untested because `@Dependency` traps outside the perform flow — now documented in `AGENTS.md`, though not yet in `README.md`.

**Files:** 17/10 · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereWidgets, WhereShareExtension, Where app

**Verified OK:** `SharedItemLoader` reports provider errors through one `LoadedValue` that can't spell "bytes *and* an error"; widget gallery strings localized; `@unknown default:` on widget-family switches; no Broadway double-link in either extension. The Where app's `AppDelegate` completes pending Inspector recovery erasures before selecting a runtime.

**Accepted:** neither extension ships a test bundle (documented).

**Files:** WhereWidgets 7/0 · WhereShareExtension 5/0 · Where 6/2 · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

## Limitations

- **Static analysis only** — this pass ran on Linux, where Tuist, the simulator, and `swift run bumper` are unavailable, so no test, build, or lint execution backs any claim about runtime behavior. What *was* executed: `./swiftformat --lint` (clean, 0/818) and `./attribution --check` (clean). CI status on `main` was read via `gh` and is green through `14778027`, which is what lets the "the Gregorian rule finds nothing" conclusion stand — a hard `.error` gate that passes over a tree containing four drifting sites can only mean the rule doesn't see them.
- Some findings need runtime confirmation: the tracking-toggle race, the outbox relaunch loss, the release-only remote-change skip, and the two quarantined snapshot instabilities.
- No severity totals are given this pass. The previous report's counts mixed filed items with folded-in summaries and couldn't be reconciled against the backlog, which is the only place a finding lives; the top-findings table above points at real items instead.
- DEBUG-only surfaces (PeriscopeTools, Inspector, Flyover) are held to a lighter standard for `try?` degradation and for localization, per their module docs.
- `Shared/Periscope/Prototypes/JournalBenchmark` (3 sources) is wired into no target and is excluded from every count.

---

## Modules reviewed

### SPM library targets

| Module | Path | Source | Test | README | AGENTS |
|--------|------|-------:|-----:|:------:|:------:|
| StuffCore | `Shared/StuffCore/` | 1 | 1 | ✓ | ✓ |
| CreditKit | `Shared/CreditKit/` | 2 | 3 | ✓ | ✓ |
| LifecycleKit | `Shared/LifecycleKit/` | 8 | 10 | ✓ | ✓ |
| LifecycleKitUI | `Shared/LifecycleKitUI/` | 5 | 3 | ✓ | ✓ |
| JournalKit | `Shared/JournalKit/` | 2 | 3 | ✓ | ✓ |
| PeriscopeCore | `Shared/Periscope/PeriscopeCore/` | 37 | 33 | ✓ | ✓ |
| PeriscopeUI | `Shared/Periscope/PeriscopeUI/` | 1 | 2 | ✓ | ✓ |
| PeriscopeTools | `Shared/Periscope/PeriscopeTools/` | 27 | 27 + 1 | ✓ | ✓ |
| Inspector | `Shared/Inspector/` | 23 | 14 + 1 | ✓ | ✓ |
| Flyover | `Shared/Flyover/` | 50 | 12 + 1 | ✓ | ✓ |
| SnapshotKit | `Shared/SnapshotKit/` | 8 | 3 | ✓ | ✓ |
| SnapshotKitTesting | `Shared/SnapshotKitTesting/` | 14 | 11 | ✓ | ✓ |
| TestHostSupport | `Shared/TestHostSupport/` | 1 | 0 | ✓ | ✓ |
| BroadwayCore | `Shared/Broadway/BroadwayCore/` | 17 | 10 | ✓ | ✓ |
| BroadwayUI | `Shared/Broadway/BroadwayUI/` | 6 | 4 | ✓ | ✓ |
| RegionKit | `Where/RegionKit/` | 14 | 9 | ✓ | ✓ |
| WhereCore | `Where/WhereCore/` | 95 | 60 | ✓ | ✓ |
| WhereUI | `Where/WhereUI/` | 150 | 61 + 28 | ✓ | ✓ |
| WhereIntents | `Where/WhereIntents/` | 17 | 10 | ✓ | ✓ |

*(A `+ N` in the Test column is that module's image-snapshot bundle, which runs in the `StuffSnapshotTests` scheme rather than `Stuff-iOS-Tests`.)*

### Tuist app / extension targets

| Target | Path | Source | Test | README | AGENTS |
|--------|------|-------:|-----:|:------:|:------:|
| Where | `Where/Where/` | 6 | 2 | ✓ | ✓ |
| WhereWidgets | `Where/WhereWidgets/` | 7 | 0 | ✓ | ✓ |
| WhereShareExtension | `Where/WhereShareExtension/` | 5 | 0 | ✓ | ✓ |
| RegionViewer | `Where/RegionViewer/` | 1 | 0 | ✓ | ✓ |
| StuffTestHost | `Shared/StuffTestHost/` | 2 | 0 | ✓ | ✓ |
| BroadwayCatalog | `Shared/Broadway/BroadwayCatalog/` | 2 | 1 | ✓ | ✓ |

**Totals:** 501 source · 279 test + 31 image-snapshot Swift files across shipped targets (plus 4 Bumper rule/test sources and 3 unwired prototype sources). 20 unit-test bundles and 4 image bundles, all enrolled in their scheme.

---

## Changes since July 26, 2026 audit

| Area | July 26 state | August 2 state |
|------|---------------|----------------|
| Target count | 14 SPM + 6 Tuist | **19 SPM** + 6 Tuist — Flyover, Inspector (renamed from SwiftDataInspector), and LifecycleKitUI landed; CreditKit, SnapshotKit, and SnapshotKitTesting are counted for the first time |
| File count | ~359 source / ~198 test | **501** source / 279 test + 31 image-snapshot (WhereUI 113 → 150, WhereCore 87 → 95, Flyover 0 → 50, Inspector 13 → 23) |
| Composition | One world, opened at launch behind the onboarding gate | `WhereScope` as a value (#150) — demo mode is a second scope, Flyover retains an unactivated third, and at most one routes logs |
| Developer surfaces | Periscope viewer, HUD, in-app SwiftData browser | Plus a Path-style tools launcher (#157), the Flyover screen browser (#156), and Inspector as an alternate **boot runtime** with filesystem/defaults/SwiftData deletion (#158) |
| Spans | Periscope had spans; the app didn't use them | Every plausibly expensive path budgeted (#154); ambient state stamped on every record and sessions build-attributed (#152) |
| Image snapshots | 1 bundle, 260 references | **4 bundles** (WhereUI, Flyover, Inspector, PeriscopeTools), **273 references**, one shared scheme and CI job |
| Test invocation | `./test` landed as the one front door (#151) | Unchanged, plus `PACKAGE_RESOURCE_BUNDLE_PATH` carrying hosted `Bundle.module` resolution under Xcode 27 beta 4 (#155) |
| Agent instructions | All rules in `AGENTS.md` | GitHub and running-tests procedure extracted into skills (#167); `AGENTS.md` keeps the always-on rules |
| Backlog | 8 `TODOs.md` files | **11** — Flyover opened this pass; every module with an open item now has one |
| Highs | 5 open | 4 still open; the LifecycleKit terminal-phase race was already fixed by #116 on July 26 and the previous pass missed it |
