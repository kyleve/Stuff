# Swift Module Audit Report

Read-only review of all **21 SPM library targets**, **7 Tuist app/extension targets**, **26 test bundles**, and the repo-owned **Bumper Bowling** architecture rules (677 source / 361 test / 46 image-snapshot Swift files across shipped targets, plus 2 unwired prototype sources). No production code was changed.

**Date:** August 16, 2026  
**Method:** Read-only verification of every open finding in all 13 `TODOs.md` files against current source, module-by-module, with each citation re-derived; file-count refresh; new-surface review of the 39 commits since the last audit; and a pass over the tree against the repo's own written rules (per-module docs, CI scheme membership, the WhereUI double-linking rule, backlog format). Every verdict this report publishes was spot-checked against source after the module passes; three candidate findings were rejected that way.  
**Prior audit:** August 9, 2026 (623 source / 337 test), merged as PR #217. **This is a genuine one-week diff** — unlike the last two passes, the previous audit reached `main`, so its numbers are the real baseline rather than a re-derivation.

> **This report carries no actionable items.** Every finding it describes is filed
> in a `TODOs.md`; the root [`TODOs.md`](TODOs.md) owns the item format and says
> which file covers which area. Read this one for *shape and drift* — what each
> module verified clean, the themes running across the backlog, and how the tree
> moved since the last pass — and take the work itself from the `TODOs.md` files.
> It is true as of the header date above, **not** as of `HEAD`.

---

## Executive summary

**Not one open backlog item closed this week.** That is the finding that should change how you read the rest of this report. Five separate verification passes re-checked every open item in all 13 files against current source and returned zero closures — two items are further along than they were (the `WhereSession` split, the snapshot matrix), and everything else is exactly where it was. Last week's pass closed five items in WhereUI alone. This week the work went entirely into new surface: 39 commits, 782 files touched, 623 → 677 sources.

What the pass found, in order of how much it should change your reading of the backlog:

