# Swift Module Audit Report

**Date:** November 16, 2026 (America/New_York)
**Reviewed source:** `6676b36bcd7a6dac1d0f7c72784b1d44b7c7f742` (PR #505), fetched from `origin/main`.
**Prior audit:** November 9, 2026, source `bbe90c4c58d9d458382335418a18a5dccb434e87`, report merged in [PR #488](https://github.com/kyleve/Stuff/pull/488).

[Linear’s Stuff team](https://linear.app/kve/team/STU/all) owns actionable work under [BACKLOG.md](BACKLOG.md).
This report records bounded verification and inventory, not a second backlog.

## Access, scope, and reconciliation

The pinned Linear CLI verified workspace `kve` and team `STU`.
The all-assignee/all-state list and paginated API query with `includeArchived: true` each returned 330 issues.
The API included descriptions and comments; no returned comment connection had another page.
Initial states were 150 Backlog, 14 In Review, and 166 Done. Triage had no submissions.
No unfinished matching audit PR was open. This pass used an isolated worktree from current main.

All 164 open records were screened against the change window by cited filenames and area.
Source checks concentrated on changed evidence, merge status, coverage policy, and selected persistent defects.
This is a static maintenance pass, not a fresh line-by-line review of every implementation or a runtime re-verification of every issue.
Unchanged source supports retaining earlier findings but does not renew their runtime evidence dates.
Completed and archived history was retrieved before reconciliation; no new issue was filed.

Linear changes preserve human priorities, labels, original descriptions, and attribution dates:

- [STU-332](https://linear.app/kve/issue/STU-332) is Done after PR #505 merged on November 16 at 01:30:07 UTC. Published lint, tools, web, architecture, macOS, iOS, audience, and snapshot checks passed. Comparison with its parent confirms 65 deleted PNGs and no changed retained PNGs. This closes the accepted maintenance reduction, not any renderer defect.
- [STU-114](https://linear.app/kve/issue/STU-114) now distinguishes the provider’s per-configuration builder from remaining externally captured references and the prebuilt inline overload.
- [STU-243](https://linear.app/kve/issue/STU-243) carries the current catalog inventory; [STU-241](https://linear.app/kve/issue/STU-241) points to the calendar literal’s new file.
- [STU-7](https://linear.app/kve/issue/STU-7) and [STU-236](https://linear.app/kve/issue/STU-236) now require assessment of distinct behavior gaps under the merged coverage policy, rather than adding tests for missing filenames.
- STU-316 through STU-328 carry corrected implementation history: #466 closed without merge after absorption into #377 and #372; #377, #378, and #372 have merged. These 13 issues retain their states and acceptance requirements because this pass did not repeat visual, interaction, or native-device verification. [STU-316](https://linear.app/kve/issue/STU-316) owns native release validation; [STU-325](https://linear.app/kve/issue/STU-325) retains the tall annotation defect.

Totals: **0 created, 18 corrected without closure, 1 closed**. Verified final distribution is 150 Backlog, 13 In Review, 167 Done.

## Area findings

| Area | Bounded result and Linear findings |
|---|---|
| Repository and tools | Gregorian implicit-member enforcement remains outside the explicit-base rule ([STU-133](https://linear.app/kve/issue/STU-133)). Atlas publication implementation is unchanged ([STU-134](https://linear.app/kve/issue/STU-134), [STU-135](https://linear.app/kve/issue/STU-135)). Where still lacks its group README ([STU-143](https://linear.app/kve/issue/STU-143)). |
| WhereCore and extensions | Swift source/tests are unchanged. Local summary fan-out, picker reconciliation, raw-GPS attribution, and widget error distinctions retain prior evidence ([STU-178](https://linear.app/kve/issue/STU-178), [STU-188](https://linear.app/kve/issue/STU-188), [STU-189](https://linear.app/kve/issue/STU-189), [STU-226](https://linear.app/kve/issue/STU-226)). |
| WhereUI | Adaptive layout and developer lab work shipped. Old UI line numbers and coverage counts are historical. Native release checks, Manual Day range coverage, and calendar behavior remain open ([STU-316](https://linear.app/kve/issue/STU-316), [STU-194](https://linear.app/kve/issue/STU-194), [STU-187](https://linear.app/kve/issue/STU-187)). The catalog has 1,033 keys, 830 without comments. |
| Broadway | Size-class propagation and scroll restoration shipped; they do not implement catalog content, cache eviction, or observer ownership ([STU-8](https://linear.app/kve/issue/STU-8), [STU-6](https://linear.app/kve/issue/STU-6), [STU-4](https://linear.app/kve/issue/STU-4)). Blanket namesake-test advice was corrected in STU-7. |
| CreditKit | The permissive `github_slug` expression remains in unchanged generator code ([STU-9](https://linear.app/kve/issue/STU-9)). |
| Flyover | Native preview churn work shipped. The export error, web shortcut, group identity, and drawer findings concern separate paths ([STU-10](https://linear.app/kve/issue/STU-10), [STU-11](https://linear.app/kve/issue/STU-11), [STU-12](https://linear.app/kve/issue/STU-12), [STU-13](https://linear.app/kve/issue/STU-13)). No browser reproduction was repeated. |
| Inspector | Three references remain after deletion of the intermittent dark capture. Deletion does not fix the renderer ([STU-20](https://linear.app/kve/issue/STU-20)); reflection and fetch source remain unchanged. |
| JournalKit and LifecycleKit | Concurrent append still discards original append errors; source count/ordering assertions remain. No new durability or duplicate-ID trap evidence was produced ([STU-25](https://linear.app/kve/issue/STU-25), [STU-26](https://linear.app/kve/issue/STU-26), [STU-27](https://linear.app/kve/issue/STU-27)). |
| Periscope | Primary-scope hierarchy counts remain explicit. Modeling, pre-attach journaling, and resume requirements remain; the prior blanket mount-test prescription was already narrowed in [STU-49](https://linear.app/kve/issue/STU-49). [STU-37](https://linear.app/kve/issue/STU-37) retains durability scope. |
| SnapshotKit / SnapshotKitTesting | Provider construction changed, so STU-114 was refined. Accessibility parse catches still trap, and inline duplicate identities remain separate requirements ([STU-115](https://linear.app/kve/issue/STU-115), [STU-125](https://linear.app/kve/issue/STU-125)). Native geometry and tiled annotations retain separate acceptance gates. |

## Changes since the prior audit

The source window contains 21 merged PRs. GitHub merge dates were checked separately from local commit dates.

| PRs | Changes screened and implications |
|---|---|
| #487, #488, #489 | Review guidance, prior audit, and snapshot shard rebalance. Current shard inventory is checked below. |
| #490, #486 | Workstation bootstrap and removal of redundant CI/setup/PNG encoding. Old timing claims remain historical; this pass made no new performance measurement. |
| #491, #492 | Linear migration and removal of migration execution tools. Historical receipt remains; Markdown backlogs are no longer live state. |
| #376, #377, #378, #372 | Size classes, measured capture geometry, scroll restoration, and adaptive Where UI. Updated stale Linear implementation history; preserved unverified acceptance. |
| #494 | Flyover preview churn changes. Separate web interaction and error-preservation requirements remain. |
| #483, #498, #502, #499, #507 | Durable planning and guidance discovery, validation, and simplification. Current instruction-chain validation passed. |
| #496, #504 | Device Layout Lab and its dark-mode fix. No new native-device claim follows from a synthetic preview. |
| #503 | Astro prototype command. All 21 focused command tests passed. |
| #505 | Test and image-matrix reduction. Confirmed deletion-only PNG changes and merged acceptance; closed STU-332. |

Open #506 and the Mobius PRs #497/#500 remain unmerged and are not shipped evidence.
No independent new defect was established in this screening. This is not a complete code review of the 1,060-file historical diff.
No module API or instruction changes are made by this report.

## Module inventory and verified-clean scope

Tracked Swift files are counted under each documented leaf’s `Sources`, `Tests`, and `SnapshotTests` directories.
Counts include support files, not executed tests. The unwired journal benchmark and tool implementation files are outside leaf totals.
Every listed module has README and AGENTS documents.
“Unchanged” below means source/test Swift object contents match the prior cutoff; image references and documentation may differ.
It establishes no new runtime result and does not mean the module has no open findings.

| Module | Source | Test/support | Image suite | Source/test comparison |
|---|---:|---:|---:|---|
| [BroadwayCatalog](Shared/Broadway/BroadwayCatalog/README.md) | 2 | 1 | 0 | Unchanged |
| [BroadwayCore](Shared/Broadway/BroadwayCore/README.md) | 21 | 15 | 0 | Changed; bounded screening only |
| [BroadwayUI](Shared/Broadway/BroadwayUI/README.md) | 9 | 5 | 0 | Changed; bounded screening only |
| [CreditKit](Shared/CreditKit/README.md) | 2 | 3 | 0 | Unchanged |
| [Flyover](Shared/Flyover/README.md) | 66 | 21 | 1 | Changed; bounded screening only |
| [Inspector](Shared/Inspector/README.md) | 23 | 14 | 1 | Unchanged |
| [InstallerKit](Shared/InstallerKit/README.md) | 10 | 11 | 0 | Unchanged |
| [InstallerKitUI](Shared/InstallerKitUI/README.md) | 27 | 8 | 5 | Changed; bounded screening only |
| [JournalKit](Shared/JournalKit/README.md) | 2 | 3 | 0 | Unchanged |
| [LifecycleKit](Shared/LifecycleKit/README.md) | 8 | 10 | 0 | Changed; bounded screening only |
| [LifecycleKitUI](Shared/LifecycleKitUI/README.md) | 6 | 4 | 0 | Unchanged |
| [PeriscopeCore](Shared/Periscope/PeriscopeCore/README.md) | 53 | 49 | 0 | Changed; bounded screening only |
| [PeriscopeMacros](Shared/Periscope/PeriscopeMacros/README.md) | 6 | 4 | 0 | Unchanged |
| [PeriscopeTools](Shared/Periscope/PeriscopeTools/README.md) | 27 | 26 | 1 | Changed; bounded screening only |
| [PeriscopeUI](Shared/Periscope/PeriscopeUI/README.md) | 1 | 2 | 0 | Unchanged |
| [SnapshotKit](Shared/SnapshotKit/README.md) | 17 | 13 | 0 | Changed; bounded screening only |
| [SnapshotKitTesting](Shared/SnapshotKitTesting/README.md) | 31 | 33 | 0 | Changed; bounded screening only |
| [StuffTestHost](Shared/StuffTestHost/README.md) | 2 | 0 | 0 | Changed; bounded screening only |
| [TestHostSupport](Shared/TestHostSupport/README.md) | 1 | 0 | 0 | Changed; bounded screening only |
| [RegionKit](Where/RegionKit/README.md) | 15 | 10 | 0 | Unchanged |
| [RegionViewer](Where/RegionViewer/README.md) | 1 | 0 | 0 | Unchanged |
| [Where](Where/Where/README.md) | 9 | 5 | 0 | Unchanged |
| [WhereCore](Where/WhereCore/README.md) | 169 | 126 | 0 | Unchanged |
| [WhereCrashReporting](Where/WhereCrashReporting/README.md) | 3 | 2 | 0 | Unchanged |
| [WhereIntents](Where/WhereIntents/README.md) | 15 | 9 | 0 | Unchanged |
| [WhereShareExtension](Where/WhereShareExtension/README.md) | 6 | 0 | 0 | Unchanged |
| [WhereUI](Where/WhereUI/README.md) | 375 | 158 | 62 | Changed; bounded screening only |
| [WhereWidgets](Where/WhereWidgets/README.md) | 8 | 0 | 0 | Unchanged |

**Totals:** 28 leaf modules, 915 source files, 532 test/support files, and 70 leaf image-suite files. Tools adds one image suite.
The prior audit counted 890 / 514 / 69 respectively.

There are **893 snapshot reference PNGs**: WhereUI 756, InstallerKitUI 103, Tools 24, Flyover 5, Inspector 3, PeriscopeTools 2.
The prior audit had 885. Reference counts are not capture counts because comparison sheets contain panels.
The shard plan validates 71 suites: **11 / 19 / 15 / 25**, plus **1 intake suite**.

## Cross-cutting themes

- Merged implementation, accepted visual output, and native-device validation are separate evidence.
- Repeated builders cannot isolate reference objects captured outside them.
- Coverage should guard behavior and visual risk; filename parity is not coverage.
- Removing a flaky reference does not establish a renderer repair.
- Inventory and phase timings describe their recorded revisions, not future source.

## Checks and limits

Host: macOS, Xcode 27.2 (27B52). The repository diff is documentation only.

- `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=Tools/Tests python3 -m unittest test_ci_changes test_ci_circleci test_ci_workflows test_circleci_pipeline test_snapshot_shards test_test_runner`: **91 passed**.
- `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=Tools/Tests python3 -m unittest test_prototype`: **21 passed**, after allowing the loopback-port fixture outside the sandbox.
- `./snapshot-shards check`: passed, with the inventory above.
- `mise exec -- ./sync-agents --check`: passed, 57 instruction files and 13 owned skills. External skills are absent in this checkout, so their layout checks were skipped.
- Recounted tracked files, snapshot references, and catalog comments; compared retained PNG object identities for #505.
- Local report links, complete report diff, and `git diff --check` checked before publication.

An initial test command misspelled the workflow module; the corrected selection passed.
Bare `./sync-agents --check` used the host’s older Ruby and failed on `filter_map`; the pinned Ruby invocation passed.
These were invocation/environment failures, not passing checks.

`./test`, architecture execution, SwiftFormat, simulator captures, browser flows, physical devices, and VoiceOver were not run for this documentation-only change.
The #505 closure uses its merged source and dated published validation; this run does not claim to have repeated that runtime evidence.
Visual, CloudKit, distribution, Linux portability, billing, and performance acceptance remain unverified here.
There is no Linear access blocker. Runtime requirements remain open in their owning issues.
