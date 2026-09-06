# Swift Module Audit Report

Read-only review of all **20 SPM library targets**, **7 Tuist app/extension targets**, **25 test bundles**, the repo-owned **Bumper Bowling** architecture rules, and the retained Python/Ruby tooling layer (700 source / 369 test / 49 image-snapshot Swift files across shipped targets, plus 2 unwired prototype sources). No production code was changed.

**Date:** September 6, 2026  
**Method:** Read-only verification of every open finding in all 12 `TODOs.md` files against current source, module-by-module, with each citation re-derived; file, reference-image, and suite-count refresh; new-surface review of the 4 commits since the last audit; and a pass over the window's new code against the repo's own written rules. Executed on this pass: `./swiftformat --lint`, `./shellcheck`, `./attribution --check`, both retained-tool test suites, and `./snapshot-shards check` — the last of which confirmed by running it that the window's two new snapshot suites landed on the intake shard exactly as the sharding design intends. Several candidate findings from the new surface were raised and rejected against source; the load-bearing rejections are recorded below.  
**Prior audit:** August 30, 2026, merged as PR #299. A one-week window of 4 commits — the smallest since this report began.

> **This report carries no actionable items.** Every finding it describes is filed
> in a `TODOs.md`; the root [`TODOs.md`](TODOs.md) owns the item format and says
> which file covers which area. Read this one for *shape and drift* — what each
> module verified clean, the themes running across the backlog, and how the tree
> moved since the last pass — and take the work itself from the `TODOs.md` files.
> It is true as of the header date above, **not** as of `HEAD`.

---

## Executive summary

**The quietest window yet — and the loudest week for the audit's own error ledger.** Four PRs landed: a DEBUG next-launch demo mode (#301), a visa-sticker redesign of the Locations card estimates (#302), a Settings region editor (#305), and a snapshot-pipeline test made deterministic (#303). Nothing closed a backlog item outright, but #305 shrank the largest counted item in the backlog — the Settings screens with no image coverage — from five to four by giving the rewritten `RegionsSettingsView` a `SnapshotProviding` conformance and a ten-reference suite on arrival. That is the third window out of four in which backlog movement came from feature work touching the cited code rather than from anyone reading the list.

What the pass found, in order of how much it should change your reading of the backlog:

- **Five of the previous audit's published numbers were wrong at its own date.** Re-deriving every count from the tree (rather than diffing forward from the report) found: WhereUI held 276 sources and 102 test files on August 30, published as 274 and 101; the repo-wide totals were 695/368, published as 694/368 with a module table summing to 693; the test-bundle count was 25 — PR #300's StuffCore removal had already taken `Stuff-iOS-Tests` to 20 targets — published as "26, unchanged" with "21 in Stuff-iOS-Tests"; the settle-floor item's "37 addressable configurations, re-derived and unchanged" missed the Ranking Animation Lab's 2, so the real figure was 39 then and is 39 now; and the report's own Method line shipped with a sentence duplicated wholesale. None of these changes a priority, but four of the five had been *re-derived* by the prior pass and still came out wrong — the recount discipline is necessary but evidently not sufficient when the recount trusts the previous edition's scope.
- **A stale count five windows old surfaced only because a subagent counted rather than confirmed.** The `WhereShortcuts` polish item has said "registers five" since it was filed; the file has registered four since PR #230 retired the recent-activity shortcut in mid-August. Every intervening pass verified the item's *claim* (LogTripIntent unregistered — true) without re-deriving its *counts*. Corrected in place.
- **PR #301's demo mode is the window's model citizen, verified rather than assumed.** The next-launch latch copies the Inspector runtime's DI pattern (a dedicated `UserDefaults` suite, mutual exclusivity, one-shot consumption before the onboarding gate), the demo scope stays fully in-memory, Spotlight indexing is skipped, the new sheet arrived with snapshot coverage and localized DEBUG copy, and the module docs were updated in the same change and match the code. The pass raised and rejected five false-alarm candidates against it (recorded below) and filed two small real ones: its snapshot case captures a scrolling `Form` at a fixed device frame against the full-content rule, and the `OnboardingGate` doc comment still says the gate roots the trunk that the demo step now heads.
- **PR #302 orphaned a formatter.** The sticker redesign builds the estimate from `WhereFormat.dayCount` plus a catalog label, leaving `WhereFormat.locationCardEstimatedDays`, its `"Estimated · %@"` key, and its test with no production caller — dead-but-tested API that reads as live. Filed.
- **The sharding design's first live exercise worked.** `./snapshot-shards check` reports 49 suites with the intake shard at 3 — the two new suites (`DeveloperDemoLaunchSheetSnapshotTests`, `RegionsSettingsViewSnapshotTests`) were picked up by intake rather than silently going unrun, which is precisely the behavior the intake shard exists to provide. First time this pass could verify it by execution rather than by reading the plan.

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

