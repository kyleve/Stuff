# Swift Module Audit Report

Read-only review of all **20 SPM library targets**, **7 Tuist app/extension targets**, **25 test bundles**, and the repo-owned **Bumper Bowling** architecture rules (623 source / 337 test / 40 image-snapshot Swift files across shipped targets, plus 2 unwired prototype sources). No code was changed.

**Date:** August 9, 2026  
**Method:** Read-only verification of every open finding in all 13 `TODOs.md` files against current source, module-by-module, with each citation re-derived; file-count refresh; new-surface review of two weeks of landings; and a pass over the tree against the repo's own written rules (per-module docs, agent-file sync, CI scheme membership, the WhereUI double-linking rule, backlog format).  
**Prior audit:** July 26, 2026 (~359 source / ~198 test). **This is a two-week diff, not a one-week one:** the August 2 pass was opened as PR #171 and closed unmerged, so nothing it found reached `main` and its work is re-derived here.

> **This report carries no actionable items.** Every finding it describes is filed
> in a `TODOs.md`; the root [`TODOs.md`](TODOs.md) owns the item format and says
> which file covers which area. Read this one for *shape and drift* — what each
> module verified clean, the themes running across the backlog, and how the tree
> moved since the last pass — and take the work itself from the `TODOs.md` files.
> It is true as of the header date above, **not** as of `HEAD`.

---

## Executive summary

**The tree nearly doubled in two weeks: 359 → 623 sources, 198 → 337 tests, 14 → 20 SPM libraries.** Three areas are new since the last merged audit — **Ledger** (a native-macOS menu-bar app for Cursor spend, with its own CI job), **Flyover** (the developer screen browser), and **LifecycleKitUI** — and `SwiftDataInspector` became **Inspector**. WhereUI alone went 113 → 224 sources and WhereCore 87 → 118.

What the verification pass found, in order of how much it should change your reading of the backlog:

