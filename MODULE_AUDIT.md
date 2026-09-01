# Swift Module Audit Report

Read-only review of all **20 SPM library targets**, **7 Tuist app/extension targets**, **26 test bundles**, the repo-owned **Bumper Bowling** architecture rules, and the retained Python/Ruby tooling layer (694 source / 368 test / 47 image-snapshot Swift files across shipped targets, plus 2 unwired prototype sources). No production code was changed.

**Date:** August 30, 2026  
**Method:** Read-only verification of every open finding in all 12 `TODOs.md` files against current source, module-by-module, with each citation re-derived; file, reference-image, and suite-count refresh; new-surface review of the 11 commits since the last audit; and a pass over the tree against the repo's own written rules. Unlike every prior edition, this pass also **executed** the Linux-capable half of CI's `format` job — `./swiftformat --lint`, `./shellcheck`, `./attribution --check`, and both retained-tool test suites — plus `./snapshot-shards check`, which is how its one new finding was discovered rather than read. Two further candidate findings were raised and rejected against source; both are recorded below. Unlike every prior edition, this pass also **executed** the Linux-capable half of CI's `format` job — `./swiftformat --lint`, `./shellcheck`, `./attribution --check`, and both retained-tool test suites — plus `./snapshot-shards check`, which is how its one new finding was discovered rather than read. Two further candidate findings were raised and rejected against source; both are recorded below.  
**Prior audit:** August 16, 2026 (677 source / 361 test), merged as PR #282. **This is a two-week window, not one** — the previous audit landed on `main`, so its numbers are the real baseline, but no audit ran on August 23.

> **This report carries no actionable items.** Every finding it describes is filed
> in a `TODOs.md`; the root [`TODOs.md`](TODOs.md) owns the item format and says
> which file covers which area. Read this one for *shape and drift* — what each
> module verified clean, the themes running across the backlog, and how the tree
> moved since the last pass — and take the work itself from the `TODOs.md` files.
> It is true as of the header date above, **not** as of `HEAD`.

---

## Executive summary

**Two items closed, one filed, and one closure came from a direction the backlog did not predict.** After a window in which nothing closed at all, PR #289 resolved the Locations ranking-reorder P2 — and resolved it by building something larger than the item asked for. The item proposed wrapping the card `ForEach` in an `.animation(_:value:)`; what shipped is an explicit interpolated layout, a keyframe-driven stack, and a single reconciliation that now releases counts, order, flourish, persistence, and haptics together. PR #300 closed the StuffCore tautological-test P2 the simpler way the backlog had been pointing at for weeks — by deleting the empty module rather than growing it — which also removed the twelfth area `TODOs.md`. That is the useful signal in this pass: what moved was moved by feature work and a small refactor landing on `main`, not by anyone reading the backlog.

What the pass found, in order of how much it should change your reading of the backlog:

- **The audit ran real checks for the first time, and one failed.** PR #283 made ShellCheck and the retained Python/Ruby tool suites steps in CI's `format` job — the first CI gates in this repo that need neither Xcode nor a Swift toolchain. Running them here surfaced a test that can only pass on macOS: it asserts bash's `126` exit status for an unlaunchable command, where Linux reports `127`. CI cannot report this, because CI only runs on macOS. Filed as one item with four halves — three more macOS assumptions turned up beside it, all from the same cause.
- **Two candidate findings were rejected, and rejecting them is the point.** A hand-rolled Reduce Motion read in the new Ranking Animation Lab looked like a violation of the `@MotionIsStatic` rule; it is not, because that rule is scoped to motion that never settles, and nothing in the lab plays without a tap. An `assertionFailure` in the new card-reconciliation modifier looked like swallowed error handling; it is the arm the repo's own rule prescribes, on a path `Task.sleep` cannot actually reach. Both are recorded here so the next pass does not re-file them.
- **A published count was wrong in a way the backlog had been repeating for five audits.** The `SnapshotProviding` item claimed three Settings drill-ins lacked image coverage and that they were "the only" ones. Enumerating every `*View.swift` with a `#Preview` and cross-checking against `SettingsView.destination(for:)` found **five**, and ten further views outside Settings. Corrected in place, with the method written down so it can be re-derived rather than carried.
- **The snapshot job is now parallel, and the warning against parallelizing it is still missing.** PR #276 shards snapshots across four CircleCI containers by suite. That is the safe axis. The in-container axis is the unsafe one, and the paragraph explaining why never travelled from GitHub Actions. A reader now arrives at a job that visibly *is* parallelized with nothing marking the line. The filed item was sharpened rather than merely re-dated.
- **`./test` shrank by 219 lines by moving its logic out rather than losing it.** The four Scripts PRs lifted report parsing and bundle selection into importable, directly tested Python under `Tools/`. That retires the "fragile embedded parser" premise of a standing P2 — the parser is now covered by name — leaving only the design question the item was really asking.
- **The renderer is pinned now.** PR #297 introduced `.xcode-build-version` (`27A5252f`), gated in both `./test` and the CircleCI runner check. A snapshot suite whose references depend on one toolchain finally says which one.

