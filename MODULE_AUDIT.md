# Swift Module Audit Report

Read-only review of all **14 SPM library targets**, **6 Tuist app/extension targets**, and the repo-owned **Bumper Bowling** architecture rules (~359 source / ~198 test Swift files across shipped targets, plus 2 unwired prototype sources). No code was changed.

**Date:** July 26, 2026  
**Method:** Read-only verification of every open July 19 finding against current source; file-count refresh; new-surface review of the week's landings (Periscope migration #94, Settings drill-in #111, developer HUD #115, navigation restructure #119, log-viewer tooling #107, String Catalog symbols #124, Gregorian calendars `fe99dde`, previews `52f0136`, Bumper Bowling #127, catalog serialization #135).  
**Prior audit:** July 19, 2026 (~308 source / ~189 test).

> **This report carries no actionable items.** Every finding it describes is filed
> in a `TODOs.md`; the root [`TODOs.md`](TODOs.md) owns the item format and says
> which file covers which area. Read this one for *shape and drift* — what each
> module verified clean, the themes running across the backlog, and how the tree
> moved since the last pass — and take the work itself from the `TODOs.md` files.
> It is true as of the header date above, **not** as of `HEAD`.

---

## Executive summary

What this pass turned up, before the findings were filed:

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

Pointers only — each one's evidence and suggested fix live in the linked file.

| # | Sev | Module | Issue | Filed in |
|---|-----|--------|-------|----------|
| 1 | **high** | Bumper Bowling | `where.gregorian_calendar` matches only an explicit `Calendar.current` base, so the rule is green while production sites drift | [`TODOs.md`](TODOs.md) P0 |
| 2 | **high** | WhereUI | `CalendarDay.displayDate` resolves through `Calendar.current`, so day labels on a non-Gregorian device render a date ~543 years off | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 3 | **high** | WhereCore | `DailySummaryReconciler.reconcile()` is absent from the post-day-change fan-out — the notification body stays stale until a foreground re-`configure` | [`Where/TODOs.md`](Where/TODOs.md) P0 |
| 4 | **high** | WhereUI | Tracking toggle race — `trackingEnabled`'s setter spawns unserialized `Task`s | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 5 | **high** | LifecycleKit | Cancel during the *last* step's `minVisible` hold isn't observed, so a superseded drive can set `phase = .ready` | [`Shared/LifecycleKit/TODOs.md`](Shared/LifecycleKit/TODOs.md) P0 |
| 6 | **medium** | WhereCore | `setPrimaryRegions(_:)` commits atomically but skips `reconcileAfterDayChange()` | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 7 | **medium** | WhereCore | `setTrackedRegion(false)` hard-deletes the row; the shipped picker now reaches it, so past-year re-attribution risk is live | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 8 | **medium** | PeriscopeCore | Orphan sweep treats an undecodable `SpanBegan` as an orphan-close candidate, silently overriding `survivesRelaunch` | [`Shared/Periscope/TODOs.md`](Shared/Periscope/TODOs.md) P1 |
| 9 | **medium** | WhereUI | Load-state UI duplicated across four views; `PresenceTimelineList` renders the *empty* state while the year is still loading | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 10 | **medium** | BroadwayCatalog | The showcase app never seeds a Broadway root, and its test bundle is an empty `struct` wired into the CI scheme | [`Shared/Broadway/TODOs.md`](Shared/Broadway/TODOs.md) P1 |

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

