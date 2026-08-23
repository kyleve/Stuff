# Swift Module Audit Report

Read-only review of all **21 SPM library targets**, **7 Tuist app/extension targets**, **26 test bundles**, the repo-owned **Bumper Bowling** architecture rules, and — new to this edition — the **retained tooling** under `Tools/` (688 source / 368 test / 47 image-snapshot Swift files across shipped targets, plus 2 unwired prototype sources; 12 Python/Ruby implementations under 21 direct test files). No production code was changed.

**Date:** August 23, 2026  
**Method:** Read-only verification of every open finding in all 13 `TODOs.md` files against current source, module-by-module, with each citation re-derived; file-count refresh; a rule-by-rule review of the window's ~1,900 lines of new Swift against the root and per-module `AGENTS.md` files; and — for the first time in this series — **actually executing** the checks a Linux host can run (`./swiftformat --lint`, `./attribution --check`, `./shellcheck`, `./snapshot-shards check`, and both direct tooling suites). Four candidate findings were rejected after inspection; two published claims were corrected against a recount.  
**Prior audit:** August 16, 2026 (677 source / 361 test), merged as PR #282. This is a genuine one-week diff against a baseline that reached `main`.

> **This report carries no actionable items.** Every finding it describes is filed
> in a `TODOs.md`; the root [`TODOs.md`](TODOs.md) owns the item format and says
> which file covers which area. Read this one for *shape and drift* — what each
> module verified clean, the themes running across the backlog, and how the tree
> moved since the last pass — and take the work itself from the `TODOs.md` files.
> It is true as of the header date above, **not** as of `HEAD`.

---

## Executive summary

**This was a tooling week, and the tooling is where the findings are.** Seven of the window's eight commits touched no shipping Swift at all: four hardening the retained Python and Ruby behind the root commands (#283, #284, #287, #288) and one rebuilding the CircleCI iOS side into a build-once/shard-the-snapshots topology (#276). The two feature PRs (#286, #289) and one test-infrastructure PR (#290) account for the rest.

That split matters because of what it changed about *verifiability*. The hardening stack made the tooling importable and directly tested — 12 implementations under 21 test files, gated in both CI systems — and those tests need no Xcode, no Swift toolchain, no simulator, and no network. They are the first body of tests in this repo that a Linux host can genuinely run. So this is the first audit that could execute something rather than only read.

What running them found, in order of how much it should change your reading of the backlog:

- **One backlog item closed** — the Locations ranking-reorder animation, by PR #289 — against last week's zero. It shipped a different and better design than the item proposed, which the closing entry records rather than smoothing over.
- **The new tooling suites fail on Linux instead of skipping.** 61 of 62 Python cases and 62 of 75 Ruby cases pass here; every failure is a platform assumption rather than a regression, in three separable groups. `Tools/ADVERSARIAL_TEST_PLAN.md` already declares a per-command platform matrix — the tests simply do not honor it. Filed.
- **`sync-agents` stopped working from a bare call, and two docs still promised it would.** PR #283 gave it a `#!/usr/bin/env ruby` shebang, making it the only root command of eighteen that reaches its interpreter that way. It exits 127 on a host with no system Ruby. The root `AGENTS.md` Linux table listed the bare invocation as a working check, and the `todo-triage` skill told this very automation the same thing. Both corrected here; the launcher fix is filed.
- **The week's new Swift is clean.** A rule-by-rule review of PRs #286/#289/#290 against the errors-and-failure, state-modeling, typed-identifier, localization, calendar, accessibility, and coverage conventions produced exactly **one** finding — and it is pre-existing debt that new code made visible, not new drift. That is a different result from the last two windows, where the new defects were copies of already-filed ones.
- **PR #289 is the shape to copy.** It landed a behavior change, four new module rules describing its own invariants, four unit-test files, and a DEBUG lab whose stated purpose is that a settled snapshot cannot prove a transition — an admission, in the docs, of what its own tests cannot cover.
- **The hardening dissolved a filed item's argument without closing it.** `affected_bundles` went from ~164 lines of heredoc Python to 85 lines of importable, directly tested module. The P2 proposing to replace it with Tuist selective testing called it "the most fragile thing in the script"; that is no longer the strongest reason to act.

---

## Top findings

Pointers only — each one's evidence and suggested fix live in the linked file.