- **CI is now two systems, and the repo's own documentation said otherwise.** PR #237 moved the iOS unit and snapshot jobs to CircleCI while GitHub Actions kept lint, architecture, and the macOS Ledger scheme. The root `AGENTS.md` still told every agent that CI *is* `.github/workflows/ci.yml`. Corrected here; the residue is filed.
- **A load-bearing warning did not survive that migration.** The old GitHub Actions snapshot job carried a paragraph explaining why the suite must never be parallelized. It did not travel to CircleCI, nothing in either CI file says it now, and `SnapshotKitTesting/AGENTS.md` still pointed at it — so the guard's stated proof led nowhere. The reasoning itself survives in that module's rejected-experiments section; restoring the CI-side warning is filed.
- **One new module: `WhereCrashReporting`** (3 sources / 2 tests), the ninth under `Where/`. Sentry was trialled in PR #224 and removed in #255; Bitdrift ships behind the new user-facing privacy and diagnostics controls. It arrived with its `README.md`, its `AGENTS.md`, a test bundle in the CI scheme, and correct attribution — `./attribution --check` passes.
- **Three published claims were corrected rather than re-verified.** The snapshot-matrix item said `LocationsView` had no empty-state case; it has had one, alongside six others. Two prior audits recorded that "nothing in Periscope shipped at all"; this week it did (PR #265's remote-export model, PR #242's typed symbols) even though none of its 19 items closed. And the settle-floor split named 22 configurations where there are now 37.
- **PR #172 rewrote nearly every doc in the repo into Simplified Technical English.** Spot-checking four `AGENTS.md` files found the rewrite meaning-preserving almost everywhere — but it broke one `README.md` sentence into a rule that reads wrong, and it promoted a *known-false* SnapshotKit claim from a buried clause into its own standalone bullet.
- **The new defects are copies of old ones.** PR #244's `WidgetPresentationStore.readTheme()` reproduces, line for line, the silent read collapse already filed against `WidgetSnapshotStore.read()`. That is filed as one item covering both, not two.

---

## Top findings

Pointers only — each one's evidence and suggested fix live in the linked file.

| # | Module | Issue | Filed in |
|---|--------|-------|----------|
| 1 | Bumper Bowling | `where.gregorian_calendar` matches only an explicit `Calendar` base, so it reports none of the 12 implicit `.current` sites — and its own mutation test only feeds it the explicit form, which is why it has now survived four audits | [`TODOs.md`](TODOs.md) P0 |
| 2 | WhereCore | `DailySummaryReconciler.reconcile()` is absent from the post-day-change fan-out — the daily notification body stays stale until a foreground re-`configure` | [`Where/TODOs.md`](Where/TODOs.md) P0 |
| 3 | PeriscopeCore | Records emitted before the store attaches reach neither the store nor the journal — the durable log has a hole at every launch | [`Shared/Periscope/TODOs.md`](Shared/Periscope/TODOs.md) P0 |
| 4 | WhereUI | `CalendarDay.displayDate` resolves through `Calendar.current`; four production sites remain, and every day label flows through them | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 5 | CI / docs | The snapshot suite's "never parallelize this" warning was lost when the job moved to CircleCI, and the `AGENTS.md` guard still cited it | [`TODOs.md`](TODOs.md) P1 |
| 6 | WhereUI | Notification authorization is requested unprompted during launch, and all three preferences default to `true` on a fresh install | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 7 | WhereCore | Untracking a region hard-deletes the row, so re-aggregating a past year re-attributes its GPS days to `.other`; both shipped pickers reach it | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 8 | SnapshotKit | A case's content is built once and re-hosted for every configuration, while both the type's doc comment *and now its `AGENTS.md`* tell authors each access is independent | [`Shared/SnapshotKit/TODOs.md`](Shared/SnapshotKit/TODOs.md) P1 |
| 9 | Bumper Bowling | `duplicate_ownership` and `declared_dependency_cycle` have no mutation test, so neither has been shown to fail on a violating tree | [`TODOs.md`](TODOs.md) P1 |
| 10 | Inspector | Three of four fetch helpers swallow errors into `0` / `[]` / `[:]` while the fourth throws and its doc comment states the principle they break | [`Shared/Inspector/TODOs.md`](Shared/Inspector/TODOs.md) P2 |

---

## Cross-cutting themes

The synthesis across items that no single item shows.

### The backlog stopped being a queue this week

Zero closures against five new findings is not a normal week, and it is worth naming rather than averaging away. Every module pass came back with the same shape: the item is still true, the line numbers moved, nothing was attempted. The two exceptions are partial and passive — `WhereSession` is *still* 636 lines (it neither grew nor shrank through a week that rewrote much of what surrounds it), and the snapshot matrix closed one half by accident, because PR #187's forecasting work happened to arrive with the `LocationsView` cases the item had asked for. Meanwhile the tree grew 9% in a week. The backlog is currently a standing ledger of known debt rather than a work queue, and the ratio between its age and the repo's velocity is widening.

### A migration carries the code but not the warnings around it

PR #237 moved two CI jobs from GitHub Actions to CircleCI. The commands moved correctly. What did not move was the paragraph above the snapshot job explaining that `-parallel-testing-enabled` distributes XCTest *classes*, that Swift Testing presents none, and that its own in-process parallelism therefore interleaves captures inside a single `StuffTestHost` and corrupts them. That warning existed precisely for the person who would one day look at a slow serial snapshot job and try to speed it up — and it is now absent from the file that person will open. The same migration left `SnapshotKitTesting/AGENTS.md` pointing at the vanished comment and the root `AGENTS.md` describing a single-system CI. Three separate documents degraded from one move, and no lint could see any of it. The rule this suggests: when a job moves, the comments explaining *why it is shaped that way* are part of the payload.

### Rewriting prose at scale is a distinct risk to correctness

PR #172 restated nearly every doc in the repo in Simplified Technical English. Judged on meaning rather than style, it is overwhelmingly faithful — this pass compared four `AGENTS.md` files against their pre-rewrite text and found the invariants intact, several genuinely clarified, and two correctly *deleted* because the code they described was gone. But two failure modes showed up that only a semantic reading catches. In `PeriscopeCore/README.md` a semicolon became a full stop mid-clause, leaving "silence spans with level floors" standing as its own lowercase rule. And in `SnapshotKit/AGENTS.md` the sentence "each content access creates the independent value rendered by that configuration" — which the backlog has flagged as **false** since 2026-08-09, because the runner reads `content` once per case — was promoted from a subordinate clause into a standalone bullet. The rewrite made a known-wrong claim more prominent and more quotable, in the file agents are most likely to preserve against the code. Neither `./swiftformat --lint` nor any other gate can see this class of regression.

### New defects are copies, not inventions

Across ~54 net new sources this week, the pass found few genuinely new mistakes — and the clearest one is a duplicate. `WidgetPresentationStore.readTheme()`, added by PR #244's multi-theme work, collapses "file never written" and "file unreadable" into the same silent default and warns only on a decode failure. That is the exact shape already filed against `WidgetSnapshotStore.read()`, twenty lines of a sibling file away. The same pattern showed up last week (the evidence panels repeating an accessibility gap). An open item describing a defect does not stop the next author from copying the working code beside it, which argues for closing quick-win items in the module a team is actively working in, rather than by priority order across the repo.

### Standing debt is invisible to a diff-shaped review

Three Settings screens — Alerts, Visible Year, and Removed Device — have a `#Preview` and no `SnapshotProviding` conformance, against the module convention that an image bundle owns "does this screen render". Two have been uncovered since PR #111, and this is the **fourth** audit to pass over them. What makes the case sharper this week is the contrast: every screen added in the window, including `PrivacyDiagnosticsSettingsView` and `DeveloperCrashTestingView`, declared the conformance on arrival. The convention is healthy; the exceptions predate the reviews that keep missing them, because a review that diffs the week can only see what moved.

### Counted claims keep going stale, and one of them was this report's

The reference-image count appeared in `SnapshotKitTesting/AGENTS.md` twice — as 381 in one bullet and 361 in another, twenty-three lines apart. Re-deriving from the tree settled which was right, and the answer is uncomfortable: **381 was correct at last week's commit, and 361 was the figure the August 9 edition of this report published.** So the audit propagated an undercount into a module's docs, where it then contradicted the accurate number sitting a few lines above it. Both are now stale anyway (466 on disk), and both are corrected. Elsewhere the dev-script count read 15 against 16 on disk, `./test`'s line count 869 against 941, and the WhereCore namesake debt 57 of 114 against 60 of 127. The pattern is stable enough across five audits to be a rule rather than an observation: a number written into prose has a half-life of about a week here, so it is worth writing only where it is load-bearing, worth re-deriving rather than carrying forward, and worth dating with a tripwire where it can't be re-measured.

---

## Per-module notes

What each module was checked for and found clean, plus the trade-offs this pass accepted as deliberate. Open work is in the linked `TODOs.md`.

### Bumper Bowling — architecture lint

Covers **Where production sources only** (`BumperBowling.swift:15-23`). CI still hard-gates it with every rule at `severity: .error`, but the invocation changed this week: PR #271 replaced three `swift run bumper` steps with `./test --architecture-only` (`.github/workflows/ci.yml:62-63`, reaching `config`/`test`/`lint` through `test:186-202`), and the CircleCI iOS jobs pass `--skip-architecture` so it does not run twice.

**Verified OK:** all ten `where.*` rules appear in `.bumper/RULES.md` and each has a mutation test; `component_boundary` and `forbidden_import` are mutation-tested.

**Not covered, by design:** everything under `Shared/`, all of `Ledger/`, test bundles, and `Where/Specifications/`. `WhereCrashReporting` is inside `Where/` but its own dependency edge to Bitdrift is not something the current rules assert on. Worth knowing when reading a green lint as a whole-repo signal.

**Files:** 4 rule/test sources · RULES.md ✓ · Open: [`TODOs.md`](TODOs.md)

---

### WhereCore

**Verified OK:** the window's new persistence surfaces hold the module's own line — `DiagnosticReportingConfiguration`'s hand-written `Codable` documents its wire-shape reason on the conformance, as the repo requires of any non-synthesized one, and `PlannedStayCoordinator` throws rather than degrading; the generation-scoped fetches from PR #209 are unchanged and still cover all seven scoped entity types; the retired AI recent-activity feature (PR #230) was removed cleanly, taking its rule out of `Where/AGENTS.md` with it rather than leaving a stale invariant behind.

**Standing:** three fan-out and lifecycle items have now survived every pass since July 26 — the summary reconcile, `setPrimaryRegions`, and the hard-deleting untrack. All three were re-confirmed against current source rather than assumed.

**Files:** 127 source / 82 test · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereUI

The busiest module in the repo by a wide margin: +16 sources this week across multi-theme, forecasting, privacy, and crash-testing work.

**Verified OK:** `Calendar.current` is still confined to four helper defaults and eight DEBUG fixtures, with the five `calendar.timeZone = .current` sites correctly *not* counted (they set a time zone on an explicit Gregorian calendar — a distinction three passes have had to re-establish, now recorded in the item so a fourth doesn't); no raw SF Symbol strings in production after PR #242; every screen added this window ships a `SnapshotProviding` conformance; the new unlabeled `.accessibilityElement(children: .combine)` sites are correct rather than defects, because their decorative symbols are `.accessibilityHidden(true)` and their combined children read as a sentence.

**Files:** 258 source / 96 test / 43 image-snapshot · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereCrashReporting — first audit

New this window. Wraps Bitdrift's `Capture` behind a `WhereReportingController` protocol, with a `CrashReportingProcess` gate that stands down under XCTest.

**Verified OK:** ships the required `README.md` + `AGENTS.md` pair; has its own test bundle wired into `Stuff-iOS-Tests`; `capture-ios` is credited as a shipped library in `Where/Where/Resources/attribution.json` and `./attribution --check` reports the report up to date; Sentry is fully gone after PR #255 — a repo-wide grep finds no trace, so the trial left no disabled code behind.

**Files:** 3 source / 2 test · README ✓ · AGENTS ✓ · Open: nothing filed

---

### PeriscopeCore, PeriscopeUI, PeriscopeTools

**Correction to the last two audits:** both recorded that nothing in Periscope shipped. This week it did — PR #265 added the `RemoteLogField` remote-export model to Core, and PR #242 moved the tool views to typed symbols. None of the 19 open items closed, which is the accurate version of the same observation.

**Verified OK:** the Broadway dependency still stops at PeriscopeTools; no test touches `Periscope.shared`; the hosting-smoke debt **held at 20 tests across 10 files** rather than growing for a third consecutive audit; the span-record P0's 2026-08-09 correction (that `spanID`/`spanExit` are computed downcasts, not stored fields) still describes the code accurately.

**Files:** PeriscopeCore 38/33 · PeriscopeUI 1/2 · PeriscopeTools 27/27 (+1 image source, 2 references) · README ✓ · AGENTS ✓ · Open: [`Shared/Periscope/TODOs.md`](Shared/Periscope/TODOs.md)

---

### Flyover

Two feature PRs this week — horizontal canvas groups (#257) and viewport-centered zoom (#268) — both landing with unit coverage of the new plans and, for #257, one new reference and a two-axis full-content capture.

**Verified OK:** no production `try?` or empty catch; the `AGENTS.md` rewrite genuinely tracked the code, gaining the "fitted to its first group's width" and depth-band-cap invariants that #257 introduced rather than describing the old layout.

**Accepted, with a note:** the module keeps proving its geometry while its surfaces stay unpinned. Test files went 10 → 12 (excluding its two shared fixtures) and references 4 → 5, all on the computational side; the focused inspector and the menus still have no image coverage.

**Files:** 54 source / 14 test / 1 image source, 5 references · README ✓ · AGENTS ✓ · Open: [`Shared/Flyover/TODOs.md`](Shared/Flyover/TODOs.md)

---

### Inspector

**Verified OK:** the `withKnownIssue` quarantine on the dark SwiftData capture is still one of exactly **two** in the whole repo (the other guards WhereUI's Elsewhere inflection bug) — re-counted rather than assumed.

**New this pass:** `inspectorCount`, `inspectorFetch`, and `inspectorModels` degrade to `0` / `[]` / `[:]` through `try?` with no log, while the sibling `inspectorModel` throws and its doc comment states the exact principle the other three break. Filed.

**Files:** 23 source / 14 test / 1 image source, 4 references · README ✓ · AGENTS ✓ · Open: [`Shared/Inspector/TODOs.md`](Shared/Inspector/TODOs.md)

---

### SnapshotKit & SnapshotKitTesting

Heavy churn this window — the SwiftUI accessibility renderer (#227), AccessibilitySnapshot 0.12 (#249), async settle stabilization for slow CI (#232), and the reference-content guard (#250).

**Verified OK:** the framework halves stay split as documented; each image bundle lists only `SnapshotKitTesting` in `extraPackageProducts`; the reporting channels still separate `report(...)`/`emit()` from `line(...)`, so no test can fabricate a row into `--review` or `--timings`.

**Corrected here:** the reference count (466 — the docs carried 381 and 361 in two contradictory bullets, of which 381 was the historically accurate one) and the addressable settle-floor split (37 configurations, not 22 — `AboutSettingsView` contributes 10 that postdate the split, and `RootView` contributes 4 once counted by configuration).

**Files:** SnapshotKit 8/3 · SnapshotKitTesting 16/15 · README ✓ · AGENTS ✓ · Open: [`Shared/SnapshotKit/TODOs.md`](Shared/SnapshotKit/TODOs.md), [`Shared/SnapshotKitTesting/TODOs.md`](Shared/SnapshotKitTesting/TODOs.md)

---

### LifecycleKit & LifecycleKitUI

PRs #229 and #264 reworked the first-foreground reveal.

**Verified OK:** the reveal semantics changed and the docs changed with them — `LifecycleKitUI/AGENTS.md` now says the splash minimum covers the first *visible* ready reveal including an already-`.ready` mount, the old guard test asserting the opposite is gone, and four new guards pin the new behavior. A behavior change, its docs, and its tests landing together is the case this repo's doc rules exist to produce.

**Files:** LifecycleKit 8/10 · LifecycleKitUI 6/4 · README ✓ · AGENTS ✓ · Open: [`Shared/LifecycleKit/TODOs.md`](Shared/LifecycleKit/TODOs.md) (LifecycleKitUI's items live in LifecycleKit's file by design)

---

### Broadway (BroadwayCore, BroadwayUI, BroadwayCatalog)

Nothing shipped. All eight items still open, citations refreshed.

**Verified OK:** the `AGENTS.md` rewrite correctly added SFSafeSymbols to BroadwayCatalog's declared dependencies, matching `Project.swift`.

**Files:** BroadwayCore 17/10 · BroadwayUI 6/4 · BroadwayCatalog 2/1 · README ✓ · AGENTS ✓ · Open: [`Shared/Broadway/TODOs.md`](Shared/Broadway/TODOs.md)

---

### Ledger, LedgerCore

Nothing shipped; all three P2s unchanged, one scheme citation corrected.

**Verified OK:** still 13 test files over 16 sources, still the three named files without a namesake test, and `Ledger-macOS-Tests` still builds the app while running only `LedgerCoreTests`. The module remains outside Bumper's scope and outside `./test`'s reach — the second of which is filed as a root P2.

**Files:** LedgerCore 16/14 · Ledger 8/0 · README ✓ · AGENTS ✓ (leaf modules; the **group** folder is missing both — filed) · Open: [`Ledger/TODOs.md`](Ledger/TODOs.md)

---

### RegionKit & RegionViewer

**Verified OK, and two doc claims closed:** PR #172's rewrite fixed both halves of a long-standing item. `RegionViewer/README.md` now describes the bundled per-region GeoJSON instead of the tooling-only monolith, and `RegionKit/README.md` now states plainly that GeoJSON decoding is **not** covered — replacing a claim that had told agents the missing tests already existed. That is the single most valuable correction in the rewrite, because a doc overclaiming coverage is an argument against writing the tests.

**Files:** RegionKit 15/10 · RegionViewer 1/0 · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereIntents, WhereWidgets, WhereShareExtension, Where app

**Verified OK:** the `IntentServices` handoff still has no self-creating fallback; the Bitdrift start path is gated behind user configuration and stands down under XCTest.

**Accepted:** all four parts of the `convention(WhereIntents)` polish item are still open, verified individually rather than as a group.

**Files:** WhereIntents 15/9 · WhereWidgets 7/0 · WhereShareExtension 5/0 · Where 8/4 · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### CreditKit, JournalKit, StuffCore, TestHostSupport, StuffTestHost

**CreditKit:** `./attribution --check` passes at 11 credits, now including `capture-ios` as a shipped library and `simple-english` among the pinned external skills. **Files:** 2/3 · Open: [`Shared/CreditKit/TODOs.md`](Shared/CreditKit/TODOs.md)

**JournalKit:** nothing shipped; docs-only changes. Both test items still open. **Files:** 2/3 · Open: [`Shared/JournalKit/TODOs.md`](Shared/JournalKit/TODOs.md)

**StuffCore:** intentional scaffold. **Files:** 1/1 · Open: [`Shared/StuffCore/TODOs.md`](Shared/StuffCore/TODOs.md)

**TestHostSupport:** dependency-free UIKit helpers, no bundle by design. **Files:** 1/0 · nothing open

**StuffTestHost:** unchanged. **Files:** 2/0 · nothing open

---

## Limitations

- **Static analysis only.** The cloud agent runs Linux, which has **no Swift toolchain at all** — so no `tuist test`, no simulator, and also no `./test --architecture-only` and no `./xcstrings --lint`, both of which are CI gates. `./swiftformat --lint` and `./attribution --check` were run and pass. Nothing in this report was executed.
- **The "the Gregorian rule finds nothing" conclusion rests on CI being green**, not on running the lint here. The mechanism (the rule's filter plus its one-sided mutation test) is read from source and is sufficient on its own; the green gate is corroboration.
- **No snapshot pixels were inspected.** Reference counts and sizes come from Git LFS pointers, never from decoded images. Whether a re-recorded ax5 reference still shows a layout defect is unanswerable here; a macOS `./test --review` would settle it.
- **Runtime-dependent items are unconfirmed by design**: the launch-time notification prompt, Flyover's log routing, multi-process journal coordination, the CloudKit import-readiness race, Spotlight indexing, whether Bitdrift receives anything on a device, and Ledger's live API and Keychain paths. Each says so in its own entry.
- **The doc-rewrite review was a spot-check, not exhaustive.** PR #172 touched hundreds of files; four `AGENTS.md` files plus the affected module docs were diffed for meaning. Other files may carry the same two failure modes.
- **No item counts by severity.** They could not be reconciled against the backlog in earlier revisions and remain deliberately omitted rather than estimated.
- `Shared/Periscope/Prototypes/JournalBenchmark` (2 sources) is wired into no target and is excluded from every count here.

---

## Modules reviewed

### SPM library targets

| Module | Path | Source | Test | Image | README | AGENTS |
|--------|------|-------:|-----:|------:|:------:|:------:|
| StuffCore | `Shared/StuffCore/` | 1 | 1 | — | ✓ | ✓ |
| CreditKit | `Shared/CreditKit/` | 2 | 3 | — | ✓ | ✓ |
| JournalKit | `Shared/JournalKit/` | 2 | 3 | — | ✓ | ✓ |
| LifecycleKit | `Shared/LifecycleKit/` | 8 | 10 | — | ✓ | ✓ |
| LifecycleKitUI | `Shared/LifecycleKitUI/` | 6 | 4 | — | ✓ | ✓ |
| SnapshotKit | `Shared/SnapshotKit/` | 8 | 3 | — | ✓ | ✓ |
| SnapshotKitTesting | `Shared/SnapshotKitTesting/` | 16 | 15 | — | ✓ | ✓ |
| Inspector | `Shared/Inspector/` | 23 | 14 | 1 | ✓ | ✓ |
| Flyover | `Shared/Flyover/` | 54 | 14 | 1 | ✓ | ✓ |
| TestHostSupport | `Shared/TestHostSupport/` | 1 | 0 | — | ✓ | ✓ |
| BroadwayCore | `Shared/Broadway/BroadwayCore/` | 17 | 10 | — | ✓ | ✓ |
| BroadwayUI | `Shared/Broadway/BroadwayUI/` | 6 | 4 | — | ✓ | ✓ |
| PeriscopeCore | `Shared/Periscope/PeriscopeCore/` | 38 | 33 | — | ✓ | ✓ |
| PeriscopeUI | `Shared/Periscope/PeriscopeUI/` | 1 | 2 | — | ✓ | ✓ |
| PeriscopeTools | `Shared/Periscope/PeriscopeTools/` | 27 | 27 | 1 | ✓ | ✓ |
| RegionKit | `Where/RegionKit/` | 15 | 10 | — | ✓ | ✓ |
| WhereCore | `Where/WhereCore/` | 127 | 82 | — | ✓ | ✓ |
| WhereUI | `Where/WhereUI/` | 258 | 96 | 43 | ✓ | ✓ |
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

**Totals:** 677 source · 361 test · 46 image-snapshot Swift files across shipped targets (plus 4 Bumper rule/test sources and 2 unwired prototype sources). **466** LFS-backed reference images (455 WhereUI, 5 Flyover, 4 Inspector, 2 PeriscopeTools). **26** test bundles: 22 unit (21 in `Stuff-iOS-Tests`, plus `LedgerCoreTests` in `Ledger-macOS-Tests`) and 4 image (`StuffSnapshotTests`) — every one is a member of a CI scheme.

**Group-folder docs:** every one of the 28 module folders above carries its `README.md` + `AGENTS.md` pair, including the new `WhereCrashReporting`. At the *group* level, `Shared/Broadway/` and `Shared/Periscope/` carry the required pair; `Where/` has `AGENTS.md` but **no `README.md`**, and `Ledger/` has **neither** — both filed in the root [`TODOs.md`](TODOs.md).

---

## Changes since August 9, 2026 audit

| Area | August 9 state | August 16 state |
|------|----------------|-----------------|
| Target count | 20 SPM + 7 Tuist | **21 SPM + 7 Tuist** — `WhereCrashReporting` (#224/#255/#265), the ninth module under `Where/` |
| File count | 623 source / 337 test | **677 / 361** (WhereUI 224 → 258, WhereCore 118 → 127, Flyover 50 → 54) |
| CI topology | One system, five jobs on GitHub Actions | **Two systems.** GitHub Actions keeps `format`, `architecture`, `test-macos`; CircleCI runs `test-ios` and `snapshot` on `m4pro.medium` (#237, #240, #245). Snapshot sharding (#223) landed and was reunified within the same window |
| Architecture lint | Three `swift run bumper` steps in CI | **`./test --architecture-only`** (#271); CircleCI passes `--skip-architecture` so it runs once |
| Crash reporting | None | **Bitdrift only.** Sentry trialled (#224) and removed (#255); user-facing privacy and diagnostics controls (#265/#266) and a DEBUG crash-testing tool (#262) |
| Test bundles | 25 | **26** — `WhereCrashReportingTests`, in `Stuff-iOS-Tests` |
| Image suites | 4 bundles, **381** references (this report published 361 — an undercount, corrected here) | **4 bundles, 466 references** — WhereUI 371 → 455, Flyover 4 → 5 |
| Deleted surface | — | The **AI recent-activity summaries** were retired (#230), removing ~40 files across WhereCore, WhereUI, and the intents |
| Formal specs | 9 TLA+ specifications | **10**, and all migrated to **PlusCal** as the editable model source (#263); `FirstForegroundReveal` is new (#264) |
| Docs | — | **PR #172 rewrote nearly every doc** into Simplified Technical English; `simple-english` joins the pinned external skills |
| Dev scripts | 13 in this report, 15 in the backlog — both stale | **16** — `loc` (#208) is new this window, and the count is re-derived rather than carried |
| Backlog | 13 `TODOs.md` | **13** — no new area needed one |