### The audit's error ledger is now its own dataset, and it has a shape

Six editions in, every pass has corrected numbers the previous one published, and this pass corrected five (see the executive summary). The errors are not random: every one is an *undercount or a stale carry* in a figure whose claim ("re-derived", "unchanged") asserted freshness. The two prior enumerations of addressable settle-floor configurations both re-derived the same 37 and both missed the same case, because re-derivation used the previous edition's *list of places to look* rather than a scope query; the bundle count said "unchanged" in the same edition whose own summary described the PR that changed it. The correction that works is the one the `SnapshotProviding` item adopted two windows ago — record the derivation *procedure* in the item, not the result — and this pass extended it to the settle-floor split (the item now says why the lab case belongs in scope) and the bundle count (derived from the scheme's `testAction` list, quoted in the item's evidence). A number without its derivation is a claim; a number with one is a check.

### Proximity to the code closes items that priority does not

`RegionsSettingsView` had been one of the "screens with no image coverage" since the item was filed; PR #305 rewrote the screen for product reasons and the coverage arrived as a side effect of the module's own convention ("a new screen declares `SnapshotProviding` on arrival") being applied to what was effectively a new screen. The same mechanism closed the ranking-reorder P2 in the previous window and the `LocationsView` matrix gap before that. The three-of-four-windows pattern strengthens the standing suggestion: the backlog's leverage point is surfacing an area's open items *when a team is about to work in that area*, because the convention machinery then does the closing for free. The corollary also held this window: the areas nothing touched (Periscope, Broadway, Ledger, JournalKit, LifecycleKit, Inspector, Flyover) moved by exactly zero items.

### A quiet window localizes drift, and the drift map matches the diff map

Every citation that moved this pass moved inside a file the window's four PRs rewrote — `WhereLaunch`/`WhereLaunchSteps` under the demo step, `LocationsView`/`WhereFormat`/`WhereFormatTests` under the sticker redesign, `SettingsView` under the region editor — plus two standing errors that predate the window (the WhereIntents doc cites that pointed past the end of both files, and the CreditKit generator's path). Items citing untouched files verified byte-for-byte, all the way down to line numbers in 1,235-line files. That is the strongest evidence yet that the weekly cadence is right-sized: a one-week window makes citation drift a mechanical, diff-guided fix rather than the bulk of the work it was in the two-week August 9 edition.

### DEBUG surfaces are held to production conventions, and it shows in both directions