---

## Top findings

Pointers only — each one's evidence and suggested fix live in the linked file.

| # | Module | Issue | Filed in |
|---|--------|-------|----------|
| 1 | Bumper Bowling | `where.gregorian_calendar` matches only an explicit `Calendar` base, so it reports none of the 12 implicit `.current` sites — and its own mutation test only feeds it the explicit form, which is why it has now survived five audits | [`TODOs.md`](TODOs.md) P0 |
| 2 | WhereCore | `DailySummaryReconciler.reconcile()` is absent from the post-day-change fan-out — the daily notification body stays stale until a foreground re-`configure` | [`Where/TODOs.md`](Where/TODOs.md) P0 |
| 3 | PeriscopeCore | Records emitted before the store attaches reach neither the store nor the journal — the durable log has a hole at every launch | [`Shared/Periscope/TODOs.md`](Shared/Periscope/TODOs.md) P0 |
| 4 | WhereUI | `CalendarDay.displayDate` resolves through `Calendar.current`; four production sites remain, and every day label flows through them | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 5 | CI / docs | The snapshot suite's "never parallelize this" warning is still absent from the file that now reads `parallelism: 4` | [`TODOs.md`](TODOs.md) P1 |
| 6 | Scripts | The retained-tool suites are CI's only Xcode-free gate and pass only on macOS — a hardcoded `126` exit status, a hermetic `PATH` that needs a system Ruby, and `sync-agents` unable to find Ruby at all | [`TODOs.md`](TODOs.md) P1 |
| 7 | WhereUI | Notification authorization is requested unprompted during launch, and all three preferences default to `true` on a fresh install | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 8 | WhereCore | Untracking a region hard-deletes the row, so re-aggregating a past year re-attributes its GPS days to `.other`; both shipped pickers reach it | [`Where/TODOs.md`](Where/TODOs.md) P1 |
| 9 | SnapshotKit | A case's content is built once and re-hosted for every configuration, while both the type's doc comment *and* its `AGENTS.md` tell authors each access is independent | [`Shared/SnapshotKit/TODOs.md`](Shared/SnapshotKit/TODOs.md) P1 |
| 10 | Bumper Bowling | `duplicate_ownership` and `declared_dependency_cycle` have no mutation test, so neither has been shown to fail on a violating tree | [`TODOs.md`](TODOs.md) P1 |

---

## Cross-cutting themes

The synthesis across items that no single item shows.

### Running the checks found what reading the code could not

Every prior edition of this report said "nothing in this report was executed". This one ran five of the `format` job's checks plus `./snapshot-shards check`, and the single new finding came out of the one that failed. It is not a subtle defect — a test asserts exit status `126` where this machine produces `127` — but no amount of reading would have produced it, because both numbers look equally plausible in source and the difference lives in bash's behaviour, not in the repo. The general shape is worth keeping: PR #283 created the repo's first CI gates that need neither Xcode nor a Swift toolchain, which means a class of check moved from "unverifiable from Linux" to "verifiable from Linux" without anyone updating the docs that said otherwise. Both the root `AGENTS.md` Linux table and the `running-tests` skill claimed Linux could run SwiftFormat and `sync-agents` and nothing else; both are corrected in this pass. The rule this suggests: when a gate stops depending on a platform, the platform-capability docs are part of the change.