| # | Area | Issue | Filed in |
|---|--------|-------|----------|
| 1 | Bumper Bowling | `where.gregorian_calendar` matches only an explicit `Calendar` base, so it reports none of the 12 implicit `.current` sites — and its own mutation test feeds it only the explicit form, which is why it has survived five audits | [`TODOs.md`](TODOs.md) P0 |
| 2 | WhereCore | `DailySummaryReconciler.reconcile()` is absent from the post-day-change fan-out — the daily notification body stays stale until a foreground re-`configure` | [`Where/TODOs.md`](Where/TODOs.md) P0 |
| 3 | PeriscopeCore | Records emitted before the store attaches reach neither the store nor the journal — the durable log has a hole at every launch | [`Shared/Periscope/TODOs.md`](Shared/Periscope/TODOs.md) P0 |
| 4 | Scripts / CI | The new direct tooling suites fail on a non-macOS host rather than skipping, so a red Linux run is indistinguishable from a real regression | [`TODOs.md`](TODOs.md) P1 |
| 5 | Scripts | `sync-agents` is the one root command reaching its interpreter through a shebang, so its documented invocation exits 127 without a `mise exec --` prefix | [`TODOs.md`](TODOs.md) P1 |
| 6 | WhereUI | `CalendarDay.displayDate` resolves through `Calendar.current`; four production sites remain, and every day label flows through them | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 7 | CI / docs | The snapshot suite's "never parallelize this" warning is still absent from CircleCI — and the job now shows a working `parallelism` key, making the omission a worse trap than before | [`TODOs.md`](TODOs.md) P1 |
| 8 | WhereUI | Notification authorization is requested unprompted during launch, and all three preferences default to `true` on a fresh install | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 9 | SnapshotKitTesting | Accessibility-parse failures `preconditionFailure` and so kill the whole host process — and PR #290 doubled the number of parses a raised-floor case can trap in | [`Shared/SnapshotKitTesting/TODOs.md`](Shared/SnapshotKitTesting/TODOs.md) P1 |
| 10 | SnapshotKit | A case's content is built once and re-hosted for every configuration, while both the type's doc comment and its `AGENTS.md` tell authors each access is independent | [`Shared/SnapshotKit/TODOs.md`](Shared/SnapshotKit/TODOs.md) P1 |

---

## Cross-cutting themes

The synthesis across items that no single item shows.

### A repo with macOS-only CI cannot tell which of its own tests are portable

The hardening stack created something this repo did not have: a body of code with no toolchain dependency, covered by tests that could run anywhere. Both CI systems gate those tests, and both run them only on macOS. So nothing in the pipeline distinguishes a test that is *portable* from one that merely *happens to pass where we run it* — and the difference turns out to be 14 cases. Three separable causes, none of them a bug in the code under test: macOS-only system binaries reached by the implementations (`/usr/bin/lockf` in `simulator`, `/usr/bin/plutil` in the app installer), a pristine-`HOME` hygiene test that inadvertently depends on a *system* interpreter, and one assertion pinning a shell's 126-vs-127 exit-status convention. The plan document already assigns each command a platform. The gap is that the tests do not read it, and no gradient anywhere would have told anyone.

### The always-loaded doc is the one that goes false fastest, and this time it went false about the reader

`AGENTS.md` is injected into every agent's context. Its "What works on Linux" table listed a bare `./sync-agents` as a working check, and the `todo-triage` skill — the procedure this very automation follows — repeated it. Then PR #283 gave the script a Ruby shebang, and the claim became a 127. The failure mode is worth naming precisely: a rewrite that keeps a command's *name*, *arguments*, and *behavior* identical, and changes only how it reaches its interpreter, is invisible to every reviewer and every lint in the repo, while breaking the one sentence that told a Linux reader it would work. There is no gate that could have caught it — which is the argument for the launcher, not for more documentation.

### Specific module rules are working; the gap is where a rule was never written down