The window's entire feature surface is developer tooling or DEBUG-adjacent, and the conventions held anyway: the demo sheet's copy is localized (the WhereUI standard for DEBUG UI, unlike the shared Flyover/Inspector tools' deliberate English), the launch controller is injected rather than global, the lab and sheet ship image coverage. The two real findings the window produced are also convention findings on DEBUG code — a fixed frame on a scrolling `Form`, a stale doc comment — which is the system working: the rules are cheap to apply at authoring time and expensive to retrofit, so a repo that applies them to its throwaway surfaces keeps them enforceable on its shipping ones.

---

## Per-module notes

What each module was checked for and found clean, plus the trade-offs this pass accepted as deliberate. Open work is in the linked `TODOs.md`.

### Repository tooling — dev scripts, retained Python/Ruby, CI

Nothing shipped. **18 root commands**, `./test` at 722 lines, 7 Python + 5 Ruby retained modules with 21 test files under `Tools/Tests`.

**Verified OK, by running it:** `./swiftformat --lint` reports 0 of 1,125 files needing formatting; `./shellcheck` is silent; `./attribution --check` reports the report up to date at 12 credits; `./snapshot-shards check` validates the plan at 49 suites (13/15/18 planned + 3 intake). The retained-tool suites reproduce exactly the failure signature the root P1 documents — 1 of 64 Python and 12+1 of 75 Ruby cases fail on macOS assumptions, not on the commands under test — so the filed item is still an accurate description of the gate's Linux behavior, and no *new* platform assumption appeared.

**Files:** 18 root commands · 7 Python / 5 Ruby retained modules · 21 tool test files · Open: [`TODOs.md`](TODOs.md)

---

### Bumper Bowling — architecture lint

Nothing shipped. Covers **Where production sources only** (`BumperBowling.swift:15-23`); CI hard-gates it through `./test --architecture-only` (`.github/workflows/ci.yml:72-73`), and CircleCI passes `--skip-architecture` so it does not run twice.

**Verified OK:** still ten `where.*` rules, each in `.bumper/RULES.md`, with eleven mutation-test functions; `component_boundary` and `forbidden_import` mutation-tested. The two graph assertions without mutation tests are unchanged and filed.

**Files:** 4 rule/test sources · RULES.md ✓ · Open: [`TODOs.md`](TODOs.md)

---

### WhereCore

Two files touched (#301): `DataIssue.swift` gained the `DataIssueCategory` raw values the demo latch persists, and `DemoDataBuilder` gained a `Configuration` whose synthetic clock advances only the demo world.

**Verified OK:** the new configuration surface models issue selection as a `Set` of a typed enum rather than parallel flags; the raw values feed only the DEBUG developer latch, not any backup or CloudKit path; `DemoDataBuilderTests` covers the full 16-combination category matrix at two clock positions. A convenience `init(now:calendar:)` forwarding to `.standard` was weighed against the no-parameter-defaults rule and accepted — it is an explicit overload on demo fixture code, not a silent default on a store API.

**Standing:** the three fan-out and lifecycle items (summary reconcile, `setPrimaryRegions`, hard-deleting untrack) have now survived every pass since July 26, re-confirmed against current source with no drift — WhereCore's citations, down to `SwiftDataStore.swift:1844-1875`, verified exactly.

**Files:** 128 source / 83 test · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereUI

The whole window landed here: +5 sources (the demo launch trio, the two sticker views), +1 test file, +2 snapshot suites, +12 references, across #301/#302/#305.

**Verified OK:** no `Calendar.current` in any new code (the count holds at 4 production + 8 DEBUG-fixture sites, with the five `calendar.timeZone = .current` sites still correctly excluded); no raw SF Symbol strings; all new catalog keys are manual entries; `RegionsSettingsView`'s two catches log typed events and keep the draft open (an improvement over the flow it replaced, which dismissed on error); the new launch controller follows the Inspector DI pattern and is consumed exactly once before the onboarding gate, pinned by `WhereLaunchTests.requestedDemoActivatesBeforeOnboardingAndOpensNoRealStore`.

**Narrowed:** the Settings image-coverage item (five screens → four, PR #305) and the namesake-test item (`scrolledForYear` no longer exists; `LocationNamer` remains).

**Filed:** the demo sheet's fixed-frame `Form` snapshot, the orphaned estimate formatter, the stale `OnboardingGate` comment.

**Accepted:** `WhereSession` held at exactly 636 lines for a fourth consecutive window — stable, but not being worked down.

**Files:** 281 source / 103 test / 46 image-snapshot · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

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

Nothing shipped for a second consecutive window (PR #301's `WhereFlyoverWorld` change is a WhereUI integration file, not this module). Counts re-confirmed: 14 test files, 5 references, one image case.

**Files:** 54 source / 14 test / 1 image source, 5 references · README ✓ · AGENTS ✓ · Open: [`Shared/Flyover/TODOs.md`](Shared/Flyover/TODOs.md)

---

### Inspector

Nothing shipped; all four items open, citations hold exactly. The `withKnownIssue` quarantine on the dark SwiftData capture is still one of exactly **two** in the repo (the other guards WhereUI's Elsewhere inflection bug, whose test moved to `WhereFormatTests.swift:98` this window).

**Files:** 23 source / 14 test / 1 image source, 4 references · README ✓ · AGENTS ✓ · Open: [`Shared/Inspector/TODOs.md`](Shared/Inspector/TODOs.md)

---

### SnapshotKit & SnapshotKitTesting

PR #303 replaced the async-capture regression's wall-clock-delayed placeholder with settle-pass accounting — the test now proves the final settle loop ran by counting passes through the non-emitting `SnapshotCaptureTiming` payload instead of racing a 100 ms task against the pixel loop. That is the module's own documented philosophy ("pixel stability cannot become a readiness signal") applied to its own test, and it closes nothing in the backlog because nothing had filed it.

**Verified OK:** the framework halves stay split; the reporting channels still separate `report(...)`/`emit()` from `line(...)`; the content-built-once contradiction (item 9 above) is byte-for-byte unchanged in the code, the doc comment, and the `AGENTS.md` bullet.

**Corrected here:** the settle-floor split is **39** addressable configurations, not the 37 two prior passes published — both missed the Ranking Animation Lab's 2 (present since PR #289) — and the dated reference counts in `AGENTS.md` were refreshed to 484 as of this audit.

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

Nothing shipped for a **fourth** consecutive window (`git diff 13b136d5..HEAD -- Ledger/` is empty); all three P2s unchanged, with two citations refreshed (`LedgerServices.swift:303-308`, scheme at `Project.swift:712-717`).

**Files:** LedgerCore 16/14 · Ledger 8/0 · README ✓ · AGENTS ✓ (leaf modules; the **group** folder is missing both — filed) · Open: [`Ledger/TODOs.md`](Ledger/TODOs.md)

---

### RegionKit & RegionViewer

Nothing shipped; citations hold, including the honestly-stated GeoJSON coverage gap.

**Files:** RegionKit 15/10 · RegionViewer 1/0 · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereIntents, WhereWidgets, WhereShareExtension, Where app

The Where app took #301's runtime-selection change: `AppDelegate` now consults `WhereDeveloperLaunchController` (which wraps the Inspector controller) instead of the Inspector controller directly, and Spotlight indexing is skipped in demo mode.

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

- **Mostly static, partly executed.** The cloud agent runs Linux with no Swift toolchain, so no `tuist test`, no simulator, no `./test --architecture-only`, and no `./xcstrings --lint`. What *was* executed for this report: `./swiftformat --lint`, `./shellcheck`, `./attribution --check`, the retained Python tool tests, the retained Ruby tool tests, and `./snapshot-shards check`. Everything else here is read from source.
- **The retained-tool failures observed (1 of 64 Python, 12+1 of 75 Ruby) match the filed root P1 exactly** — macOS assumptions, not broken commands. If those counts ever change, check for a new platform assumption or a real regression before reporting either.
- **The "the Gregorian rule finds nothing" conclusion rests on CI being green**, not on running the lint here. The mechanism (the rule's filter plus its one-sided mutation test) is read from source and is sufficient on its own; the green gate is corroboration.
- **No snapshot pixels were inspected.** Reference counts come from file enumeration and Git LFS pointers. Whether PR #302's re-recorded `locations.Loaded_iPad.png` still bakes the inflection markup is highly likely (the broken hop is untouched) but unverifiable here; a macOS `./test --review` would settle it.
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
| WhereUI | `Where/WhereUI/` | 281 | 103 | 46 | ✓ | ✓ |
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

**Totals:** 700 source · 369 test · 49 image-snapshot Swift files across shipped targets (plus 4 Bumper rule/test sources and 2 unwired prototype sources). **484** LFS-backed reference images (473 WhereUI, 5 Flyover, 4 Inspector, 2 PeriscopeTools) across **49** snapshot suites (48 suite files plus the cross-boundary flag probe). **25** test bundles: 21 unit (20 in `Stuff-iOS-Tests` — the scheme's `testAction` list — plus `LedgerCoreTests` in `Ledger-macOS-Tests`) and 4 image (`StuffSnapshotTests`) — every one is a member of a CI scheme. The August 30 edition published 26/22/21 for these; that was already wrong at its date (PR #300 had removed `StuffCoreTests`), so the bundle change belongs to the *previous* window, not this one.

**Group-folder docs:** every one of the 27 module folders above carries its `README.md` + `AGENTS.md` pair. At the *group* level, `Shared/Broadway/` and `Shared/Periscope/` carry the required pair; `Where/` has `AGENTS.md` but **no `README.md`**, and `Ledger/` has **neither** — both filed in the root [`TODOs.md`](TODOs.md).

---

## Changes since August 30, 2026 audit

| Area | August 30 state (as published / as corrected) | September 6 state |
|------|-----------------------------------------------|-------------------|
| File count | published 694 / 368; **really 695 / 368** (WhereUI 276/102, not 274/101) | **700 / 369** — +5 WhereUI sources (#301, #302), +1 test file |
| Backlog movement | 2 closed, 1 filed | **0 closed, 2 narrowed, 3 filed** — #305 shrank the Settings-coverage item to four screens; the `scrolledForYear` half of a test item is obsolete; the demo-sheet frame, orphaned formatter, and stale gate comment are new P2s |
| Test bundles | published "26, unchanged"; **really 25** (StuffCoreTests went with #300) | **25**, genuinely unchanged this window |
| Image suites | 4 bundles, 472 references, 47 suites | **4 bundles, 484 references, 49 suites** — `DeveloperDemoLaunchSheetSnapshotTests` (#301) and `RegionsSettingsViewSnapshotTests` (#305), both on the intake shard, verified by running `./snapshot-shards check` (13/15/18/3) |
| Settle-floor split | published "37 addressable, re-derived and unchanged"; **really 39** (Ranking Animation Lab missed twice) | **39**, item now records why the lab is in scope |
| DEBUG boot modes | Inspector only | **Inspector + one-shot demo** (#301) — `WhereDeveloperLaunchController` wraps `InspectorModeController`, mutually exclusive, consumed before the onboarding gate |
| Where launch trunk | `resolve-scope` first | **`ActivateLaunchDemoStep` first** (#301) — the onboarding gate is second; its doc comment still says "head" (filed) |
| Locations card estimates | Text line under the count | **Visa-sticker endorsement** (#302); 12 references re-recorded; the old formatter is now orphaned (filed) |
| Settings regions flow | Full onboarding picker reused | **Overview + per-region editor** (#305), with snapshot coverage on arrival |
| Backlog files | 12 `TODOs.md` | **12**, unchanged |
