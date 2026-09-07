# Swift Module Audit Report

Review of all **20 SPM library targets**, **7 Tuist app/extension targets**, **25 test bundles**, the repo-owned **Bumper Bowling** architecture rules, and the retained Python/Ruby tooling layer (704 source / 369 test / 49 image-snapshot Swift files across shipped targets, plus 2 unwired prototype sources). No production behavior was changed.

**Date:** September 6, 2026  
**Method:** Re-verification of every open finding in all 12 `TODOs.md` files against current source, using the prior same-day audit as the baseline for paths untouched since it; a fresh file, reference-image, and suite count; and code plus visual review of the one commit landed after that audit. Executed on this pass: `./swiftformat --lint`, `./shellcheck`, `./attribution --check`, `./sync-agents`, both retained-tool test suites, and `./snapshot-shards check`. Representative joined, separated, and AX5 Timeline references were inspected directly.
**Prior audit:** September 6, 2026, merged as PR #308 at `3daba8fb`. This same-day follow-up covers the one later commit, PR #307 (`1e9c9289`).

> **This report carries no actionable items.** Every finding it describes is filed
> in a `TODOs.md`; the root [`TODOs.md`](TODOs.md) owns the item format and says
> which file covers which area. Read this one for *shape and drift* — what each
> module verified clean, the themes running across the backlog, and how the tree
> moved since the last pass — and take the work itself from the `TODOs.md` files.
> It is true as of the header date above, **not** as of `HEAD`.

---

## Executive summary

**A same-day follow-up caught one merged feature that landed after the weekly audit.** PR #307 rewrote the Timeline's planned-stay presentation, added the Estimated Time panel, four focused rendering helpers, and six references after PR #308's audit baseline. The change moved two open-item citations without closing either issue, and introduced one narrow coverage gap: the joined planned-stay card has an accessibility-only layout branch but no AX5 image case. The pass also finished the stale onboarding-gate documentation item filed by the prior audit, correcting every repeated claim rather than only the originally cited comment.

What the pass found, in order of how much it should change your reading of the backlog:

- **PR #307 held the domain boundary.** Its adjacency decision uses typed `CalendarDay` values and the injected report calendar; persistence, forecast math, and plan mutation remain in `LocationForecastModel`/WhereCore. It added no `Calendar.current`, raw SF Symbol names, user-facing string literals, or store access.
- **The visual states checked clean.** The joined New York continuation reads as one segmented card, the different-region case keeps full corners and rail separation, and the full-content captures include the trailing Estimated Time panel without clipping. The source keeps VoiceOver order aligned with visual order and preserves a semantic accessibility capture.
- **The accessibility rendering branch is unpinned.** `PlannedPresenceJourneyCardContent` restacks its joined labels and day count when the stylesheet resolves AX Dynamic Type, but the planned-stay case covers only standard-size light/dark plus a semantic accessibility capture. The existing AX5 Timeline case contains no plan, so it cannot execute the new branch. Filed as a WhereUI quick win.
- **The previous audit's documentation finding is closed.** `OnboardingGate` follows a side-effect-free demo preflight and still precedes every store/session-building step. `WhereLaunchSteps`, `OnboardingView`, `RootView`, `WhereLaunchTests`, and the WhereUI README now state that precise boundary.
- **Counts moved only where PR #307 moved them.** WhereUI is 285 source files, the repo is 704, and the six new planned-stay images take the LFS reference total from 484 to 490. Test files, image-suite files, suite assignments, and test bundles are unchanged.

---

## Top findings

Pointers only — each one's evidence and suggested fix live in the linked file.