The week's ~1,900 lines of new Swift produced one convention finding, and reviewing them was mostly an exercise in confirming that the rules held: no `try?` swallowing a failure, no raw SF Symbol string, no `Calendar.current`, no Core parameter default, no English literal in shipped copy, every new screen declaring `SnapshotProviding` on arrival. The planned-stay path in particular keeps "no fix available" and "outside the region" as distinct states from the verifier through the model to two different rows on screen, which is exactly the make-invalid-states-unrepresentable rule applied without being told to. The one finding is the mirror image: Flyover catalog titles are English literals at every one of ~20 registrations, against a rule (`Where/AGENTS.md`: "DEBUG-only UI is still localized") that no lint enforces and that nothing in the Flyover code says is carved out. Because those titles are plain `String` arguments rather than `Text`, Xcode never extracts them, so no catalog can see the gap. A convention with a lint holds; a convention with only a sentence drifts uniformly, and then a new screen follows both halves at once.

### A feature that ships its own rules and admits what its tests cannot prove

PR #289 replaced a proposed one-line `.animation(_:value:)` with a custom layout that interpolates card positions while holding the semantic `ForEach` order fixed — because moving the source hierarchy would reorder VoiceOver mid-transition. It then wrote four rules into `WhereUI/AGENTS.md` pinning the parts a future edit would get wrong (keep source order stable during the crossing; commit the real order without animation afterwards; one `GlassEffectContainer` per card with the identity transition; keep the ranking layout out of the calendar zoom namespace), and added a DEBUG lab with the instruction to play at least two overtakes after any ranking-motion change *because a settled snapshot cannot prove a transition*. That last part is the unusual one: the change documents the limit of its own coverage rather than letting a green suite imply more than it checked. The comparable case in this repo's history is LifecycleKit's reveal rework, and both are worth pointing at when a behavior change arrives without them.

### Hardening can dissolve a filed refactor's motivation without closing it

Two root P2s argued from the state of `./test`. One said the script contradicted the root rule about being the only test entry point; the doc half is now closed and only the design question remains. The other proposed replacing `affected_bundles` with `tuist xcodebuild test-without-building`, arguing chiefly that the parser was "the most fragile thing in the script": ~164 lines of Python inside a heredoc, inferring declaration boundaries from indent level, with a verifier that exited from inside the shell. It is now 85 lines in an importable module with three direct tests covering dependent propagation, over-selection, and short-parse rejection. The regex parse of `Project.swift` and the indent-level inference are both still there, so the item is not closed — but its argument has to be rebuilt from the remaining fragility rather than from the old framing. This is the second week running where a filed item needed its *premise* corrected rather than its citations refreshed, which suggests re-reading an item's reasoning, not just its line numbers, deserves to be part of the standing procedure.

### The dating discipline held where it was applied, and only there

Last week's pass concluded that a number written into prose has a half-life of about a week here, and recommended dating any that cannot be re-measured in place. Both reference counts in `SnapshotKitTesting/AGENTS.md` carried their date, so this week they were *stale but not false*, and correcting them to 472 was mechanical. `CI_BENCHMARK.md` shows the other half of the experiment: it gates renderer compatibility on "all 381 checked-in references" and on a specific Xcode 27 beta 4 build, undated, unreferenced from anywhere in the repo, and now wrong on both. Same repo, same week, same class of claim — the only difference is whether someone wrote down when it was true.

---

## Per-module notes

What each module was checked for and found clean, plus the trade-offs this pass accepted as deliberate. Open work is in the linked `TODOs.md`.

### Retained tooling (`Tools/`) — first audit

New as an audited area, though the directory arrived with PR #283. Twelve importable implementations (7 Python, 5 Ruby) hold the parsing, reporting, and filesystem policy the root commands used to inline; 21 test files under `Tools/Tests/` exercise them directly, gated in the GitHub `format` job and CircleCI's `test_ci_helpers`.

**Verified OK:** both suites are wired into both CI systems, so the tests are genuinely run rather than merely present; `./shellcheck` (new this window, `#!/bin/sh`) passes over every tracked shell file; `./snapshot-shards check` validates the checked-in plan and reports 47 suites across 3 planned shards plus intake; `./test`'s architecture path still reaches `bumper config`/`test`/`lint`; the shard plan's intake behavior worked exactly as documented — PR #289's new `RankingAnimationLabViewSnapshotTests` is the one suite on the intake shard, which is what the root `AGENTS.md` says should happen to a new suite until rebalancing.

**Executed here, and the reason this area is worth auditing:** 61/62 Python and 62/75 Ruby cases pass on Linux. The 14 failures are platform assumptions, filed as a root P1.