- **Five WhereUI items closed for real**, four of them from the broken-snapshots cluster that has sat open since PR #101. Two were fixed as filed, one was fixed by redesign, and one is *obsolete* rather than fixed — PR #200 deleted the code it described. The cluster is down from eight sub-items to three.
- **Three items turned out to describe code that doesn't work the way they claim.** The span-record-modeling P0 says `spanID`/`spanExit` are "bolted onto every `LogRecord`"; they're computed downcasts, and only `bypassesFloors` is stored. That changes what the item is asking for, so it's recorded as a dated correction inside the item rather than edited away.
- **Nothing in Periscope, Broadway, SnapshotKit, SnapshotKitTesting, CreditKit, JournalKit, LifecycleKit, or StuffCore shipped at all.** Their 24 open items are all still open. Periscope's three durability gaps remain the oldest work in the repo.
- **Two tracked debts grew while nobody was looking.** The PeriscopeTools hosting-smoke-test count went from 18 across 9 files to **20 across 10** (PR #152 added a file while the conversion was backlogged), and the WhereCore namesake-test gap went from 28 of 87 files to **59 of 118**.
- **Ledger passed its first audit** with three modest P2s and no defects of substance — notable for a brand-new network-facing app outside Bumper's scope.
- **Every measured number in the previous audit was stale**, and several in module docs were too. Those are corrected or dated with tripwires; the ones this pass cannot re-measure say so rather than being restated.

---

## Top findings

Pointers only — each one's evidence and suggested fix live in the linked file.

| # | Module | Issue | Filed in |
|---|--------|-------|----------|
| 1 | Bumper Bowling | `where.gregorian_calendar` matches only an explicit `Calendar` base, so it reports none of the 12 implicit `.current` sites — and its own mutation test only feeds it the explicit form, which is why it has survived three audits | [`TODOs.md`](TODOs.md) P0 |
| 2 | WhereCore | `DailySummaryReconciler.reconcile()` is absent from the post-day-change fan-out — the daily notification body stays stale until a foreground re-`configure` | [`Where/TODOs.md`](Where/TODOs.md) P0 |
| 3 | WhereUI | `CalendarDay.displayDate` resolves through `Calendar.current`; four production sites remain, and every day label flows through them | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 4 | PeriscopeCore | Records emitted before the store attaches reach neither the store nor the journal — the durable log has a hole at every launch | [`Shared/Periscope/TODOs.md`](Shared/Periscope/TODOs.md) P0 |
| 5 | PeriscopeCore | `survivesRelaunch` is honored by the sweep but nothing re-seeds surviving spans, so `end(for:)` warns "without a matching begin" in the new process | [`Shared/Periscope/TODOs.md`](Shared/Periscope/TODOs.md) P0 |
| 6 | WhereUI | Notification authorization is requested unprompted during launch, and all three preferences default to `true` on a fresh install | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 7 | WhereCore | Untracking a region hard-deletes the row, so re-aggregating a past year re-attributes its GPS days to `.other`; both shipped pickers reach it | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 8 | Bumper Bowling | `duplicate_ownership` and `declared_dependency_cycle` have no mutation test, so neither has been shown to fail on a violating tree | [`TODOs.md`](TODOs.md) P1 |
| 9 | SnapshotKit | A case's content is built once and re-hosted for every configuration, while the type's doc comment tells authors each access is independent | [`Shared/SnapshotKit/TODOs.md`](Shared/SnapshotKit/TODOs.md) P1 |
| 10 | PeriscopeTools | 20 tests across 10 files assert only "the hosted view reached a window", and the image bundle that should replace them still holds one file | [`Shared/Periscope/TODOs.md`](Shared/Periscope/TODOs.md) P2 |

---

## Cross-cutting themes

The synthesis across items that no single item shows.

### A lint rule and its test can fail together

The `where.gregorian_calendar` blind spot has now survived three audits, and this pass found why: the rule filters on an explicit `Calendar` base, and its mutation test only ever feeds it an explicit `Calendar.current`. The test passes for precisely the reason the rule fails, so the pair is self-consistent and green while 12 sites drift. The same shape appears in the two untested graph assertions (finding 8) — an assertion nobody has watched fail is indistinguishable from one that passes everything. This is the strongest argument in the backlog for the repo's own rule that a lint rule and its mutation test land together.

### Re-recording a reference does not fix what it pins

PR #196 re-recorded much of the WhereUI suite for intrinsic-height captures. That genuinely closed one broken-snapshot item — the blank VoiceOver calendar captures went from 66 KB of white to 3.2 MB of content — but for three others it re-recorded the defect at a new size, so the reference still faithfully pins a truncated day grid, an overflowing picker, and a misplaced badge. An image suite makes rendering visible; it does not make it correct, and a re-record in the changelog is not evidence a rendering bug closed. The remaining sub-items now carry that warning explicitly.

### The reconciliation fan-out has the same two holes it had in July

`reconcileAfterDayDataChange()` still reaches issue state and widgets only. **Daily summary** remains outside it and **`setPrimaryRegions(_:)`** still commits without calling it — unchanged across two weeks in which PR #160 rewrote much of the surrounding recording stack and PR #209 rewrote every fetch beneath it. What did change is the diagnosis: the single-sample and bulk ingest paths were closed in August, and `reset()` does reconcile summary, so the gap is now specifically the *local* write paths rather than a general absence. `Where/Specifications/PostWriteReconcile` documents the canonical ordering and deliberately excludes summary, which means the spec cannot be used as evidence the hole is closed.

### Growth outran the tests, and the docs recorded the old ratio

WhereUI went 113 → 224 sources against 36 → 90 tests; WhereCore 87 → 118 against 58 → 74. The namesake-test debt therefore grew in absolute terms (28 → 59 files in WhereCore) even though real coverage was added. Three screens have no image coverage, and two of them have had none since PR #111 — prior audits missed them because they checked what was *new*, not what was uncovered. The lesson for this report: an inventory that only diffs the week can't see standing debt.

### Documentation drifts fastest where it quotes a number

Nine measured claims in the previous audit were stale, and four more were in module docs: two reference counts in `SnapshotKitTesting/AGENTS.md`, a coverage claim in `RegionKit/README.md` that named tests which don't exist, a geometry layout in `RegionViewer/README.md` describing the pipeline's build-time input as if it were the shipped bundle, and a `tuist test` command in `LedgerCore/AGENTS.md` naming the bundle instead of the scheme. **A false claim in an `AGENTS.md` is the worst case** — the RegionKit one told the next agent that GeoJSON decoding was tested, which is an argument against writing the missing tests. All are corrected in this pass; the two that can only be re-measured on macOS are dated with tripwires instead.

### New code is landing clean; the debt is old

Across two weeks and ~264 new source files, the verification pass found few defects in new code: one honest gap in `WidgetSnapshotStore.read()`, an accessibility gap in the evidence discovery panels, three uncovered screens, and an untested Spotlight indexer. Ledger arrived with a typed error path, a single `LoadState`, no secrets in its JSON, and near-1:1 tests. Four candidate findings were investigated and rejected as false alarms — including one that looked like a shipped bug (`\.isCapturingSnapshot` set to `true` in WhereUI) until it turned out to be inside `#if DEBUG`. The backlog's weight is in items filed in July and earlier, not in what shipped this fortnight.

---

## Per-module notes

What each module was checked for and found clean, plus the trade-offs this pass accepted as deliberate. Open work is in the linked `TODOs.md`.

### Bumper Bowling — architecture lint

Covers **Where production sources only** (`BumperBowling.swift:15-23`): layer boundaries and forbidden imports, graph integrity, production store opening, checked-concurrency escape hatches, composition ownership, the Gregorian calendar, the `store.perform` boundary, `AppShortcutsProvider` ownership, the logging facade and logging-type placement, and `#Preview` coverage. CI runs `config`, `test`, and `lint --timings` as hard gates with every rule at `severity: .error`.

**Verified OK:** all ten `where.*` rules in `WhereProjectRules.swift` appear in `.bumper/RULES.md` and each has a mutation test; `component_boundary` and `forbidden_import` are mutation-tested; the stale "three intentional calendar violations" claim is gone from the catalog.

**Not covered, by design:** everything under `Shared/`, all of `Ledger/`, test bundles, and `Where/Specifications/`. Three of the four modules added since July — Flyover, Inspector, LifecycleKitUI, and both Ledger targets — therefore landed with zero architecture lint. Worth knowing when reading a green lint as a whole-repo signal.

**Files:** 4 rule/test sources · RULES.md ✓ · Open: [`TODOs.md`](TODOs.md)

---

### WhereCore

**Verified OK:** generation-scoped fetches cover all seven scoped entity types and preserve legacy `nil == .initial` rows, with rotation and mixed-generation reads tested; the crash-safe outbox journals whole snapshots and recovers a torn tail; automatic-recording consent is installation-local with no cross-device authority timeline; an unreadable backup asset now fails the import instead of committing metadata-only evidence; `DeviceRecordingController`'s import-recovery `catch` logs a typed error, revokes authorization, publishes `.unavailable`, and flags reconciliation — the sanctioned "log + honest state" path, not a swallowed error.

**Files:** 118 source / 74 test · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereUI

**Verified OK:** no `Calendar.current` outside four helper defaults and eight DEBUG fixtures (`calendar.timeZone = .current` on an explicit Gregorian calendar is the correct pattern and is not drift); the only production write of `\.isCapturingSnapshot` is inside `#if DEBUG`; the capture-flag reads that remain are the documented stand-in carve-outs; every new screen this window except three ships image coverage; the automatic-recording binding is serialized behind a monotonic intent sequence and the Devices UI renders remote status read-only.

**Files:** 224 source / 90 test / 37 image-snapshot · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### PeriscopeCore, PeriscopeUI, PeriscopeTools

**Verified OK:** the Broadway dependency genuinely stops at PeriscopeTools — no `BroadwayCore`/`BroadwayUI` import in Core or UI, and `Package.swift:94-99` lists it on Tools alone; no test touches `Periscope.shared`; span-pair integrity holds across floors, redaction, and drop pressure; the relaunch sweep leaves surviving spans open and is tested. A concurrency-focused review of the new ambient and build-attribution code found no defects and rejected four candidates.

**Accepted:** the journal append sits outside the pipeline lock deliberately — the sequence in each entry makes recovery order-safe.

**Files:** PeriscopeCore 37/33 · PeriscopeUI 1/2 · PeriscopeTools 27/27 (+1 image) · README ✓ · AGENTS ✓ · Open: [`Shared/Periscope/TODOs.md`](Shared/Periscope/TODOs.md)

---

### Ledger, LedgerCore — first audit

Native macOS, outside the Where graph and outside Bumper's scope, in its own `Ledger-macOS-Tests` CI job.

**Verified OK:** one `LoadState` enum rather than parallel loading/error/value fields; transport, HTTP, and decode failures become a typed `DashboardError` mapped to a `LoadError` and logged, with 401 distinguished as an expired session; a failed refresh keeps the last snapshot and surfaces staleness rather than blanking it; only the newest refresh may mutate state, via a request-generation guard that also protects recorded history; `state.vscdb` is opened `SQLITE_OPEN_READONLY`; no secrets in its JSON (pasted token in the Keychain, auto-token in Cursor's own store); no token value reaches a log string; `SecureField` for the token draft, cleared after save; Swift Testing throughout with 13 test files over 16 sources; docs correctly credit PeriscopeCore rather than the deleted LogKit.

**Files:** LedgerCore 16/14 · Ledger 8/0 · README ✓ · AGENTS ✓ (leaf modules; the **group** folder is missing both — filed) · Open: [`Ledger/TODOs.md`](Ledger/TODOs.md)

---

### Flyover — first audit

**Verified OK:** no production `try?` or empty catch; the `default:` uses are dictionary subscript defaults, not enum switches; `README.md`/`AGENTS.md` match the code on the lazy catalog, the Broadway root, and the canvas cap; PR #166's snapshot stabilization left no `withKnownIssue` behind — it uses a settle floor.

**Accepted:** `FlyoverScreenContent.swift:47` sets `\.isCapturingSnapshot` for overview frames, so descendants render their inert capture stand-ins. Deliberate for a screen browser whose whole job is deterministic miniatures, and the only such production write in the repo.

**Files:** 50 source / 12 test / 1 image · README ✓ · AGENTS ✓ · Open: [`Shared/Flyover/TODOs.md`](Shared/Flyover/TODOs.md)

---

### Inspector

**Verified OK:** `AGENTS.md` invariants (filesystem protection, the pagination model, `Sendable` snapshots) match the code; the browsing test monolith was split by concern in July.

**Accepted:** the dark SwiftData capture stays quarantined under `withKnownIssue(isIntermittent:)` — one of only two quarantines in the repo, both tracked.

**Files:** 23 source / 14 test / 1 image · README ✓ · AGENTS ✓ · Open: [`Shared/Inspector/TODOs.md`](Shared/Inspector/TODOs.md)

---

### SnapshotKit & SnapshotKitTesting

**Verified OK:** the framework halves stay split as documented (shippable matrix vs test-only pipeline); each image bundle lists only `SnapshotKitTesting` in `extraPackageProducts`; the reporting channels no longer fabricate rows into `--review`/`--timings`; the non-converging `fullContent` measurement now fails rather than blessing an arbitrary height.

**Files:** SnapshotKit 8/3 · SnapshotKitTesting 14/11 · README ✓ · AGENTS ✓ · Open: [`Shared/SnapshotKit/TODOs.md`](Shared/SnapshotKit/TODOs.md), [`Shared/SnapshotKitTesting/TODOs.md`](Shared/SnapshotKitTesting/TODOs.md)

---

### LifecycleKit & LifecycleKitUI

**Verified OK:** the typed `LaunchPlan` still makes a mis-ordered launch a compile error; the terminal-phase race is closed by the typed-engine rewrite (the engine holds nothing, and a superseded walk publishes nothing); `completedStepIDs` keeps a promotion re-drive from re-running finished work; the suites poll predicates rather than sleeping.

**Files:** LifecycleKit 8/10 · LifecycleKitUI 5/3 · README ✓ · AGENTS ✓ · Open: [`Shared/LifecycleKit/TODOs.md`](Shared/LifecycleKit/TODOs.md) (LifecycleKitUI's items live in LifecycleKit's file by design)

---

### Broadway (BroadwayCore, BroadwayUI, BroadwayCatalog)

**Verified OK:** stylesheet, trait, and cycle behavior are well tested; trait registration pairs with teardown.

**Accepted:** a bare `default:` mapping an unknown `UIContentSizeCategory` to `.large`; hardcoded English in the internal showcase app.

**Files:** BroadwayCore 17/10 · BroadwayUI 6/4 · BroadwayCatalog 2/1 · README ✓ · AGENTS ✓ · Open: [`Shared/Broadway/TODOs.md`](Shared/Broadway/TODOs.md)

---

### RegionKit & RegionViewer

**Verified OK:** the per-region catalog drives `RegionStyle`, the pickers, and the App Intents `RegionEntity` with no `Region` enum to extend; `buildSourceOutlines()` decodes the 54 bundled per-region files, so RegionViewer's Source mode shows what ships.

**Files:** RegionKit 15/10 · RegionViewer 1/0 · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereIntents, WhereWidgets, WhereShareExtension, Where app

**Verified OK:** the reader/writer seams are well covered; the `IntentServices` handoff has no self-creating fallback; `@unknown default:` on widget-family switches; the post-midnight stale snapshot is documented as intentional degradation in the provider and both docs; `WhereTests` pins `.undetermined` as the launch reason under the UIScene lifecycle.

**Accepted:** the per-intent `perform()` glue is untested because `@Dependency` traps outside the perform flow — now explained in `WhereIntents/AGENTS.md`, though the README hasn't caught up (filed). Neither extension ships a test bundle, by design.

**Files:** WhereIntents 17/10 · WhereWidgets 7/0 · WhereShareExtension 5/0 · Where 6/2 · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### CreditKit, JournalKit, StuffCore, TestHostSupport, StuffTestHost

**CreditKit:** `./attribution --check` passes and the derivation is honest — it credits the TLA+ tooling and all four external agent skills while correctly excluding repo-owned skills and tooling-only packages. **Files:** 2/3 · Open: [`Shared/CreditKit/TODOs.md`](Shared/CreditKit/TODOs.md)

**JournalKit:** strong fuzz and truncation coverage; payload-agnostic, with no log semantics leaking in. **Files:** 2/3 · Open: [`Shared/JournalKit/TODOs.md`](Shared/JournalKit/TODOs.md)

**StuffCore:** intentional scaffold. **Files:** 1/1 · Open: [`Shared/StuffCore/TODOs.md`](Shared/StuffCore/TODOs.md)

**TestHostSupport:** dependency-free UIKit helpers, no bundle by design. **Files:** 1/0 · nothing open

**StuffTestHost:** the WhereCore embed is gone; each `.xctest` carries its own resource bundles and `PACKAGE_RESOURCE_BUNDLE_PATH` covers the beta-4 dedup. The scene configuration name is now owned solely by the Tuist manifest. **Files:** 2/0 · nothing open

---

## Limitations

- **Static analysis only.** The cloud agent runs Linux, which has **no Swift toolchain at all** — so no `tuist test`, no simulator, and also no `swift run bumper lint` and no `./xcstrings --lint`, both of which are CI gates. `./swiftformat --lint` (0/1007 files) and `./attribution --check` (up to date) were run and pass. CI on `main` is green at `46a84015`, which is what lets the "the Gregorian rule finds nothing" conclusion stand.
- **No snapshot pixels were inspected.** Where this pass judged a reference re-recorded, it read the **Git LFS pointer's `size` field**, not the image. That is strong evidence for the blank-capture item (66 KB → 3.2 MB cannot be solid white) and no evidence at all about whether a re-recorded ax5 reference still shows a layout defect. A macOS `./test --review` would settle those.
- **Runtime-dependent items are unconfirmed by design**: the launch-time notification prompt, Flyover's log routing, multi-process journal coordination, the CloudKit import-readiness race, Spotlight indexing, and Ledger's live API and Keychain paths. Each says so in its own entry.
- **No severity or category counts.** Earlier revisions of this report carried them; they could not be reconciled against the backlog and are omitted deliberately rather than estimated.
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
| LifecycleKitUI | `Shared/LifecycleKitUI/` | 5 | 3 | — | ✓ | ✓ |
| SnapshotKit | `Shared/SnapshotKit/` | 8 | 3 | — | ✓ | ✓ |
| SnapshotKitTesting | `Shared/SnapshotKitTesting/` | 14 | 11 | — | ✓ | ✓ |
| Inspector | `Shared/Inspector/` | 23 | 14 | 1 | ✓ | ✓ |
| Flyover | `Shared/Flyover/` | 50 | 12 | 1 | ✓ | ✓ |
| TestHostSupport | `Shared/TestHostSupport/` | 1 | 0 | — | ✓ | ✓ |
| BroadwayCore | `Shared/Broadway/BroadwayCore/` | 17 | 10 | — | ✓ | ✓ |
| BroadwayUI | `Shared/Broadway/BroadwayUI/` | 6 | 4 | — | ✓ | ✓ |
| PeriscopeCore | `Shared/Periscope/PeriscopeCore/` | 37 | 33 | — | ✓ | ✓ |
| PeriscopeUI | `Shared/Periscope/PeriscopeUI/` | 1 | 2 | — | ✓ | ✓ |
| PeriscopeTools | `Shared/Periscope/PeriscopeTools/` | 27 | 27 | 1 | ✓ | ✓ |
| RegionKit | `Where/RegionKit/` | 15 | 10 | — | ✓ | ✓ |
| WhereCore | `Where/WhereCore/` | 118 | 74 | — | ✓ | ✓ |
| WhereUI | `Where/WhereUI/` | 224 | 90 | 37 | ✓ | ✓ |
| WhereIntents | `Where/WhereIntents/` | 17 | 10 | — | ✓ | ✓ |
| LedgerCore | `Ledger/LedgerCore/` | 16 | 14 | — | ✓ | ✓ |

### Tuist app / extension targets

| Target | Path | Source | Test | README | AGENTS |
|--------|------|-------:|-----:|:------:|:------:|
| Where | `Where/Where/` | 6 | 2 | ✓ | ✓ |
| WhereWidgets | `Where/WhereWidgets/` | 7 | 0 | ✓ | ✓ |
| WhereShareExtension | `Where/WhereShareExtension/` | 5 | 0 | ✓ | ✓ |
| RegionViewer | `Where/RegionViewer/` | 1 | 0 | ✓ | ✓ |
| Ledger | `Ledger/Ledger/` | 8 | 0 | ✓ | ✓ |
| StuffTestHost | `Shared/StuffTestHost/` | 2 | 0 | ✓ | ✓ |
| BroadwayCatalog | `Shared/Broadway/BroadwayCatalog/` | 2 | 1 | ✓ | ✓ |

**Totals:** 623 source · 337 test · 40 image-snapshot Swift files across shipped targets (plus 4 Bumper rule/test sources and 2 unwired prototype sources). **361** LFS-backed reference images. **25** test bundles: 21 unit (`Stuff-iOS-Tests`, plus `Ledger-macOS-Tests`) and 4 image (`StuffSnapshotTests`) — every one is a member of a CI scheme.

**Group-folder docs:** `Shared/Broadway/` and `Shared/Periscope/` carry the required group-level pair. `Where/` has `AGENTS.md` but **no `README.md`**, and `Ledger/` has **neither** — both filed in the root [`TODOs.md`](TODOs.md).

---

## Changes since July 26, 2026 audit

| Area | July 26 state | August 9 state |
|------|---------------|----------------|
| Target count | 14 SPM + 6 Tuist | **20 SPM + 7 Tuist** — Ledger/LedgerCore (#103), Flyover (#156), LifecycleKitUI, plus CreditKit, SnapshotKit and SnapshotKitTesting now counted |
| File count | ~359 source / ~198 test | **623 / 337** (WhereUI 113 → 224, WhereCore 87 → 118, PeriscopeTools 24 → 27) |
| Platforms | iOS only | iOS **and native macOS** — Ledger is the first macOS app, with its own `test-macos` CI job and a `Ledger-macOS-Tests` scheme, because no single xcodebuild destination builds both |
| Renames | `SwiftDataInspector` | **`Inspector`** (#158), now also a DEBUG boot runtime the app can launch instead of its regular composition root |
| Image suites | 1 bundle, 232 references | **4 bundles** (WhereUI, Flyover, Inspector, PeriscopeTools), **361** references, one shared `StuffSnapshotTests` scheme; scrolling content now captures at intrinsic height (#196) |
| Formal specs | — | **9 TLA+ specifications** under `Where/Specifications/`, run locally via `./tla-check` (opt-in, not CI) — launch lifecycle, scope exclusivity, log routing, post-write reconcile, remote device removal, store-perform serialization, and more |
| Multi-device | Single install | Installation-local recording consent, advisory check-ins, removal tombstones, a Devices settings screen, and a removal-recovery gate (#160) |
| Persistence | Unscoped fetches | Every scoped fetch is generation-aware, composed before materialization (#209) |
| Agent tooling | 2 skills | **10 skills** (6 repo-owned, 4 external and pinned), a PR template, and `codex-watchdog` + `worktree` for Codex-managed checkouts |
| Backlog | 8 `TODOs.md` | **13** — `Ledger/` and `Shared/Flyover/` opened by this pass |
| Dev scripts | 10 | **13** (`tla-check` added; the root `AGENTS.md` list had omitted it) |