| # | Module | Issue | Filed in |
|---|--------|-------|----------|
| 1 | Bumper Bowling | `where.gregorian_calendar` matches only an explicit `Calendar` base, so it reports none of the 12 implicit `.current` sites — and its own mutation test only feeds it the explicit form, which is why it has now survived six audits | [`TODOs.md`](TODOs.md) P0 |
| 2 | WhereCore | `DailySummaryReconciler.reconcile()` is absent from the post-day-change fan-out — the daily notification body stays stale until a foreground re-`configure` | [`Where/TODOs.md`](Where/TODOs.md) P0 |
| 3 | PeriscopeCore | Records emitted before the store attaches reach neither the store nor the journal — the durable log has a hole at every launch | [`Shared/Periscope/TODOs.md`](Shared/Periscope/TODOs.md) P0 |
| 4 | WhereUI | `CalendarDay.displayDate` resolves through `Calendar.current`; four production sites remain, and every day label flows through them | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 5 | CI / docs | The snapshot suite's "never parallelize this" warning is still absent from the file that now reads `parallelism: 4` | [`TODOs.md`](TODOs.md) P1 |
| 6 | Scripts | The retained-tool suites are CI's only Xcode-free gate and pass only on macOS — a hardcoded `126` exit status, a hermetic `PATH` that needs a system Ruby, and `sync-agents` unable to find Ruby at all | [`TODOs.md`](TODOs.md) P1 |
| 7 | WhereUI | Notification authorization is requested unprompted during launch, and all three preferences default to `true` on a fresh install | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 8 | WhereCore | Untracking a region hard-deletes the row, so re-aggregating a past year re-attributes its GPS days to `.other`; both shipped pickers reach it | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 9 | SnapshotKit | A case's content is built once and re-hosted for every configuration, while both the type's doc comment *and* its `AGENTS.md` tell authors each access is independent | [`Shared/SnapshotKit/TODOs.md`](Shared/SnapshotKit/TODOs.md) P1 |
| 10 | Bumper Bowling | `duplicate_ownership` and `declared_dependency_cycle` have no mutation test, so neither has been shown to fail on a violating tree | [`TODOs.md`](TODOs.md) P1 |

The nearest dated deadline in the backlog is external: the `kve-stuff` benchmark organization's paid plan downgrades on **September 9, 2026** — three days after this audit — and its deletion item is a root P1.

---

## Cross-cutting themes

The synthesis across items that no single item shows.

### Same-day audits need a commit boundary, not only a date

The existing header date was still current when PR #307 landed after PR #308. A date-only window would therefore have reported no new surface even though 43 files had changed. This pass names both boundary commits and treats `3daba8fb..1e9c9289` as the source window. Weekly dates remain useful for cadence; commit boundaries are the only unambiguous input when merges race the audit on the same day.

### Coverage follows representative states, so conditional branches can hide inside a covered screen

`PresenceTimelineList` remains one of the best-covered screens: its representative state uses the full screen-default matrix, its planned states use focused light/dark cases, and the joined state has a semantic accessibility capture. That still leaves the new AX-only layout branch unexecuted because the representative state contains no plan and the planned state contains no AX Dynamic Type configuration. "The screen has AX coverage" and "this AX branch has coverage" are different claims. The new backlog item names the branch and the smallest matrix addition that reaches it.

### Documentation drift propagates by repetition

The onboarding-gate item cited one stale comment, but the same "roots the trunk" claim had spread into `OnboardingView`, `RootView`, `WhereLaunchTests`, and the module README. Fixing only the cited line would have left four authoritative-looking copies to reintroduce it. The completed item now records the semantic statement worth preserving: the gate follows a side-effect-free preflight and precedes every step that can build a user world.

---

## Per-module notes

What each module was checked for and found clean, plus the trade-offs this pass accepted as deliberate. Open work is in the linked `TODOs.md`.

### Repository tooling — dev scripts, retained Python/Ruby, CI

Nothing shipped. **18 root commands**, `./test` at 722 lines, 7 Python + 5 Ruby retained modules with 21 test files under `Tools/Tests`.

**Verified OK, by running it:** `./swiftformat --lint` reports 0 of 1,129 files needing formatting; `./shellcheck` is silent; `./attribution --check` reports the report up to date at 12 credits; `./sync-agents` refreshes the generated SnapshotKitTesting instructions; `./snapshot-shards check` validates 49 suites (13/15/18 planned + 3 intake); and all 64 retained Python tests pass. The 75-test Ruby suite has one environment-only failure: under the test's isolated `HOME`, Apple's `/usr/bin/python3` emits Xcode cache/FSEvents diagnostics before `snapshot-shards --help`; the same command exits cleanly and prints only usage outside that harness. No command contract changed in this window.