**Docs:** `README.md` ✓ · `AGENTS.md` — none, and both of its docs are linked from nothing outside the directory (filed). Not a module by the per-module rule, so this is a discoverability finding rather than a missing-pair violation.

**Files:** 12 implementation / 21 test (non-Swift) · Open: [`TODOs.md`](TODOs.md)

---

### Bumper Bowling — architecture lint

Covers **Where production sources only** (`BumperBowling.swift:15-23`). CI hard-gates it through the `architecture` job's `./test --architecture-only` (`.github/workflows/ci.yml:68-69`), which reaches the three bumper subcommands via `run_architecture_checks` at `test:252-268` — a citation that moved this window with the script rewrite. CircleCI passes `--skip-architecture` at four sites so it runs once.

**Verified OK:** all ten `where.*` rules appear in `.bumper/RULES.md` and each has a mutation test (eleven `@Test` functions cover them, the extra being a second concurrency case); `component_boundary` and `forbidden_import` are mutation-tested; `RULES.md`'s "the mutation tests prove…" sentence is still correctly scoped to imports, so it is missing coverage rather than a false claim.

**Corrected here:** a recount of the implicit-`.current` sites reached 15 by including five spelled-out uses in `Where/*/Tests/`, which are outside the lint's production-only scope. The number is **12**, unchanged for a third pass, and the item now carries the scoping rule as a tripwire.

**Not covered, by design:** everything under `Shared/`, all of `Ledger/`, test bundles, and `Where/Specifications/`.

**Files:** 4 rule/test sources · RULES.md ✓ · Open: [`TODOs.md`](TODOs.md)

---

### WhereCore

**Verified OK:** PR #286's `PlannedStayLocationVerifier` keeps "no location fix available" and "outside the planned region" as separate states rather than collapsing an absent fix into a negative verdict — the honest handling of `LocationSource.requestCurrentLocation()`'s documented `nil` return, carried 1:1 through `LocationForecastModel` and rendered as two distinct rows; it arrived with its namesake test, which is what held the namesake-debt count flat for the first time.

**Standing:** the three fan-out and lifecycle items have now survived every pass since July 26 — the summary reconcile, `setPrimaryRegions`, and the hard-deleting untrack. All re-confirmed against current source, with every citation re-derived (the `SwiftDataStore` ones moved ~70 lines).

**Corrected here:** the P0 said backup, remote-import *and reset* reconcile summary through `DerivedDataReconciler`. Reset does it directly via `summary.reconcile()`, rebuilding the summary without reminders, widgets, or issue alerts — worth knowing before citing reset as the pattern to copy.

**Files:** 128 source / 83 test · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereUI

The busiest module again: +10 sources and +5 tests across the ranking-animation and planned-stay work, and the only module with a closure this week.

**Verified OK:** `Calendar.current` still confined to four helper defaults and eight DEBUG fixtures, with neither feature PR adding one; no `try?` swallowing a failure, no bare `default:`, no raw SF Symbol string, and no English literal in shipped `Text` across the new surface; the ranking work's persistence reuses the existing year-keyed, `Region.rawValue`-keyed preference channel rather than inventing a wire shape, and drops unknown keys on load; `StampBanner`'s combined accessibility element is correct because its seal, rosette, and arrow are all `accessibilityHidden` first; `GatedCurrentLocationSource` conforms to the production `LocationSource` protocol, lives in its own support file, and polls a predicate rather than sleeping; the new stylesheet tokens are pinned in `WhereStylesheetTests`, as that module's rule requires of any token change.

**Accepted:** five new source files have no namesake test (two rows, a modifier, and two lab helpers), each covered through a parent's snapshot matrix or stack tests. Consistent with how the Card Designer subviews are treated, so recorded rather than filed.

**Files:** 268 source / 101 test / 44 image-snapshot · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereCrashReporting

Nothing shipped. Unchanged since its first audit last window.

**Files:** 3 source / 2 test · README ✓ · AGENTS ✓ · Open: nothing filed

---

### PeriscopeCore, PeriscopeUI, PeriscopeTools

Nothing shipped. None of the 19 open items closed, and every citation re-derived.

**Verified OK:** the span-record P0's 2026-08-09 correction still describes the code accurately (`spanID`/`spanExit`/`spanRelaunchPolicy` are computed downcasts; `LogRecord` stores only `bypassesFloors`); the hosting-smoke debt **held at 20 tests across 10 files for a third consecutive audit**, every cited line still exact; `PeriscopeViewerSnapshotTests` is still the only file in the module's image bundle, so none of the conversion has begun.