The String Catalog symbol migration (#124) is complete and the hand-maintained key facades are gone, so a removed key breaks the build. Remaining slips are individual, not architectural: a raw `String(localized: "region.other")` in RegionKit, a hardcoded caption in `IntentSnippets`, the parallel `share.form.*` / `evidence.form.*` namespaces, and four auto-extracted literals — three in Where's catalogs, one in LifecycleKit's.

### Infrastructure that is genuinely done

Periscope replaced LogKit/LogViewerUI outright; `.undetermined` replaced the cold-launch guess with a state that can't lie; `#Preview` coverage is complete across WhereUI/WhereWidgets; `@_spi(Testing)` is the norm for test seams (the only `…ForTesting` API is itself behind it); the SwiftData browser shipped into Settings → Developer; String Catalogs are serialized the way Xcode writes them and linted (`./xcstrings`); and `./simulator` now resolves destinations by UDID for `profile` / `flaky` / CI.

---

## Per-module notes

What each module was checked for and found clean, plus the trade-offs this pass
accepted as deliberate. Open work is in the linked `TODOs.md`.

### Bumper Bowling — architecture lint

The repo-owned rule set (`BumperBowling.swift`, `.bumper/Sources`, catalog in `.bumper/RULES.md`) covers **Where production sources only**: layer boundaries and forbidden imports, graph integrity, production store opening, checked-concurrency escape hatches, composition ownership (`WhereServices`, live `LocationSource`), the Gregorian calendar, the `store.perform` transaction boundary, `AppShortcutsProvider` ownership, the logging facade and logging-type placement, and `#Preview` coverage. Mutation tests live in `.bumper/Tests`; CI runs `config`, `test`, and `lint --timings` with every rule at `severity: .error`.

**Verified OK:** rule IDs and scopes in `RULES.md` match `WhereProjectRules.swift`; the component graph matches `BumperBowling.swift` / `WhereArchitecture.swift`; Broadway is forbidden on WhereIntents/WhereWidgets via `forbidden_import`, matching `Project.swift`.

**Files:** 4 rule/test sources · RULES.md ✓ · Open: [`TODOs.md`](TODOs.md)

---

### WhereCore

**Verified OK:** backup import → full fan-out via `onImport`; summary format args (guarded by `summaryBodyContainsNoFormatPlaceholders`); `BackupError` localization; drain-only ingest skipping the full reminder reconcile; no raw-string/`os.Logger` logging left; no PII in `.public` events; `RecentActivitySummarizer`'s typed unavailability and segment cap.

**Files:** 87 source / 58 test · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereUI

**Verified OK:** no closure `Binding(get:set:)` anywhere in the module (`SaveErrorAlertState`, `AddEvidenceModel`, `AppIconModel` expose computed `get`/`set`); every load-state `switch` enumerates its cases; `MainTabs` drives `YearReportModel.activate()` / `deactivate()` off `scenePhase`; every previewable `View`/`Widget` ships an in-file `#Preview`; `README.md` and `AGENTS.md` are current on the three-tab shape.

**Files:** 113 source / 36 test · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### LifecycleKit

**Verified OK:** cancel-and-drain no longer waits out the full `minVisible` window; duplicate step-ID `precondition`; localized `LifecycleFailureView`; background *and* `.undetermined` promotion container tests. The `.undetermined` state machine (#109) holds up: `completedStepIDs` records only steps that ran to completion, so a promotion re-drive skips finished work while still running newly-applicable steps, and promotion/teardown both funnel through the same cancel-and-drain.

**Files:** 9 source / 11 test · README ✓ · AGENTS ✓ · Open: [`Shared/LifecycleKit/TODOs.md`](Shared/LifecycleKit/TODOs.md)

---

### SwiftDataInspector

**Verified OK:** pagination + lazy rendering with regression tests; relationship resolution for materialized models.

**Accepted:** `try?` on fetches yields empty rows/counts (documented DEBUG degradation); a bare `default:` in `defaultFormat` over `Any` (open-type dispatch).

**Files:** 13 source / 1 test · README ✓ · AGENTS ✓ · Open: [`Shared/SwiftDataInspector/TODOs.md`](Shared/SwiftDataInspector/TODOs.md)

---

### PeriscopeCore, PeriscopeUI, PeriscopeTools

**Verified OK:** Broadway does not leak below PeriscopeTools; no test touches `Periscope.shared`; `@_spi(Testing)` used for injection hooks; span-pair floors, rollback-on-failed-save, and the seeded lifecycle fuzz all still in place. PeriscopeUI is a thin DEBUG bridge with nothing outstanding.

**Files:** PeriscopeCore 35/31 · PeriscopeUI 1/2 · PeriscopeTools 24/22 · README ✓ · AGENTS ✓ · Open: [`Shared/Periscope/TODOs.md`](Shared/Periscope/TODOs.md)

---

### JournalKit, StuffCore, TestHostSupport, StuffTestHost

**JournalKit:** strong fuzz/truncation coverage. **Files:** 2/3 · README ✓ · AGENTS ✓ · Open: [`Shared/JournalKit/TODOs.md`](Shared/JournalKit/TODOs.md)

**StuffCore:** intentional scaffold. **Files:** 1/1 · README ✓ · AGENTS ✓ · Open: [`Shared/StuffCore/TODOs.md`](Shared/StuffCore/TODOs.md)

**TestHostSupport:** dependency-free UIKit helpers; no dedicated bundle by design (exercised via hosted bundles), nothing open. **Files:** 1/0 · README ✓ · AGENTS ✓

**StuffTestHost:** the WhereCore-always-embedded trade-off is documented and verified load-bearing in `Project.swift:256`; the smoke test lives in `LifecycleKitTests`. **Files:** 2/0 · README ✓ · AGENTS ✓ · Open: [`TODOs.md`](TODOs.md) (both items reach the root Tuist manifest)

---

### BroadwayCore, BroadwayUI, BroadwayCatalog

**Verified OK:** stylesheet/trait/cycle behavior well tested; trait registration pairs with teardown.

**Accepted:** a bare `default:` mapping unknown `UIContentSizeCategory` to `.large` (`BTraits+Values.swift:125`, a deliberate fallback); hardcoded English in the catalog app (internal showcase).

**Files:** BroadwayCore 17/10 · BroadwayUI 6/4 · BroadwayCatalog 2/1 · README ✓ · AGENTS ✓ · Open: [`Shared/Broadway/TODOs.md`](Shared/Broadway/TODOs.md)

---

### RegionKit & RegionViewer

**Verified OK:** the per-region catalog drives `RegionStyle`, the pickers, and the App Intents `RegionEntity` with no `Region` enum left to extend. RegionViewer ships no test bundle by design.

**Files:** RegionKit 13/8 · RegionViewer 1/0 · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereIntents

**Verified OK:** reader/writer seams well tested (`WhereIntentReaderTests`, `WhereIntentWriterTests`); `IntentServices` handoff still covered by `IntentServicesTests` (install/park/cancel/replace) with no self-creating fallback; no Broadway double-link.

**Accepted:** the per-intent `perform()` glue is untested because `@Dependency` traps outside the perform flow — the open item is to extract a seam or say so in `README.md`.

**Files:** 17/9 · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereWidgets & WhereShareExtension

**Verified OK:** `SharedItemLoader` logs load failures at `warning`; widget gallery strings localized; `@unknown default:` on widget-family switches; no Broadway double-link in either target. The post-midnight stale snapshot is explicitly documented as intentional degradation in the provider, `README.md`, and `AGENTS.md`.

**Accepted:** neither target ships a test bundle (documented).

**Files:** WhereWidgets 7/0 · WhereShareExtension 5/0 · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### Where app

**Verified OK:** `Where/Where/README.md` now exists and matches the three-file shell; `WhereTests` pins `.undetermined` as the launch reason under the UIScene lifecycle; delegate wiring smoke test; no Broadway double-link. Nothing open.

**Files:** 3/1 · README ✓ · AGENTS ✓

---

## Limitations

- Static analysis only — no `tuist test`, `bumper lint`, or simulator runs in this pass (the Cloud agent runs Linux; the full suite requires macOS CI). CI status on `main` was read via `gh` and is green, which is what lets the "the Gregorian rule finds nothing" conclusion stand.
- Some findings (the LifecycleKit terminal-phase race, the tracking toggle, outbox relaunch loss) need runtime confirmation.
- Severity counts are approximate — several low-severity 1:1 test gaps are folded into module summaries rather than filed individually.
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
| Backlog | Findings split between this file and two `TODOs.md` | One backlog across eight `TODOs.md`; this report is derived and carries no items |