**Files:** 18 root commands · 7 Python / 5 Ruby retained modules · 21 tool test files · Open: [`TODOs.md`](TODOs.md)

---

### Bumper Bowling — architecture lint

Nothing shipped. Covers **Where production sources only** (`BumperBowling.swift:15-23`); CI hard-gates it through `./test --architecture-only` (`.github/workflows/ci.yml:72-73`), and CircleCI passes `--skip-architecture` so it does not run twice.

**Verified OK:** still ten `where.*` rules, each in `.bumper/RULES.md`, with eleven mutation-test functions; `component_boundary` and `forbidden_import` mutation-tested. The two graph assertions without mutation tests are unchanged and filed.

**Files:** 4 rule/test sources · RULES.md ✓ · Open: [`TODOs.md`](TODOs.md)

---

### WhereCore

Nothing shipped after the prior audit. PR #307 consumes existing typed forecast and planned-stay APIs without changing them.

**Verified OK:** the new Timeline surface keeps adjacency presentation-only and passes typed `CalendarDay`, `Region`, and the injected Gregorian report calendar through the view boundary. Forecast math, persistence, and mutations remain in the existing model/Core seams.

**Standing:** the three fan-out and lifecycle items (summary reconcile, `setPrimaryRegions`, hard-deleting untrack) have now survived every pass since July 26, re-confirmed against current source with no drift — WhereCore's citations, down to `SwiftDataStore.swift:1844-1875`, verified exactly.

**Files:** 128 source / 83 test · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereUI

PR #307 added four Timeline rendering helpers, expanded `PresenceTimelineList`, and added six references. Tests and snapshot-suite files are unchanged.

**Verified OK:** joined stays require both the same typed region and next-day adjacency; nonconsecutive and different-region plans remain standalone. The estimate panel reuses the Calendar component and the same model actions. Representative joined, separated, and AX5 references show intact full-content sizing, rail order, forecast chrome, and Dynamic Type behavior for the non-plan state. No new code uses `Calendar.current`, raw SF Symbol strings, unlocalized user copy, store I/O, or ad-hoc design constants outside the owning stylesheet.

**Re-verified:** the Timeline still maps a missing report to an empty stint list and renders the no-stays state while loading; its citations moved. The four production plus eight DEBUG-fixture Gregorian-calendar sites are unchanged.

**Filed:** the joined planned-stay card's AX-only stacked layout has no AX5 image configuration.

**Closed:** the stale onboarding-gate wording, across every repeated comment and the module README.

**Accepted:** `WhereSession` remains exactly 636 lines — stable, but not being worked down.

**Files:** 285 source / 103 test / 46 image-snapshot · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereCrashReporting

Nothing shipped. **Files:** 3 source / 2 test · README ✓ · AGENTS ✓ · Open: nothing filed

---

### PeriscopeCore, PeriscopeUI, PeriscopeTools

Nothing shipped. All 20 items still open; every key citation verified, one drifted (`PeriscopeToolsSnapshotTests` wiring is `Project.swift:627-633`).

**Verified OK:** the hosting-smoke debt held at **20 tests across 10 files for a third consecutive audit** — every cited site re-confirmed individually; `PeriscopeViewerSnapshotTests` is still the only file in the module's image bundle (2 references); `Periscope.swift` and `PeriscopeStore.swift` held at 935 and 1,235 lines; `StoredLogEvent` still carries `spanID` and `spanExitMode` but not `spanRelaunchPolicy`, exactly as the span-record item's 2026-08-09 correction states.

**Files:** PeriscopeCore 38/33 · PeriscopeUI 1/2 · PeriscopeTools 27/27 (+1 image source, 2 references) · README ✓ · AGENTS ✓ · Open: [`Shared/Periscope/TODOs.md`](Shared/Periscope/TODOs.md)

---