**Corrected here:** the multi-process journal item cited the unconditional directory delete at `:42-44`, which is the ingest loop; it is at `:61` and `:71`. The decomposition P0 now records concrete sizes — `Periscope.swift` 935 lines, `PeriscopeStore.swift` 1235 — so the next pass has a baseline instead of an adjective.

**Files:** PeriscopeCore 38/33 · PeriscopeUI 1/2 · PeriscopeTools 27/27 (+1 image source, 2 references) · README ✓ · AGENTS ✓ · Open: [`Shared/Periscope/TODOs.md`](Shared/Periscope/TODOs.md)

---

### SnapshotKit & SnapshotKitTesting

PR #290 was the window's only framework change: raised-floor accessibility captures now parse, settle through the declared floor, then re-parse before capturing, guarded by a new `AccessibilitySnapshotViewControllerTests` that probes a view flipping colour on window attachment.

**Verified OK:** the framework halves stay split as documented; each image bundle lists only `SnapshotKitTesting` in `extraPackageProducts`; the reporting channels still separate `report(...)`/`emit()` from `line(...)`, so no test can fabricate a row into `--review` or `--timings`; the new two-pass behavior arrived documented in both `AGENTS.md` and `README.md` and guarded by a test.

**Worth reading together:** PR #290 did *not* touch the four `preconditionFailure` arms in `parseAccessibility()`, so a raised-floor accessibility case can now trap in two parses where it previously had one. The change is correct and the item is unchanged, but the exposure it describes grew — noted in the item rather than re-filed.

**Corrected here:** the reference count (472, from 466) in both the backlog and the module's `AGENTS.md`, which kept its dated form; the addressable settle-floor split (39 configurations, from 37 — `RankingAnimationLabView` adds two at 1.0s, and belongs to the chrome-adaptation group rather than the report-loading one); and three drifted citations in the coverage sub-bullets.

**Files:** SnapshotKit 8/3 · SnapshotKitTesting 16/16 · README ✓ · AGENTS ✓ · Open: [`Shared/SnapshotKit/TODOs.md`](Shared/SnapshotKit/TODOs.md), [`Shared/SnapshotKitTesting/TODOs.md`](Shared/SnapshotKitTesting/TODOs.md)

---

### Flyover

Nothing shipped, and for once that is the finding: the single open item has widened in every recent window as new plan math arrived without new image coverage. Twelve test files, five references, and the one `canvasAndList` case are all unchanged, so the gap held.

**Files:** 54 source / 14 test / 1 image source, 5 references · README ✓ · AGENTS ✓ · Open: [`Shared/Flyover/TODOs.md`](Shared/Flyover/TODOs.md)

---

### Inspector

Nothing shipped.

**Verified OK:** the `withKnownIssue` quarantine on the dark SwiftData capture is still one of exactly **two** in the whole repo — re-counted rather than assumed, the other being WhereUI's Elsewhere inflection guard at `WhereFormatTests.swift:89`; the bundle still has one case producing four references.

**Files:** 23 source / 14 test / 1 image source, 4 references · README ✓ · AGENTS ✓ · Open: [`Shared/Inspector/TODOs.md`](Shared/Inspector/TODOs.md)

---

### LifecycleKit & LifecycleKitUI

Nothing shipped. The single P2's two `precondition` sites are unchanged and still unexercised.

**Files:** LifecycleKit 8/10 · LifecycleKitUI 6/4 · README ✓ · AGENTS ✓ · Open: [`Shared/LifecycleKit/TODOs.md`](Shared/LifecycleKit/TODOs.md) (LifecycleKitUI's items live in LifecycleKit's file by design)

---

### Broadway (BroadwayCore, BroadwayUI, BroadwayCatalog)

Nothing shipped. All eight items still open, and every citation in the file still resolves exactly — including the `Project.swift` line numbers, which survived a window that edited that manifest.

**Files:** BroadwayCore 17/10 · BroadwayUI 6/4 · BroadwayCatalog 2/1 · README ✓ · AGENTS ✓ · Open: [`Shared/Broadway/TODOs.md`](Shared/Broadway/TODOs.md)

---

### CreditKit

