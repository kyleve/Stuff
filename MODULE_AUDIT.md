# Swift Module Audit Report

**Date:** November 23, 2026 (America/New_York)
**Reviewed source:** `acdae322d90287f1a0bd26319053102c9d4a9cd5`, fetched from `origin/main`.
**Prior audit:** November 16, 2026, source `6676b36bcd7a6dac1d0f7c72784b1d44b7c7f742`, report merged in [PR #508](https://github.com/kyleve/Stuff/pull/508).

[Linear’s Stuff team](https://linear.app/kve/team/STU/all) owns actionable work under [BACKLOG.md](BACKLOG.md).
This report records bounded verification and inventory, not a second backlog.

## Access and coverage

The pinned Linear CLI authenticated workspace `kve` and team `STU`.
The all-assignee/all-state list and paginated API with archived issues both returned **346 issues**.
Descriptions and comments were retrieved; no comment connection had another page.
Initial states were 151 Backlog, 21 In Review, 3 Todo, and 171 Done. There were no Triage submissions.
No unfinished matching audit PR was open; this pass used an isolated worktree from current main.

All 175 open records were screened by area and cited filenames against the change window.
Detailed source checks focused on merged acceptance, changed WebKit and selector evidence, journal batching, fixture clocks, and catalog counts.
Filename screening is conservative and is not a fresh verification of every acceptance condition.
Unchanged source retains prior evidence; it does not renew runtime verification dates.
Completed and archived descriptions were available for duplicate searches. No new issue was established or filed.

## Linear reconciliation

Human priorities, labels, original descriptions, and attribution dates were preserved.
Audit evidence was appended after reading each current issue and the saved results were inspected.

- Closed [STU-203](https://linear.app/kve/issue/STU-203): PR #549 merged November 20. The generation-scoped transaction retains ordered overlays, individual audits, rollback, and final widget publication. Its dated record reports 96 selected tests passing.
- Closed [STU-339](https://linear.app/kve/issue/STU-339): PR #552 merged November 20. Immediate geometry capture retains all twelve inset/attachment/size-class combinations and teardown assertions. Its record reports five rendering tests passing, including adjacent settled native-bar coverage.
- Closed [STU-340](https://linear.app/kve/issue/STU-340): PR #553 merged November 20. Eleven date-independent cases use the injected January clock; report-content coverage remains. Its record reports 41 tests passing.
- Refined [STU-122](https://linear.app/kve/issue/STU-122): merged #559 adds call-scoped WebKit reuse. Fresh-view acceptance and runtime isolation/readiness still need reconciliation.
- Refined [STU-147](https://linear.app/kve/issue/STU-147): merged #555 replaces the old selection implementation. The Tuist decision remains open; registered-artwork selection is already [STU-345](https://linear.app/kve/issue/STU-345).
- Refreshed [STU-243](https://linear.app/kve/issue/STU-243) with current catalog counts.
- Corrected merged history in [STU-338](https://linear.app/kve/issue/STU-338), [STU-331](https://linear.app/kve/issue/STU-331), [STU-333](https://linear.app/kve/issue/STU-333), and [STU-334](https://linear.app/kve/issue/STU-334). Visual, interaction, and physical-device requirements remain open.

Totals: **0 created, 7 materially updated without closure, 3 closed**.
Final distribution: **151 Backlog, 18 In Review, 3 Todo, 174 Done**.

## Area findings and verified-clean scope

| Area | Bounded result |
|---|---|
| Repository and tools | Selector and publication changes shipped. The focused 121-test host selection passes. Registered artwork remains tracked in STU-345; Tuist replacement remains STU-147. No new distribution/runtime claim follows from those host checks. |
| WhereCore and extensions | Demo batching acceptance is complete in STU-203. Whole-scope compatibility is distinct from per-entity upcasting ([STU-206](https://linear.app/kve/issue/STU-206), [STU-208](https://linear.app/kve/issue/STU-208)). Physical account and extension delivery acceptance remains open. The module contract still identifies summary fan-out and primary-region reconciliation gaps ([STU-178](https://linear.app/kve/issue/STU-178), [STU-188](https://linear.app/kve/issue/STU-188)). |
| WhereUI | Shared screen roots and Calendar optimization merged. This audit did not inspect rendered images or exercise resizing, scrolling, or native Duo behavior. Their acceptance remains open. Catalog counts are refreshed in STU-243. |
| SnapshotKit / SnapshotKitTesting | Preparation, measurement, capture reuse, and annotation changes shipped. Native safe-area test acceptance is closed. WebKit reuse evidence is updated in STU-122. Panel timing still emits before sheet composition in AssertComparisonSnapshots ([STU-123](https://linear.app/kve/issue/STU-123)). |
| Broadway and CreditKit | Source/test Swift contents are unchanged. Existing catalog, observer/cache, and slug findings retain earlier evidence ([STU-8](https://linear.app/kve/issue/STU-8), [STU-4](https://linear.app/kve/issue/STU-4), [STU-6](https://linear.app/kve/issue/STU-6), [STU-9](https://linear.app/kve/issue/STU-9)). |
| Flyover and InstallerKitUI | Capture preparation and accessibility reference changes do not establish fixes for Flyover browser interactions or error propagation ([STU-10](https://linear.app/kve/issue/STU-10), [STU-13](https://linear.app/kve/issue/STU-13)). No browser reproduction was repeated. |
| Inspector | Image-suite configuration changed. Reflection and fetch requirements remain; no renderer closure is inferred ([STU-20](https://linear.app/kve/issue/STU-20), [STU-23](https://linear.app/kve/issue/STU-23)). |
| JournalKit and LifecycleKit | Source/test Swift contents are unchanged. Durability and duplicate-node requirements remain ([STU-26](https://linear.app/kve/issue/STU-26), [STU-27](https://linear.app/kve/issue/STU-27)). |
| Periscope | Test support and capture configuration changed. No new evidence establishes pre-attach durability, multi-process coordination, or resume mechanics ([STU-37](https://linear.app/kve/issue/STU-37), [STU-39](https://linear.app/kve/issue/STU-39), [STU-36](https://linear.app/kve/issue/STU-36)). |

“Verified clean” is limited to the executed host checks, report links, inventory, and unchanged-source comparisons.
It does not mean these areas have no open defects.

## Changes since the prior audit

The November 16 cutoff to this source contains the following 34 merged PRs.
Merge dates were checked through GitHub; unmerged work is excluded.
Screening covered change scope and related backlog evidence, not a complete review of the 723-file historical diff.

| PR | Change screened | Merge date (UTC) |
|---|---|---|
| [#506](https://github.com/kyleve/Stuff/pull/506) | feat(WhereUI): center screen content with shared roots | 2026-11-16 |
| [#508](https://github.com/kyleve/Stuff/pull/508) | docs: refresh November 16 Linear backlog audit | 2026-11-16 |
| [#510](https://github.com/kyleve/Stuff/pull/510) | docs(review): probe retries after partial skill updates | 2026-11-16 |
| [#509](https://github.com/kyleve/Stuff/pull/509) | chore(ci): rebalance snapshot shards from current timings | 2026-11-16 |
| [#511](https://github.com/kyleve/Stuff/pull/511) | perf(snapshots): prepare fixtures before settling captures | 2026-11-17 |
| [#512](https://github.com/kyleve/Stuff/pull/512) | perf(snapshots): reduce fixture measurement and settling | 2026-11-17 |
| [#514](https://github.com/kyleve/Stuff/pull/514) | perf(WhereUI): shorten adaptive snapshot settling | 2026-11-17 |
| [#515](https://github.com/kyleve/Stuff/pull/515) | perf(snapshots): share outline paths and prepare artwork earlier | 2026-11-17 |
| [#516](https://github.com/kyleve/Stuff/pull/516) | perf(snapshots): reuse fixed report fixtures | 2026-11-17 |
| [#517](https://github.com/kyleve/Stuff/pull/517) | perf(snapshots): share demo world initialization | 2026-11-17 |
| [#518](https://github.com/kyleve/Stuff/pull/518) | perf(snapshots): await mounted calendar content before measuring | 2026-11-17 |
| [#520](https://github.com/kyleve/Stuff/pull/520) | perf(snapshots): avoid repeated settling in Elsewhere and MainTabs | 2026-11-17 |
| [#521](https://github.com/kyleve/Stuff/pull/521) | test(snapshots): remove RTL coverage and focus calendar captures | 2026-11-17 |
| [#523](https://github.com/kyleve/Stuff/pull/523) | chore(ci): rebalance snapshot shards after capture optimizations | 2026-11-17 |
| [#535](https://github.com/kyleve/Stuff/pull/535) | perf(snapshots): land independent snapshot and CI improvements | 2026-11-18 |
| [#537](https://github.com/kyleve/Stuff/pull/537) | fix(WhereCore): recheck remote history when the observed counter repeats | 2026-11-18 |
| [#495](https://github.com/kyleve/Stuff/pull/495) | feat(Where): gate synced history by data compatibility version | 2026-11-18 |
| [#539](https://github.com/kyleve/Stuff/pull/539) | chore(snapshots): update testing libraries and accessibility annotations | 2026-11-18 |
| [#541](https://github.com/kyleve/Stuff/pull/541) | perf(snapshots): capture 478 verified images on a single native mount | 2026-11-20 |
| [#542](https://github.com/kyleve/Stuff/pull/542) | perf(ci): run snapshots on three active shards | 2026-11-20 |
| [#543](https://github.com/kyleve/Stuff/pull/543) | perf(ci): reuse full PR validation on identical main merges | 2026-11-20 |
| [#544](https://github.com/kyleve/Stuff/pull/544) | fix(ci): retry missing PR evidence after auto-merge | 2026-11-20 |
| [#546](https://github.com/kyleve/Stuff/pull/546) | perf(ci): skip verified Markdown merges and build Where audiences daily | 2026-11-20 |
| [#549](https://github.com/kyleve/Stuff/pull/549) | perf(WhereCore): publish the completed demo dataset once | 2026-11-20 |
| [#548](https://github.com/kyleve/Stuff/pull/548) | perf(WhereUI): reduce Calendar zoom layout work | 2026-11-20 |
| [#550](https://github.com/kyleve/Stuff/pull/550) | fix(ci): skip superseded main installer archives | 2026-11-20 |
| [#552](https://github.com/kyleve/Stuff/pull/552) | perf(tests): capture native child safe areas after layout | 2026-11-20 |
| [#553](https://github.com/kyleve/Stuff/pull/553) | perf(tests): seed demo lifecycle tests in early January | 2026-11-20 |
| [#554](https://github.com/kyleve/Stuff/pull/554) | perf(tests): share library test hosts during full iOS validation | 2026-11-21 |
| [#555](https://github.com/kyleve/Stuff/pull/555) | fix(test): select affected bundles safely and preview skipped tests | 2026-11-22 |
| [#557](https://github.com/kyleve/Stuff/pull/557) | perf(ci): cache the installer snapshot fixture | 2026-11-22 |
| [#558](https://github.com/kyleve/Stuff/pull/558) | perf(ci): reuse the unit simulator for snapshot inventory | 2026-11-22 |
| [#559](https://github.com/kyleve/Stuff/pull/559) | perf(snapshots): reuse one web view for installer pages | 2026-11-22 |
| [#551](https://github.com/kyleve/Stuff/pull/551) | fix(pages): deploy completed site artifacts and skip stale retries | 2026-11-22 |

No module API or instruction changes are made by this report.

## Module inventory

Counts cover tracked Swift files in each documented leaf’s Sources, Tests, and SnapshotTests directories.
Test/support counts are files, not executed tests.
Every listed leaf has README and AGENTS documents.
“Unchanged” compares those Swift contents with the prior source cutoff; images and documentation can differ.

| Module | Source | Test/support | Image suite | Source/test comparison |
|---|---:|---:|---:|---|
| [BroadwayCatalog](Shared/Broadway/BroadwayCatalog/README.md) | 2 | 1 | 0 | Unchanged |
| [BroadwayCore](Shared/Broadway/BroadwayCore/README.md) | 21 | 15 | 0 | Unchanged |
| [BroadwayUI](Shared/Broadway/BroadwayUI/README.md) | 9 | 5 | 0 | Unchanged |
| [CreditKit](Shared/CreditKit/README.md) | 2 | 3 | 0 | Unchanged |
| [Flyover](Shared/Flyover/README.md) | 66 | 21 | 1 | Changed; bounded screening |
| [Inspector](Shared/Inspector/README.md) | 23 | 14 | 1 | Changed; bounded screening |
| [InstallerKit](Shared/InstallerKit/README.md) | 10 | 11 | 0 | Unchanged |
| [InstallerKitUI](Shared/InstallerKitUI/README.md) | 27 | 8 | 5 | Changed; bounded screening |
| [JournalKit](Shared/JournalKit/README.md) | 2 | 3 | 0 | Unchanged |
| [LifecycleKit](Shared/LifecycleKit/README.md) | 8 | 10 | 0 | Unchanged |
| [LifecycleKitUI](Shared/LifecycleKitUI/README.md) | 6 | 4 | 0 | Unchanged |
| [PeriscopeCore](Shared/Periscope/PeriscopeCore/README.md) | 53 | 49 | 0 | Changed; bounded screening |
| [PeriscopeMacros](Shared/Periscope/PeriscopeMacros/README.md) | 6 | 4 | 0 | Unchanged |
| [PeriscopeTools](Shared/Periscope/PeriscopeTools/README.md) | 27 | 26 | 1 | Changed; bounded screening |
| [PeriscopeUI](Shared/Periscope/PeriscopeUI/README.md) | 1 | 2 | 0 | Unchanged |
| [SnapshotKit](Shared/SnapshotKit/README.md) | 17 | 13 | 0 | Changed; bounded screening |
| [SnapshotKitTesting](Shared/SnapshotKitTesting/README.md) | 33 | 35 | 0 | Changed; bounded screening |
| [StuffTestHost](Shared/StuffTestHost/README.md) | 2 | 0 | 0 | Unchanged |
| [TestHostSupport](Shared/TestHostSupport/README.md) | 1 | 0 | 0 | Unchanged |
| [RegionKit](Where/RegionKit/README.md) | 15 | 10 | 0 | Unchanged |
| [RegionViewer](Where/RegionViewer/README.md) | 1 | 0 | 0 | Unchanged |
| [Where](Where/Where/README.md) | 9 | 6 | 0 | Changed; bounded screening |
| [WhereCore](Where/WhereCore/README.md) | 186 | 134 | 0 | Changed; bounded screening |
| [WhereCrashReporting](Where/WhereCrashReporting/README.md) | 3 | 2 | 0 | Unchanged |
| [WhereIntents](Where/WhereIntents/README.md) | 15 | 9 | 0 | Changed; bounded screening |
| [WhereShareExtension](Where/WhereShareExtension/README.md) | 6 | 0 | 0 | Changed; bounded screening |
| [WhereUI](Where/WhereUI/README.md) | 393 | 169 | 64 | Changed; bounded screening |
| [WhereWidgets](Where/WhereWidgets/README.md) | 8 | 0 | 0 | Changed; bounded screening |

**Totals:** 28 leaf modules, 952 source files, 554 test/support files, and 72 leaf image-suite files.
The prior audit counted 915 / 532 / 70 respectively. Tools adds one image suite.
There are **902 snapshot PNGs**: Flyover 5, Inspector 3, InstallerKitUI 103, PeriscopeTools 2, Tools 24, WhereUI 765.
These are reference files, not capture counts.
The shard plan validates **73 suites**, distributed **25 / 24 / 24**, with zero intake suites.

## Cross-cutting themes

- Merged source, rendered correctness, and physical-device behavior require separate evidence.
- Performance results apply to their measured revisions and environments.
- Reuse boundaries require isolation and readiness evidence.
- Test selection and fixture caching have separate input contracts.
- Earlier issue descriptions remain historical; appended audit notes identify changed evidence.

## Checks and limits

Host: macOS, Xcode 27.2 (27B52). The repository diff is documentation only.

- `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=Tools/Tests python3 -m unittest test_ci_changes test_ci_circleci test_ci_workflows test_circleci_pipeline test_snapshot_shards test_test_runner test_test_selection`: **121 passed**.
- `./snapshot-shards check`: passed, 73 suites across three active shards.
- `mise exec -- ./sync-agents --check`: passed, 57 instruction files and 13 owned skills. Absent external skills and Claude links were allowed and their layout checks skipped.
- Tracked inventory, local report links, complete report diff, and `git diff --check` checked before publication.
- Closure PRs #549, #552, and #553 have successful published lint, tool, web, architecture, macOS, iOS, and snapshot checks. Dated execution records supply the runtime evidence; this audit did not repeat those runs.

`./test`, architecture execution, SwiftFormat, simulator captures, browser flows, physical devices, VoiceOver, CloudKit transitions, and performance measurements were not run for this documentation-only change.
There is no Linear access blocker. The audit cannot establish the remaining runtime acceptance conditions.
Dependency installation reported 16 npm advisories (12 moderate, 4 high); their applicability was not investigated and no package changes were made.