### Flyover

Nothing shipped after the prior audit. Counts re-confirmed: 14 test files, 5 references, one image case.

**Files:** 54 source / 14 test / 1 image source, 5 references · README ✓ · AGENTS ✓ · Open: [`Shared/Flyover/TODOs.md`](Shared/Flyover/TODOs.md)

---

### Inspector

Nothing shipped; all four items remain open and their citations hold. The `withKnownIssue` quarantine on the dark SwiftData capture is still one of exactly **two** in the repo (the other guards WhereUI's Elsewhere inflection bug).

**Files:** 23 source / 14 test / 1 image source, 4 references · README ✓ · AGENTS ✓ · Open: [`Shared/Inspector/TODOs.md`](Shared/Inspector/TODOs.md)

---

### SnapshotKit & SnapshotKitTesting

PR #303 replaced the async-capture regression's wall-clock-delayed placeholder with settle-pass accounting — the test now proves the final settle loop ran by counting passes through the non-emitting `SnapshotCaptureTiming` payload instead of racing a 100 ms task against the pixel loop. That is the module's own documented philosophy ("pixel stability cannot become a readiness signal") applied to its own test, and it closes nothing in the backlog because nothing had filed it.

**Verified OK:** the framework halves stay split; the reporting channels still separate `report(...)`/`emit()` from `line(...)`; the content-built-once contradiction (item 9 above) is byte-for-byte unchanged in the code, the doc comment, and the `AGENTS.md` bullet.

**Refreshed here:** the settle-floor split remains **39** addressable configurations, and the dated reference counts in `AGENTS.md` now reflect the six additions from PR #307: 490 as of this audit.

**Files:** SnapshotKit 8/3 · SnapshotKitTesting 16/16 · README ✓ · AGENTS ✓ · Open: [`Shared/SnapshotKit/TODOs.md`](Shared/SnapshotKit/TODOs.md), [`Shared/SnapshotKitTesting/TODOs.md`](Shared/SnapshotKitTesting/TODOs.md)

---

### LifecycleKit & LifecycleKitUI

Nothing shipped. The single P2 stands, citations unchanged.

**Files:** LifecycleKit 8/10 · LifecycleKitUI 6/4 · README ✓ · AGENTS ✓ · Open: [`Shared/LifecycleKit/TODOs.md`](Shared/LifecycleKit/TODOs.md) (LifecycleKitUI's items live in LifecycleKit's file by design)

---

### Broadway (BroadwayCore, BroadwayUI, BroadwayCatalog)

Nothing shipped. All eight items still open; the two `Project.swift` citations drifted (target block now `:660-669`, scheme listings `:748`/`:771`) because targets above them were removed with StuffCore, not because anything Broadway changed.

**Files:** BroadwayCore 17/10 · BroadwayUI 6/4 · BroadwayCatalog 2/1 · README ✓ · AGENTS ✓ · Open: [`Shared/Broadway/TODOs.md`](Shared/Broadway/TODOs.md)

---

### Ledger, LedgerCore

Nothing shipped after the prior audit; all three P2s and their citations are unchanged.

**Files:** LedgerCore 16/14 · Ledger 8/0 · README ✓ · AGENTS ✓ (leaf modules; the **group** folder is missing both — filed) · Open: [`Ledger/TODOs.md`](Ledger/TODOs.md)

---

### RegionKit & RegionViewer

Nothing shipped; citations hold, including the honestly-stated GeoJSON coverage gap.

**Files:** RegionKit 15/10 · RegionViewer 1/0 · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereIntents, WhereWidgets, WhereShareExtension, Where app

Nothing shipped in these targets after the prior audit. PR #307 is contained in WhereUI.

**Verified OK:** runtime selection still happens exactly once at process initialization; Inspector recovery remains authoritative over a conflicting demo request (`completePendingStoreErasures` re-schedules Inspector on failure); the `IntentServices` handoff still has no self-creating fallback.

**Corrected here:** the WhereIntents polish item's doc citations pointed past the end of both rewritten files (`AGENTS.md` is 90 lines; the item cited `:95-108`), and `WhereShortcuts` has registered four shortcuts, not five, since PR #230 — a count no pass had re-derived in five audits.

**Files:** WhereIntents 15/9 · WhereWidgets 7/0 · WhereShareExtension 5/0 · Where 8/4 · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### CreditKit, JournalKit, TestHostSupport, StuffTestHost

**CreditKit:** `./attribution --check` passes at **12** credits. The one open item's path citation was wrong — the generator lives at `Shared/CreditKit/Tools/generate-attribution.rb`, not root `Tools/` — corrected. **Files:** 2/3 · Open: [`Shared/CreditKit/TODOs.md`](Shared/CreditKit/TODOs.md)

**JournalKit:** nothing shipped. Both test items still open at their exact lines. **Files:** 2/3 · Open: [`Shared/JournalKit/TODOs.md`](Shared/JournalKit/TODOs.md)

**TestHostSupport:** dependency-free UIKit helpers, no bundle by design. **Files:** 1/0 · nothing open

**StuffTestHost:** unchanged. **Files:** 2/0 · nothing open

---

## Limitations

- **Mostly static, partly executed.** This local macOS pass ran agent sync, SwiftFormat, ShellCheck, attribution, the retained tool suites, and the snapshot-shard validator. `./test` was skipped because this PR changes Markdown and comments only; no executable Swift or rendered copy changed. The architecture lint and simulator suites were likewise not run.
- **One retained Ruby contract test failed because of the automation sandbox, not repository output.** Its deliberately isolated `HOME` makes Apple's `/usr/bin/python3` emit Xcode cache/FSEvents diagnostics before `snapshot-shards --help`. Running that command normally in the same checkout is clean. The 64 Python tests pass.
- **The "the Gregorian rule finds nothing" conclusion rests on unchanged source and green main CI**, not on running the lint here. The mechanism (the rule's filter plus its one-sided mutation test) remains sufficient on its own; CI is corroboration.
- **Snapshot review was representative, not exhaustive.** Joined, different-region, and AX5 Timeline references were inspected. Reference counts come from full file enumeration, but all 33 modified and 6 added images from PR #307 were not opened individually.
- **Runtime-dependent items are unconfirmed by design**: the launch-time notification prompt, Flyover's log routing, multi-process journal coordination, the CloudKit import-readiness race, the demo mode's end-to-end cold launch beyond what its unit tests prove, and Ledger's live API and Keychain paths. Each says so in its own entry.
- **No item counts by severity.** They could not be reconciled against the backlog in earlier revisions and remain deliberately omitted rather than estimated.
- `Shared/Periscope/Prototypes/JournalBenchmark` (2 sources) is wired into no target and is excluded from every count here.

---

## Modules reviewed

### SPM library targets

| Module | Path | Source | Test | Image | README | AGENTS |
|--------|------|-------:|-----:|------:|:------:|:------:|
| CreditKit | `Shared/CreditKit/` | 2 | 3 | — | ✓ | ✓ |
| JournalKit | `Shared/JournalKit/` | 2 | 3 | — | ✓ | ✓ |
| LifecycleKit | `Shared/LifecycleKit/` | 8 | 10 | — | ✓ | ✓ |
| LifecycleKitUI | `Shared/LifecycleKitUI/` | 6 | 4 | — | ✓ | ✓ |
| SnapshotKit | `Shared/SnapshotKit/` | 8 | 3 | — | ✓ | ✓ |
| SnapshotKitTesting | `Shared/SnapshotKitTesting/` | 16 | 16 | — | ✓ | ✓ |
| Inspector | `Shared/Inspector/` | 23 | 14 | 1 | ✓ | ✓ |
| Flyover | `Shared/Flyover/` | 54 | 14 | 1 | ✓ | ✓ |
| TestHostSupport | `Shared/TestHostSupport/` | 1 | 0 | — | ✓ | ✓ |
| BroadwayCore | `Shared/Broadway/BroadwayCore/` | 17 | 10 | — | ✓ | ✓ |
| BroadwayUI | `Shared/Broadway/BroadwayUI/` | 6 | 4 | — | ✓ | ✓ |
| PeriscopeCore | `Shared/Periscope/PeriscopeCore/` | 38 | 33 | — | ✓ | ✓ |
| PeriscopeUI | `Shared/Periscope/PeriscopeUI/` | 1 | 2 | — | ✓ | ✓ |
| PeriscopeTools | `Shared/Periscope/PeriscopeTools/` | 27 | 27 | 1 | ✓ | ✓ |
| RegionKit | `Where/RegionKit/` | 15 | 10 | — | ✓ | ✓ |
| WhereCore | `Where/WhereCore/` | 128 | 83 | — | ✓ | ✓ |
| WhereUI | `Where/WhereUI/` | 285 | 103 | 46 | ✓ | ✓ |
| WhereIntents | `Where/WhereIntents/` | 15 | 9 | — | ✓ | ✓ |
| WhereCrashReporting | `Where/WhereCrashReporting/` | 3 | 2 | — | ✓ | ✓ |
| LedgerCore | `Ledger/LedgerCore/` | 16 | 14 | — | ✓ | ✓ |

### Tuist app / extension targets

| Target | Path | Source | Test | README | AGENTS |
|--------|------|-------:|-----:|:------:|:------:|
| Where | `Where/Where/` | 8 | 4 | ✓ | ✓ |
| WhereWidgets | `Where/WhereWidgets/` | 7 | 0 | ✓ | ✓ |
| WhereShareExtension | `Where/WhereShareExtension/` | 5 | 0 | ✓ | ✓ |
| RegionViewer | `Where/RegionViewer/` | 1 | 0 | ✓ | ✓ |
| Ledger | `Ledger/Ledger/` | 8 | 0 | ✓ | ✓ |
| StuffTestHost | `Shared/StuffTestHost/` | 2 | 0 | ✓ | ✓ |
| BroadwayCatalog | `Shared/Broadway/BroadwayCatalog/` | 2 | 1 | ✓ | ✓ |

**Totals:** 704 source · 369 test · 49 image-snapshot Swift files across shipped targets (plus 4 Bumper rule/test sources and 2 unwired prototype sources). **490** LFS-backed reference images (479 WhereUI, 5 Flyover, 4 Inspector, 2 PeriscopeTools) across **49** snapshot suites (48 suite files plus the cross-boundary flag probe). **25** test bundles: 21 unit (20 in `Stuff-iOS-Tests` — the scheme's `testAction` list — plus `LedgerCoreTests` in `Ledger-macOS-Tests`) and 4 image (`StuffSnapshotTests`) — every one is a member of a CI scheme.

**Group-folder docs:** every one of the 27 module folders above carries its `README.md` + `AGENTS.md` pair. At the *group* level, `Shared/Broadway/` and `Shared/Periscope/` carry the required pair; `Where/` has `AGENTS.md` but **no `README.md`**, and `Ledger/` has **neither** — both filed in the root [`TODOs.md`](TODOs.md).

---

## Changes since the September 6, 2026 audit at `3daba8fb`

| Area | Prior same-day audit | Current state |
|------|----------------------|---------------|
| New surface | Through PR #308's base | **PR #307** — joined continuous planned Timeline stays and a trailing Estimated Time panel |
| File count | 700 source / 369 test / 49 image-snapshot | **704 / 369 / 49** — four focused WhereUI rendering helpers added |
| Backlog movement | 12 files | **1 filed, 1 closed, 2 citations refreshed** — joined-card AX5 coverage filed; onboarding-gate wording closed; Timeline loading/Gregorian citations moved |
| Image coverage | 4 bundles, 484 references, 49 suites | **4 bundles, 490 references, 49 suites** — six focused planned-stay references; shard plan remains 13/15/18/3 |
| Test bundles | 25 | **25**, unchanged |
| Documentation | Onboarding gate still described as the trunk root | **Preflight/gate boundary corrected** in source docs, tests, and the WhereUI README |
| Backlog files | 12 `TODOs.md` | **12**, unchanged |