`generate-attribution.rb` was hardened this window and gained direct tests in `Tools/Tests/generate_attribution_test.rb`.

**Verified OK:** `./attribution --check` passes at **12** credits (up from 11 — `.agents/development-tools.json` gained an entry with the pinned ShellCheck).

**Standing, and sharper for it:** the `github_slug` regex is byte-identical after the hardening, and the new tests cover package-graph parsing and source validation without a slug-format case. The file is now tested *around* the one line the item is about, which makes the gap easier to miss rather than harder.

**Files:** 2/3 · README ✓ · AGENTS ✓ · Open: [`Shared/CreditKit/TODOs.md`](Shared/CreditKit/TODOs.md)

---

### Ledger, LedgerCore

Core and app sources untouched. The window's only Ledger change was PR #287's transactional rework of `Ledger/install` and its app-leaf README — which is worth stating precisely, because "Ledger shipped nothing" has been this report's phrasing for three weeks and is now true only of the Swift.

**Verified OK:** still 13 test files over 16 sources, still the three named files without a namesake test, and `Ledger-macOS-Tests` still builds the app while running only `LedgerCoreTests`. The module remains outside Bumper's scope and outside `./test`'s reach — the second of which is filed as a root P2 whose documentation half is now closed.

**Files:** LedgerCore 16/14 · Ledger 8/0 · README ✓ · AGENTS ✓ (leaf modules; the **group** folder is missing both — filed) · Open: [`Ledger/TODOs.md`](Ledger/TODOs.md)

---

### RegionKit & RegionViewer

Nothing shipped. PR #172's honest "GeoJSON decoding is not covered" statement is intact at `RegionKit/README.md:165-168`, so the doc half of that pairing stays closed and only the test gap remains.

**Files:** RegionKit 15/10 · RegionViewer 1/0 · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereIntents, WhereWidgets, WhereShareExtension, Where app

Nothing shipped.

**Corrected here:** the `convention(WhereIntents)` item said `WhereShortcuts` registers five shortcuts. It registers **four** — Today, Days, RegionOnDate, LogDay. The `WhereIntents/README.md` citation also pointed past the end of an 88-line file.

**Files:** WhereIntents 15/9 · WhereWidgets 7/0 · WhereShareExtension 5/0 · Where 8/4 · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### JournalKit, StuffCore, TestHostSupport, StuffTestHost

**JournalKit:** nothing shipped; both test items unchanged. **Files:** 2/3 · Open: [`Shared/JournalKit/TODOs.md`](Shared/JournalKit/TODOs.md)

**StuffCore:** intentional scaffold. **Files:** 1/1 · Open: [`Shared/StuffCore/TODOs.md`](Shared/StuffCore/TODOs.md)

**TestHostSupport:** dependency-free UIKit helpers, no bundle by design. **Files:** 1/0 · nothing open

**StuffTestHost:** unchanged. **Files:** 2/0 · nothing open

---

## Limitations

- **Mostly static analysis, but not entirely — and this edition says which is which.** The cloud agent runs Linux with **no Swift toolchain**, so no `tuist test`, no simulator, no `./test --architecture-only`, and no `./xcstrings --lint`. **Executed and passing:** `./swiftformat --lint` (0 of 1110 files), `./attribution --check` (12 credits, up to date), `./shellcheck`, `./snapshot-shards check`. **Executed with failures analyzed:** both direct tooling suites (see the root P1). Nothing about the Swift targets was executed.
- **The "the Gregorian rule finds nothing" conclusion rests on CI being green**, not on running the lint here. The mechanism — the rule's filter plus its one-sided mutation test — is read from source and is sufficient on its own; the green gate is corroboration.
- **No snapshot pixels were inspected.** Reference counts come from Git LFS pointers, never decoded images. Whether PR #289's re-recorded `locations.Loaded_iPad` still bakes the inflection markup is inferred from the unchanged rendering path, not seen; a macOS `./test --review` would settle it.
- **The ranking animation is the one closure this pass could not watch run.** Its correctness claim rests on reading the layout, the reconciliation, four unit-test files, and the module rules the PR added — and the PR's own instruction is that a settled snapshot cannot prove a transition, which applies to this report too.
- **Runtime-dependent items are unconfirmed by design**: the launch-time notification prompt, Flyover's log routing, multi-process journal coordination, the CloudKit import-readiness race, Spotlight indexing, whether Bitdrift receives anything on a device, and Ledger's live API and Keychain paths. Each says so in its own entry.
- **The new-Swift review was rule-directed, not exhaustive.** ~1,900 lines across three PRs were read against a named checklist of repo conventions. A defect outside those rules would not have been looked for.
- **No item counts by severity.** They could not be reconciled against the backlog in earlier revisions and remain deliberately omitted rather than estimated.
- `Shared/Periscope/Prototypes/JournalBenchmark` (2 sources plus a manifest) is wired into no target and is excluded from every count here.

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
| WhereUI | `Where/WhereUI/` | 268 | 101 | 44 | ✓ | ✓ |
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