### Rejecting a finding is as much of a result as filing one

Two things in the new surface looked wrong and were not. The Ranking Animation Lab reads `\.accessibilityReduceMotion` directly rather than through the shared `@MotionIsStatic` wrapper, which reads as a rule violation until you notice the rule is scoped to *continuous or looping* motion needing a static end-state, and that the lab's overtake is finite and plays only on a tap — so nothing is in motion during a capture and the capture flag has nothing to freeze. The new `LocationCardsReconciliationModifier` catches non-cancellation errors into `assertionFailure` with no log, which reads as swallowed failure until you notice that `Task.sleep` and `Task.checkCancellation` throw only `CancellationError`, making that arm the impossible-state case the repo's own rule assigns to `assertionFailure`. Both are cheap to file and expensive to un-file: a wrong item in a `TODOs.md` reads as established, and the next pass inherits it. Naming them here costs two paragraphs and saves that.

### The backlog's counted claims are unreliable in a specific, correctable way

The `SnapshotProviding` item is the sharpest case this repo has produced. It named three uncovered Settings screens and asserted they were the only ones; the tree has five, and the two it missed — `EvidenceListView` behind Settings > Attachments and `RegionsSettingsView` behind Settings > Regions — were reachable the whole time. The item survived five audits because each pass re-checked *the three it named* and found them still true, which is a different question from the one the item claims to answer. The correction is not a bigger number: it is that the item now records **how** the number was derived (list every `*View.swift` with a `#Preview` and no conformance, then intersect with `SettingsView.destination(for:)`), so the next pass re-runs a procedure instead of re-confirming a list. Elsewhere the same window found the reference count at 472 against 466 in two `AGENTS.md` bullets, Flyover's test files at 14 against 12, and `./test` at 722 lines against 941. Four of five audits have now published this theme; the difference here is that one item stopped carrying a count and started carrying a method.

### A feature team closes what a backlog reader does not

The one closure in this window came from PR #289, which set out to animate the Locations ranking and, in passing, satisfied a P2 that had sat open since July. It is the second time in three windows that the closure came from feature work landing on top of a filed item rather than from anyone working the list — the previous one was PR #187 accidentally supplying the `LocationsView` snapshot cases a matrix item had asked for. Read alongside the reverse case from two weeks ago, where a new store copied a defect filed against its sibling twenty lines away, the pattern is consistent: proximity to the code beats priority in the file. That argues for the same thing in both directions — surface the open items for the module a team is *about to work in*, because that is when they get closed and when their absence gets copied.

### Shape now travels with the thing it constrains

Three mechanisms landed this window that each pin a previously implicit assumption, and all three shipped their own enforcement rather than a note. `.xcode-build-version` pins the snapshot renderer to `27A5252f` and is checked by `./test` before it starts a simulator and again by the CircleCI runner validation. `./snapshot-shards` owns the suite-to-container assignment and *verifies after the fact* that each worker ran exactly its assignment. The retained-tool layer moved shell-embedded Python into importable modules and covered each by name. The contrast with the standing CI-docs item is stark: the one piece of shape that did **not** travel — the reasoning for keeping the snapshot suite serial inside a container — is the one that has now been missing through two migrations of the job it constrains.

---

## Per-module notes

What each module was checked for and found clean, plus the trade-offs this pass accepted as deliberate. Open work is in the linked `TODOs.md`.

### Repository tooling — dev scripts, retained Python/Ruby, CI

