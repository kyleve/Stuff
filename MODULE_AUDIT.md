# Swift Module Audit Report

**Date:** November 9, 2026 (America/New_York)
**Reviewed source:** `bbe90c4c58d9d458382335418a18a5dccb434e87` (PR #485), fetched from `origin/main`.
**Prior audit:** November 4, 2026, source cutoff `a22b6095254d391cb70a2dbed61943647ecbdeab`, report merged in PR #479 on November 6.

This report was verified against 11 Markdown backlog files at its header date. It carries no actionable items.
[BACKLOG.md](BACKLOG.md) now owns the Linear workflow. Links below were migrated without changing this report’s verification date.
The report describes the header date and reviewed source, not later HEADs.

## Method and backlog reconciliation

The pass read the open area backlogs, checked cited source locations, and compared implementations and tests with the previous cutoff.
All Swift source, tests, manifests, and reference images are unchanged in this window.
Those unchanged blobs support retaining prior findings; this was not a fresh review of every source line.
Runtime, visual, and design acceptance requirements remain open.
Existing priorities, human origins, and completed history remain intact.

At this audit’s date, the former Markdown inbox had no open notes. Nothing required promotion or a decline verdict.
No implementation item met its full closure condition. No new independent defect was established.
The previous triage PR #479 merged on November 6; no unfinished matching triage PR existed at branch creation.

| Backlog | Result of this pass |
|---|---|
| [Root](https://linear.app/kve/view/df229f7aa2f4) | Corrected architecture/tool-job citations and LFS hydration ownership after the CI split. Retained publication races, parser, portability, calendar, distribution, and documentation requirements. |
| [Where](https://linear.app/kve/view/1cdf347a9c54) | Source locations and unchanged implementation support retaining reconciliation, attribution, recording, localization, test, performance, and visual requirements. |
| [Broadway](https://linear.app/kve/view/44ec91d450b2) | Placeholder app/test, missing root, unconditional observer, invalidation, and cache gaps remain in unchanged source. |
| [CreditKit](https://linear.app/kve/view/835453b822e9) | The permissive GitHub-slug expression remains at lines 97–98. |
| [Flyover](https://linear.app/kve/view/2292471484f2) | Web and native sources are unchanged. Shortcut, group-filter, drawer, error-preservation, and native interaction findings remain open. |
| [Inspector](https://linear.app/kve/view/83c3c45cf416) | Relationship branch, silent fetches, image gaps, and intermittent search-width quarantine remain. |
| [JournalKit](https://linear.app/kve/view/0ea46c42ff5f) | Concurrent append still discards original errors; full-sync coverage remains one append. |
| [LifecycleKit](https://linear.app/kve/view/b4bc9780ee5f) | Duplicate-input preconditions and the missing trap tests remain unchanged. |
| [Periscope](https://linear.app/kve/view/c0511a6281eb) | Modeling, hierarchy, journal, resume, query, density, handoff, and hosting-coverage requirements remain open. |
| [SnapshotKit](https://linear.app/kve/view/c1d3e2053ada) | Ordinary content still builds once before the configuration loop. Cutsheet isolation does not close this item. |
| [SnapshotKitTesting](https://linear.app/kve/view/82d7e3ada668) | Parse traps, pipeline coverage, and duplicate inline identities remain. Removed the claim that old timings establish current phase costs. |

## Changes since the prior audit

The window `a22b6095..bbe90c4c` contains five merged commits. All five PRs merged on November 6, UTC.
Open PRs, including CI consolidation #484 and snapshot optimization #486, are not shipped evidence.

| PR | Surface checked |
|---|---|
| #469 | Shared documentation classifier, Linux CircleCI selection, continuation jobs, required GitHub job names, and early publication failure after setup failure. |
| #478 | Review guidance for default transport adapters and filesystem cleanup ownership; no executable change. |
| #477 | DayRelabelView suite moved from shard 3 to shard 1. Suite membership and reference inventory remain unchanged. |
| #479 | Previous audit and backlog reconciliation; documentary baseline for this pass. |
| #485 | Dated CI timing/cost report distinguishes production from the unmerged consolidation proposal. No current price or billing verification performed. |

**CI selection:** the classifier checks the complete merge-base diff, including deleted paths and both sides of renames.
Executable Markdown, symlinks, rendered-content paths, empty diffs, and unavailable history select full CI.
Main, manual, and publication events retain full checks. Focused tests exercise these boundaries and continuation request redaction.
Workflow tests check required names, selection conditions, and setup/continuation parameter parity.
These local checks do not execute the hosted providers.

**Publication polling:** the shared controller now stops when setup fails before the requested workflow exists.
The installer and Flyover command tests exercise this failure through their command boundaries.
No signed archive, site publication, or remote artifact mutation occurred during this pass.

**Backlog corrections:** snapshot workers hydrate references at `.circleci/continue.yml:520`; the shared builder does not.
The LFS cache item now names that owner and preserves the missing cold/warm benchmark requirement.
Suite durations and job costs do not establish the current settle/render/compare breakdown.
The snapshot performance item now treats both its old measurements and its optimization conclusion as historical.

**Documentation:** Tools README/AGENTS and root guidance already describe the new CI selection flow.
SnapshotKitTesting guidance points to the continuation file for serial worker configuration.
No additional module API or architecture documentation mismatch was established in this window.
The existing missing Where group README remains filed. Agent mirrors were synchronized.

## Inventory changes

| Inventory | November 4 cutoff | November 9 cutoff |
|---|---:|---:|
| Leaf modules, each with README and AGENTS | 28 | 28 |
| Source Swift files | 890 | 890 |
| Test/support Swift files | 514 | 514 |
| Leaf image-suite Swift files | 69 | 69 |
| Additional tool image suites | 1 | 1 |
| Reference PNGs | 885 | 885 |
| Area backlog files | 11 | 11 |

The shard plan now assigns 70 suites across **14 / 18 / 16 / 22**, with zero intake suites.
The prior plan assigned 13 / 18 / 17 / 22. Reference count does not equal capture count because sheets contain independent panels.

## Module inventory and Verified OK

Counts cover tracked `.swift` files under each leaf's `Sources/`, `Tests/`, and `SnapshotTests/`.
Test counts include support files, not test cases. Every row has both module documents.
The bounded results below retain the prior source conclusions after checking unchanged implementation and test blobs.
They are not new runtime results. No Swift source, test, manifest, or PNG changed since the prior cutoff.

| Module | Source | Test/support | Image suite | Verified OK / bounded result |
|---|---:|---:|---:|---|
| [BroadwayCatalog](Shared/Broadway/BroadwayCatalog/README.md) | 2 | 1 | 0 | Target and iOS scheme still include the placeholder app and empty test. Neither is behavior coverage; the backlog retains both gaps. |
| [BroadwayCore](Shared/Broadway/BroadwayCore/README.md) | 19 | 13 | 0 | Context mutations still update the stylesheet key. Cache sharing remains explicit; unchanged-value and eviction gaps remain filed. |
| [BroadwayUI](Shared/Broadway/BroadwayUI/README.md) | 6 | 4 | 0 | Dependency points downward to BroadwayCore. The nested-observer TODO remains beside unconditional observer creation. |
| [CreditKit](Shared/CreditKit/README.md) | 2 | 3 | 0 | Foundation-only values and manifest-derived attribution ownership remain. The GitHub-slug parsing gap remains reproducible from source. |
| [Flyover](Shared/Flyover/README.md) | 66 | 19 | 1 | Thumbnail metadata reaches native export, Python validation, and browser selection. Device previews supply layout traits; native interaction gaps remain open. |
| [Inspector](Shared/Inspector/README.md) | 23 | 14 | 1 | The four-reference suite retains its intermittent search-width quarantine. Bare-identifier and silent-fetch gaps still match source. |
| [InstallerKit](Shared/InstallerKit/README.md) | 10 | 11 | 0 | Host-injected fetch/preferences and app/bundle selection remain. No package source changed in this window; device acceptance remains open. |
| [InstallerKitUI](Shared/InstallerKitUI/README.md) | 27 | 8 | 5 | Page-owned refresh and typed destinations remain unchanged. The shared five-suite matrix retains 106 references. |
| [JournalKit](Shared/JournalKit/README.md) | 2 | 3 | 0 | Concurrent append still checks count, uniqueness, and per-writer order. The remaining swallowed-error claim concerns diagnostics, not missing-record detection. |
| [LifecycleKit](Shared/LifecycleKit/README.md) | 8 | 10 | 0 | Duplicate-node precondition remains. No duplicate-ID exit test was found; typed launch and cancellation test files remain. |
| [LifecycleKitUI](Shared/LifecycleKitUI/README.md) | 6 | 4 | 0 | Duplicate gate registrations still trap at construction. View rendering remains separate from the launch engine. |
| [PeriscopeCore](Shared/Periscope/PeriscopeCore/README.md) | 53 | 49 | 0 | Span identity remains a computed downcast. Journal attachment still requires a store sink; the pre-attach durability gap remains open. |
| [PeriscopeMacros](Shared/Periscope/PeriscopeMacros/README.md) | 6 | 4 | 0 | The unchanged macro target imports SwiftSyntax without PeriscopeCore. It remains separate from shipping runtime dependencies. |
| [PeriscopeTools](Shared/Periscope/PeriscopeTools/README.md) | 27 | 27 | 1 | Primary-only hierarchy counts remain explicitly tested. Twenty window-only assertions across ten files remain; no conversion to per-view image coverage shipped. |
| [PeriscopeUI](Shared/Periscope/PeriscopeUI/README.md) | 1 | 2 | 0 | The unchanged environment adapter depends on SwiftUI and PeriscopeCore; group guidance retains linked-context semantics. |
| [SnapshotKit](Shared/SnapshotKit/README.md) | 13 | 9 | 0 | Ordinary descriptors retain lazy builders. The runner still evaluates ordinary content once per case; cutsheet panel builders remain separate. |
| [SnapshotKitTesting](Shared/SnapshotKitTesting/README.md) | 30 | 30 | 0 | The ordinary runner reuses its supplied view across configurations. Parse traps and the inline duplicate-ID gap remain; intentional failure probes are not quarantines. |
| [StuffTestHost](Shared/StuffTestHost/README.md) | 2 | 0 | 0 | The UIKit shell marks its test window and depends on TestHostSupport. It does not embed WhereCore. |
| [TestHostSupport](Shared/TestHostSupport/README.md) | 1 | 0 | 0 | Window lookup uses the host marker. The shared resource-path configuration remains in Project.swift. |
| [RegionKit](Where/RegionKit/README.md) | 15 | 10 | 0 | GeoJSON still throws for unsupported geometry. The missing namesake decoding test remains; the raw Other localization key is unchanged. |
| [RegionViewer](Where/RegionViewer/README.md) | 1 | 0 | 0 | The thin NavigationStack host remains. Its missing Broadway root stays in the Where backlog. |
| [Where](Where/Where/README.md) | 9 | 5 | 0 | The regular runtime remains the composition root. Ledger removal did not add another Where store owner or change audience selection. |
| [WhereCore](Where/WhereCore/README.md) | 169 | 126 | 0 | Local summary and picker fan-out gaps remain. Backup format is still v7; raw-GPS attribution and widget read-error gaps remain open. |
| [WhereCrashReporting](Where/WhereCrashReporting/README.md) | 3 | 2 | 0 | The adapter target, test-process gate, source count, and dependencies are unchanged. No live reporting was invoked. |
| [WhereIntents](Where/WhereIntents/README.md) | 15 | 9 | 0 | The injected services handoff and audience-specific widget-store fallback remain. Spotlight and perform-glue verification gaps remain explicit. |
| [WhereShareExtension](Where/WhereShareExtension/README.md) | 6 | 0 | 0 | The extension still composes pending evidence and writes through a local-only store. No extension-specific test bundle was added. |
| [WhereUI](Where/WhereUI/README.md) | 360 | 151 | 61 | Timeline loading/error branches and layout-keyed calendar positioning remain. Initial app-shell reachability, live maps, and visual acceptance stay open. |
| [WhereWidgets](Where/WhereWidgets/README.md) | 8 | 0 | 0 | The provider still requests the next midnight without opening SwiftData. Its scheduling coverage gap remains open. |

**Leaf totals:** 890 source, 514 test/support, and 69 image-suite Swift files.
Tools adds one image-suite file. The unwired journal benchmark, Bumper implementation/tests, and CreditKit's manifest fixture are outside these totals.
`Package.swift` retains 21 library targets, one macro target, and its host test target.
`Project.swift` retains 28 test bundles: 22 iOS unit bundles and six image bundles.
Audience-generated app and extension targets remain declared in the same manifest.

**References:** 744 WhereUI, 106 InstallerKitUI, 24 Tools, five Flyover, four Inspector, and two PeriscopeTools: 885 total.
WhereCore still has 73 of 169 sources without a namesake test; this is a convention proxy, not an untested-behavior count.
The WhereUI catalog still contains 1,021 keys, including 818 without a nonempty comment.
Broadway and Periscope have group docs; Where still lacks its group README.

## Cross-cutting themes and top findings

- Unchanged implementation preserves open acceptance requirements; green documentation checks cannot close runtime defects.
- Suite timings, capture-phase timings, and provider costs answer different performance questions.
- CI configuration now has a selection entry point and a continuation file; job citations must name their current owner.
- Filesystem ownership and pre-attach durability remain independent of this week's CI improvements.

Pointers only; the owning backlogs contain evidence and proposed work.

| Area | Finding | Backlog |
|---|---|---|
| Bumper | Gregorian lint misses implicit `.current` | [Root P0](https://linear.app/kve/view/df229f7aa2f4) |
| WhereCore | Daily-summary reconciliation absent from local fan-out | [Where P0](https://linear.app/kve/view/1cdf347a9c54) |
| PeriscopeCore | Pre-store-attach events lack durable journaling | [Periscope P0](https://linear.app/kve/view/c0511a6281eb) |
| Scripts | Atlas replacement and committed-install recovery races | [Root P1](https://linear.app/kve/view/df229f7aa2f4) |
| WhereCore / WhereUI | Residency requirements, attribution, picker fan-out, and display calendars | [Where P1](https://linear.app/kve/view/1cdf347a9c54) |
| Installer | Signed-device and update-flow acceptance | [Root P1](https://linear.app/kve/view/df229f7aa2f4) |
| Snapshot infrastructure | Captured-model isolation and accessibility parse failures | [SnapshotKit](https://linear.app/kve/view/c1d3e2053ada), [SnapshotKitTesting](https://linear.app/kve/view/82d7e3ada668) |
| Flyover | Focused shortcuts, group identity, drawer bounds, and original errors | [Flyover P2](https://linear.app/kve/view/2292471484f2) |

## Verification and limitations

This run used **macOS with Xcode 27.2 (27B52)**, not the Linux environment assumed by the skill.
The resulting diff changes documentation only.

Executed at the reviewed source:

- `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=Tools/Tests python3 -m unittest test_ci_changes test_ci_circleci test_ci_workflows test_circleci_pipeline test_circleci_distribution test_flyover_distribution test_flyover_workflows test_snapshot_shards test_test_runner` — **116 tests passed**.
- `./snapshot-shards check` — valid, 70 suites with the assignments above.
- `./sync-agents` — passed; only ignored mirrors generated.
- Recounted tracked module files and PNGs; checked source citations, unchanged implementation blobs, and the complete documentation diff.
- Local Markdown targets and `git diff --check` checked before publication.

`./test`, SwiftFormat, architecture execution, simulator captures, and browser execution were skipped for this documentation-only diff.
No live VoiceOver, physical-device installation, CloudKit, Linux portability, or new performance result is claimed.
Visual findings retain their earlier evidence dates; this pass did not inspect rendered references or exercise scroll reachability.
The earlier publication-race probes remain historical evidence against unchanged code; this pass did not rerun those probes.

GitHub confirms that `kve-stuff/Stuff-CI-Benchmark` still exists and is not archived on November 9.
Billing, downgrade, and installed-integration state remain unverified.
CI results for the publication commit belong to its PR. Documentation skips do not establish runtime coverage.