**Totals:** 688 source · 368 test · 47 image-snapshot Swift files across shipped targets (plus 4 Bumper rule/test sources and 2 unwired prototype sources). **472** LFS-backed reference images (461 WhereUI, 5 Flyover, 4 Inspector, 2 PeriscopeTools). **26** test bundles: 22 unit (21 in `Stuff-iOS-Tests`, plus `LedgerCoreTests` in `Ledger-macOS-Tests`) and 4 image (`StuffSnapshotTests`) — every one a member of a CI scheme. Outside the Swift totals: **18** root dev commands, **12** retained Python/Ruby implementations under **21** direct test files, and **10** TLA+ specifications.

**Group-folder docs:** every one of the 28 module folders above carries its `README.md` + `AGENTS.md` pair. At the *group* level, `Shared/Broadway/` and `Shared/Periscope/` carry the required pair; `Where/` has `AGENTS.md` but **no `README.md`**, and `Ledger/` has **neither** — both filed in the root [`TODOs.md`](TODOs.md). This window edited `Where/Where/README.md` and `Ledger/Ledger/README.md`, both app-target leaves one directory below the files that are actually missing.

---

## Changes since August 16, 2026 audit

| Area | August 16 state | August 23 state |
|------|----------------|-----------------|
| Window shape | 39 commits, 782 files, almost all feature work | **8 commits, 152 files, +12,119/−2,169** — seven of eight touched no shipping Swift |
| File count | 677 source / 361 test | **688 / 368** (WhereUI 258 → 268, WhereCore 127 → 128, SnapshotKitTesting tests 15 → 16) |
| Backlog closures | **0** | **1** — the Locations ranking-reorder animation (#289), shipped as a position-interpolating layout rather than the proposed `.animation(_:value:)` |
| Retained tooling | Shell-inlined parsing; no direct tests | **12 importable Python/Ruby implementations under 21 direct test files** (#283/#284/#287/#288), gated in both CI systems, plus `Tools/README.md` and an 11 KB `ADVERSARIAL_TEST_PLAN.md` |
| Dev commands | 16 | **18** — `shellcheck` and `snapshot-shards` are new |
| `./test` size | 941 lines | **709**, plus `Tools/test_runner.py` at 445; `affected_bundles` went ~164 → **85** lines and gained three direct tests |
| CircleCI iOS topology | `test-ios` + `snapshot`, both `m4pro.medium`, each building | **Build-once/attach** (#276): one `m4pro.large` builder feeds a unit worker and 4-way sharded snapshot workers via `./snapshot-shards` |
| Linux verifiability | Format lint and agent sync only | **Format lint, attribution check, ShellCheck, shard-plan check, and both tooling suites** — the suites reveal 14 macOS-only cases, and bare `./sync-agents` now exits 127 |
| Image suites | 4 bundles, 466 references | **4 bundles, 472 references** — WhereUI 455 → 461 (`RankingAnimationLabView` +2, planned-stay states +4) |
| Settle-floor debt | 37 addressable configurations | **39** — `RankingAnimationLabView.Default` at 1.0s |
| Target count | 21 SPM + 7 Tuist | **Unchanged.** No new module; the audited-area count grew by `Tools/` |
| Test bundles | 26 | **26** — the new snapshot suite is a file in an existing bundle, running on the shard plan's intake shard as designed |
| Docs | PR #172's rewrite still settling | **Two false Linux claims corrected** (root `AGENTS.md`, `todo-triage` skill) after `sync-agents` gained a Ruby shebang |
| Backlog | 13 `TODOs.md` | **13** — no new area needed one; the tooling items belong in the root file by the placement rule |