The busiest area of the window by a wide margin: four Scripts PRs (#283, #284, #287, #288) plus #276's shard planner. **18 root commands** now (16 at the last audit — `shellcheck` and `snapshot-shards` are new), over a retained layer of 7 Python modules and 5 Ruby modules with 22 test files under `Tools/Tests`.

**Verified OK, by running it:** `./swiftformat --lint` reports 0 of 1,116 files needing formatting; `./shellcheck` is silent across every tracked shell file; `./attribution --check` reports the report up to date at 12 credits — up from 11 because PR #283 pinned ShellCheck as a development tool *and* re-ran the generator in the same change, which is exactly the discipline the attribution rule exists to enforce. Every retained Python and Ruby module has a matching test file; spot-checking three found real fixture-shaped assertions rather than placeholders.

**New this pass:** the retained-tool gate passes only on macOS — one hardcoded shell exit status and one hermetic `PATH` that assumes a system Ruby — and running it leaves untracked `__pycache__/` directories, which `.gitignore` does not cover. Filed as one item with three halves.

**One more thing the run turned up, and it is the tidiest illustration of the cause:** `./sync-agents` is `#!/usr/bin/env ruby` and fails on a bare Linux shell with ``/usr/bin/env: 'ruby': No such file or directory``, because `.cursor/install.sh` puts mise on `PATH` but not its shims. Its sibling `./attribution` is a bash wrapper that reaches the pinned Ruby through `mise exec --` (`attribution:75-78`) and works fine. Two Ruby-implemented commands, one documented as working on Linux, and only one of them arranged to. Folded into the same filed item, which now has four halves and one root cause.

**Accepted:** `./test` is 722 lines, down from 941, having shed its report parsing and bundle selection to `Tools/`. The affected-bundle parser still infers declaration boundaries from indent level, but it is now importable and covered by name, which retires the argument the standing P2 was built on.

**Files:** 18 root commands · 7 Python / 5 Ruby retained modules · 22 tool test files · Open: [`TODOs.md`](TODOs.md)

---

### Bumper Bowling — architecture lint

Covers **Where production sources only** (`BumperBowling.swift:15-23`). CI hard-gates it through `./test --architecture-only` (`.github/workflows/ci.yml:72-73`, reaching `config`/`test`/`lint` through `test:253-261`), and the CircleCI iOS jobs pass `--skip-architecture` so it does not run twice.

**Verified OK:** all ten `where.*` rules appear in `.bumper/RULES.md`, and each has a mutation test — eleven test functions for ten rules, since `where.checked_concurrency_boundaries` gets one per escape hatch. `component_boundary` and `forbidden_import` are mutation-tested.

**Not covered, by design:** everything under `Shared/`, all of `Ledger/`, test bundles, and `Where/Specifications/`. Worth knowing when reading a green lint as a whole-repo signal.

**Files:** 4 rule/test sources · RULES.md ✓ · Open: [`TODOs.md`](TODOs.md)

---

### WhereCore

**Verified OK:** the window's one new source, `PlannedStayLocationVerifier.swift`, arrived with its namesake test, takes every argument explicitly rather than defaulting them, and models its advisory outcome as one enum rather than parallel optionals — so for the first time in four audits the namesake-test debt held flat (60 uncovered) while the module grew. No new `try?`, empty `catch`, or `Calendar.current` in the changed surface.

**Standing:** three fan-out and lifecycle items have now survived every pass since July 26 — the summary reconcile, `setPrimaryRegions`, and the hard-deleting untrack. All three were re-confirmed against current source rather than assumed, and this pass corrected two citations that had drifted by roughly 70 lines inside `SwiftDataStore` and one in `reset()`.

**Files:** 128 source / 83 test · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereUI

Again the busiest module: +16 sources across the endorsement redesign (#292), the ranking-overtake animation (#289), and the planned-stay warning (#286).

**Verified OK:** `Calendar.current` is still confined to four helper defaults and eight DEBUG fixtures, with the five `calendar.timeZone = .current` sites correctly *not* counted, and the new forecasting code holding the line (`LocationForecastProgress.swift:65` builds an explicit Gregorian calendar); no raw SF Symbol strings; production copy resolves through catalog symbols; the new accessibility work is correct rather than defective — `LocationForecastRow` composes an explicit label over ignored children, and `StampBanner`'s unlabeled `.combine` reads as one localized sentence.

**Closed:** the Locations ranking-reorder P2, by PR #289. The `matchedTransitionSource` conflict the item flagged was real and is now a written rule keeping the ranking layout out of the calendar zoom namespace.

**Corrected here:** the `SnapshotProviding` gap is five Settings-reachable screens, not three, plus ten further views with a bare `#Preview`.

**Accepted, and documented as such:** the overtake transition has no intermediate-frame coverage. A settled snapshot cannot prove a transition, so `WhereUI/AGENTS.md` prescribes playing two overtakes in the lab by hand after any ranking-motion change. That is a deliberate manual step, not a filed gap.

**Files:** 274 source / 101 test / 44 image-snapshot · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereCrashReporting

Nothing shipped this window. **Files:** 3 source / 2 test · README ✓ · AGENTS ✓ · Open: nothing filed

---

### PeriscopeCore, PeriscopeUI, PeriscopeTools

Nothing shipped. All 19 items still open, citations refreshed.

**Verified OK:** the Broadway dependency still stops at PeriscopeTools; no test touches `Periscope.shared`; the hosting-smoke debt **held at 20 tests across 10 files** for a second consecutive audit, so it has stopped growing without being worked down; `PeriscopeViewerSnapshotTests` is still the only file in the module's image bundle, at 2 references.

**Corrected here:** three citations in the span-record P0 and the relaunch P0. `StoredLogEvent` carries `spanID` and `spanExitMode` but not `spanRelaunchPolicy`, which lives only on `SDLogEvent` and the journal entry; the warning the relaunch item cited at `LogSpan.swift:643` is `end(for:)`'s "without a matching begin", not a relaunch-path warning; and the journal-ingest deletes are at `:61` and `:71`, not `:42-44`.

**Files:** PeriscopeCore 38/33 · PeriscopeUI 1/2 · PeriscopeTools 27/27 (+1 image source, 2 references) · README ✓ · AGENTS ✓ · Open: [`Shared/Periscope/TODOs.md`](Shared/Periscope/TODOs.md)

---

### Flyover

Nothing shipped, after two feature PRs in the previous window.

**Corrected here:** the standing coverage item said twelve test files; there are **fourteen**. It undercounted `FlyoverContentLoadCoordinatorTests` and `FlyoverConnectorGeometryTests`, both of which the item's own body credits by name — a count and a body disagreeing inside one bullet.

**Accepted, with a note:** references held at 5 and the single `canvasAndList` image case is unchanged, so the module's engine-proven/surface-unpinned split is stable rather than widening for a third window.

**Files:** 54 source / 14 test / 1 image source, 5 references · README ✓ · AGENTS ✓ · Open: [`Shared/Flyover/TODOs.md`](Shared/Flyover/TODOs.md)

---

### Inspector

Nothing shipped; all four items open, citations hold exactly.

**Verified OK:** the `withKnownIssue` quarantine on the dark SwiftData capture is still one of exactly **two** in the whole repo (the other guards WhereUI's Elsewhere inflection bug) — re-counted rather than assumed. The bundle still produces four references from one case.

**Files:** 23 source / 14 test / 1 image source, 4 references · README ✓ · AGENTS ✓ · Open: [`Shared/Inspector/TODOs.md`](Shared/Inspector/TODOs.md)

---

### SnapshotKit & SnapshotKitTesting

PR #290 stabilized raised-floor accessibility captures and added `AccessibilitySnapshotViewControllerTests` for the window-attachment timing; PR #297 re-recorded the suite against Xcode 27 beta 6 and introduced the `.xcode-build-version` pin.

**Verified OK:** the framework halves stay split as documented; each image bundle lists only `SnapshotKitTesting` in `extraPackageProducts`; the reporting channels still separate `report(...)`/`emit()` from `line(...)`, so no test can fabricate a row into `--review` or `--timings`; the raised-floor double-parse invariant matches the code that now implements it.

**Corrected here:** the reference count (472 — `AGENTS.md` carried 466 in two bullets, both now refreshed) and four drifted citations in the pipeline items, including `rejectsNonConvergingBoundedScrollMeasurement`, which moved by roughly 95 lines. The 37-configuration settle-floor split was re-derived and is unchanged; the item now also records where the 10-per-case and 2-per-case figures come from, so the next pass can re-derive rather than trust them.

**Files:** SnapshotKit 8/3 · SnapshotKitTesting 16/16 · README ✓ · AGENTS ✓ · Open: [`Shared/SnapshotKit/TODOs.md`](Shared/SnapshotKit/TODOs.md), [`Shared/SnapshotKitTesting/TODOs.md`](Shared/SnapshotKitTesting/TODOs.md)

---

### LifecycleKit & LifecycleKitUI

Nothing shipped. The single P2 stands, citations unchanged.

**Files:** LifecycleKit 8/10 · LifecycleKitUI 6/4 · README ✓ · AGENTS ✓ · Open: [`Shared/LifecycleKit/TODOs.md`](Shared/LifecycleKit/TODOs.md) (LifecycleKitUI's items live in LifecycleKit's file by design)

---

### Broadway (BroadwayCore, BroadwayUI, BroadwayCatalog)

Nothing shipped. All eight items still open, two citations corrected (`BStylesheets.swift:91`, and the empty catalog test bundle is listed twice in `Project.swift`).

**Files:** BroadwayCore 17/10 · BroadwayUI 6/4 · BroadwayCatalog 2/1 · README ✓ · AGENTS ✓ · Open: [`Shared/Broadway/TODOs.md`](Shared/Broadway/TODOs.md)

---

### Ledger, LedgerCore

Nothing shipped for a third consecutive window; all three P2s unchanged.

**Verified OK:** still 13 test files over 16 sources, still the three named files without a namesake test, and `Ledger-macOS-Tests` still builds the app while running only `LedgerCoreTests`. The module remains outside Bumper's scope and outside `./test`'s reach — the second of which is filed as a root P2, whose line-count evidence this pass had to revise downward twice.

**Files:** LedgerCore 16/14 · Ledger 8/0 · README ✓ · AGENTS ✓ (leaf modules; the **group** folder is missing both — filed) · Open: [`Ledger/TODOs.md`](Ledger/TODOs.md)

---

### RegionKit & RegionViewer

Nothing shipped; the doc claims PR #172 corrected remain correct.

**Files:** RegionKit 15/10 · RegionViewer 1/0 · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### WhereIntents, WhereWidgets, WhereShareExtension, Where app

Nothing shipped.

**Verified OK:** the `IntentServices` handoff still has no self-creating fallback.

**Accepted:** all four parts of the `convention(WhereIntents)` polish item are still open, verified individually rather than as a group.

**Files:** WhereIntents 15/9 · WhereWidgets 7/0 · WhereShareExtension 5/0 · Where 8/4 · README ✓ · AGENTS ✓ · Open: [`Where/TODOs.md`](Where/TODOs.md)

---

### CreditKit, JournalKit, TestHostSupport, StuffTestHost

**CreditKit:** `./attribution --check` passes at **12** credits, now including ShellCheck as a pinned development tool. **Files:** 2/3 · Open: [`Shared/CreditKit/TODOs.md`](Shared/CreditKit/TODOs.md)

**JournalKit:** nothing shipped. Both test items still open. **Files:** 2/3 · Open: [`Shared/JournalKit/TODOs.md`](Shared/JournalKit/TODOs.md)

**TestHostSupport:** dependency-free UIKit helpers, no bundle by design. **Files:** 1/0 · nothing open

**StuffTestHost:** unchanged. **Files:** 2/0 · nothing open

---

## Limitations

- **Mostly static, but no longer entirely.** The cloud agent runs Linux with no Swift toolchain, so no `tuist test`, no simulator, no `./test --architecture-only`, and no `./xcstrings --lint`. What *was* executed for this report: `./swiftformat --lint`, `./shellcheck`, `./attribution --check`, the retained Python tool tests, the retained Ruby tool tests, and `./snapshot-shards check`. Everything else here is read from source.
- **The two retained-tool failures this pass observed are the finding, not noise.** The Python suite failed one of 64 tests, and the Ruby suite reported 12 failures and one error across 75 runs, in both cases on macOS assumptions rather than on the commands under test. Both are filed; neither indicates a broken command.
- **The "the Gregorian rule finds nothing" conclusion rests on CI being green**, not on running the lint here. The mechanism (the rule's filter plus its one-sided mutation test) is read from source and is sufficient on its own; the green gate is corroboration.
- **No snapshot pixels were inspected.** Reference counts come from file enumeration and Git LFS pointers, never from decoded images. Whether PR #297's re-recording against Xcode 27 beta 6 preserved or re-baked any of the four open broken-snapshot defects is unanswerable here; a macOS `./test --review` would settle it.
- **Runtime-dependent items are unconfirmed by design**: the launch-time notification prompt, Flyover's log routing, multi-process journal coordination, the CloudKit import-readiness race, Spotlight indexing, whether Bitdrift receives anything on a device, and Ledger's live API and Keychain paths. Each says so in its own entry.
- **The new-surface review was a rule-by-rule read, not a proof.** The window's 17 net new Swift sources were checked against the repo's written rules one by one; the ranking-overtake transition in particular cannot be verified without running it, which is what `WhereUI/AGENTS.md` says to do by hand.
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
| WhereUI | `Where/WhereUI/` | 274 | 101 | 44 | ✓ | ✓ |
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

**Totals:** 694 source · 368 test · 47 image-snapshot Swift files across shipped targets (plus 4 Bumper rule/test sources and 2 unwired prototype sources). **472** LFS-backed reference images (461 WhereUI, 5 Flyover, 4 Inspector, 2 PeriscopeTools) across **47** snapshot suites. **26** test bundles: 22 unit (21 in `Stuff-iOS-Tests`, plus `LedgerCoreTests` in `Ledger-macOS-Tests`) and 4 image (`StuffSnapshotTests`) — every one is a member of a CI scheme.

**Group-folder docs:** every one of the 28 module folders above carries its `README.md` + `AGENTS.md` pair. At the *group* level, `Shared/Broadway/` and `Shared/Periscope/` carry the required pair; `Where/` has `AGENTS.md` but **no `README.md`**, and `Ledger/` has **neither** — both filed in the root [`TODOs.md`](TODOs.md).

---

## Changes since August 16, 2026 audit

| Area | August 16 state | August 30 state |
|------|-----------------|-----------------|
| File count | 677 source / 361 test | **694 / 368** (WhereUI 258 → 274, WhereCore 127 → 128) |
| Backlog movement | 0 closed, 5 filed | **2 closed, 1 filed** — #289 closed the Locations ranking-reorder P2; #300 closed the StuffCore tautological-test P2 by removing the module; one new item covers four macOS-coupled edges in the retained-tool layer |
| Dev scripts | 16 | **18** — `shellcheck` (#283) and `snapshot-shards` (#276) |
| CI `format` job | 4 checking steps | **6** — ShellCheck and the retained Python/Ruby tool suites joined (#283) |
| CI iOS topology | One `test-ios` job, one serial `snapshot` job | **Build once, attach everywhere** — `build-ios-tests` hands products to `test-ios` and a `parallelism: 4` `snapshot` job sharded by suite (#276) |
| Snapshot renderer | Unpinned | **`.xcode-build-version` = `27A5252f`** (#297), gated in `test:449-452` and validated on the CircleCI runner |
| CI opt-out | None | **`NO-CI` in a PR title** skips both systems; main pushes and manual full-gate runs are unaffected (#294) |
| Retained tooling | Report policy and bundle selection embedded in `./test` (941 lines) | **7 Python + 5 Ruby modules, 22 test files** under `Tools/`; `./test` down to **722** lines (#283/#284/#287/#288) |
| Image suites | 4 bundles, 466 references | **4 bundles, 472 references, 47 suites** — WhereUI 455 → 461, re-recorded whole for Xcode 27 beta 6 (#297) |
| Attribution | 11 credits | **12** — ShellCheck, pinned and credited in the same PR that added it |
| Formal specs | 10 TLA+ specifications | **10**, unchanged |
| Test bundles | 26 | **26**, unchanged |
| Backlog | 13 `TODOs.md` | **12** — StuffCore's area file went with the module (#300); no new area needed one |
