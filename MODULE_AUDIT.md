# Swift Module Audit Report

**Date:** November 4, 2026 (America/New_York)
**Reviewed source:** `a22b6095254d391cb70a2dbed61943647ecbdeab` (PR #474), fetched from `origin/main`.
**Prior audit:** October 26, 2026, source cutoff `123272e3f2361a9fa2d23879d654eede6d90b072`, report merged in PR #441.

This report derives from all **11 current `TODOs.md` files**. It carries no actionable items.
The root [backlog](TODOs.md) owns item format and placement.
The report describes the header date and reviewed source, not later HEADs.

## Method and backlog reconciliation

The pass read every open area backlog and checked its cited source seams, test inventory, and changes since the prior cutoff.
Unchanged implementations were compared with that cutoff; this was not a fresh line-by-line review of all 890 source files.
Design requests remain decisions, source findings remain findings, and runtime acceptance remains unverified unless explicitly exercised below.
Existing priorities, human origins, and completed history remain intact.

`INBOX.md` has no open notes. Nothing required promotion or a decline verdict.
No open implementation item met its full closure condition this week.
Ledger's already-archived items now cite PR #451 and its actual October 27 merge date.
No new independent defect was established; existing findings were corrected or sharpened instead of duplicated.

| Backlog | Result of this pass |
|---|---|
| [Root](TODOs.md) | Retained calendar enforcement, publication races, distribution acceptance, portability, parser, package, and documentation items. Corrected CI locations and Ledger dates. Narrowed LFS caching to the remaining benchmark decision. |
| [Where](Where/TODOs.md) | Retained reconciliation, attribution, recording, performance, test, localization, and visual acceptance requirements. Expanded the identifier question; corrected naming, welcome, map, and widget-fixture citations. |
| [Broadway](Shared/Broadway/TODOs.md) | Rechecked placeholder/host/test, observer, invalidation, cache, and namesake-test gaps. Corrected target and scheme locations. |
| [CreditKit](Shared/CreditKit/TODOs.md) | The permissive GitHub-slug expression remains; no focused malformed-pin regression was found. |
| [Flyover](Shared/Flyover/TODOs.md) | Retained shortcut, group-filter, drawer, error-preservation, and native interaction gaps. Added the bounded effect of this week's thumbnail and layout-trait work. |
| [Inspector](Shared/Inspector/TODOs.md) | Retained fetch, relationship, image-coverage, and search-width requirements. Distinguished its intermittent quarantine from deliberate failure assertions. |
| [JournalKit](Shared/JournalKit/TODOs.md) | Concurrent append still discards original errors. Full-sync coverage remains one append; neither item is closed. |
| [LifecycleKit](Shared/LifecycleKit/TODOs.md) | Both uniqueness guards remain; their duplicate-input trap tests remain absent. |
| [Periscope](Shared/Periscope/TODOs.md) | Rechecked all modeling, hierarchy, journal, resume, query, density, handoff, and hosting-coverage items. Corrected the image-bundle location. |
| [SnapshotKit](Shared/SnapshotKit/TODOs.md) | Ordinary configuration model isolation remains distinct from fresh cutsheet panels and retry reuse. |
| [SnapshotKitTesting](Shared/SnapshotKitTesting/TODOs.md) | Retained parse-failure, pipeline-coverage, inline-identity, and performance items. Historical timing and visual requirements remain unverified this week. |

The identifier search found 13 production modifiers and no tracked consumers of their string values.
That does not establish that external automation has no consumers; the existing P1 remains a policy decision.
The widget timestamp correction separates `referenceWidgetDay` from an evidence fixture with the same numeric instant.

## Changes since the prior audit

The window `123272e3f..a22b6095` contains nine merged commits, including the previous audit commit.
Dates below are GitHub merge dates in UTC, not branch-author dates.
Open StorageKit, compatibility, multi-device, theme, and Duo PRs are not shipped evidence.

| Merged | PR | Surface checked |
|---|---|---|
| October 27 | #441 | Previous backlog and audit publication; treated as the documentary baseline. |
| October 27 | #451 | Ledger, LedgerCore, installer wrapper, and native macOS app-test scheme removed. Retired issues remain archived. |
| October 27 | #452 | Native thumbnail pyramid, optional manifest metadata, Python validation/versioning, browser size selection, and regression fixtures. |
| October 27 | #453 | Lint, tool, and web jobs separated. Live branch protection requires all three new statuses. |
| October 31 | #465 | DerivedData ownership, dry run, orphan eligibility, and public cleanup wrapper. Focused temporary-directory tests passed. |
| November 2 | #467 | Xcode 27.2 major/minor pin, simulator defaults, shell/tool expectations, and reference replacement. No visual approval inferred from replacement. |
| November 4 | #470 | Accepted-pipeline and workflow-discovery 404 retries; deadline, response closure, and non-discovery failures. |
| November 4 | #471 | Independent web accessibility tests by surface; native device-preview layout traits and host sizing. |
| November 4 | #474 | Installer controller uses the shared HTTP transport. Public-command tests cover eventual discovery and timeout without duplicate submission. |

**Flyover:** native exports retain the largest thumbnail and add smaller variants without upscaling.
Python validates paths, dimensions, order, and aspect ratio; publication versions the additional assets.
Browser selection considers layout size, zoom, pixel density, and contain/cover mode.
Seven TypeScript tests passed, including legacy fallback and the shared native manifest fixture.
Browser bounds, request budgets, and axe assertions were inspected, but browser tests did not run during this pass.
Native layout-trait assertions cover phone orientations, tablets, and fixed components; they do not close native inspector/menu image gaps.

**Tooling:** CircleCI discovery retries only the accepted pipeline's missing pipeline/workflow resources and remains bounded by the polling deadline.
Other HTTP failures propagate. Installer transport tests exercise the actual command entry point with fake HTTP responses.
Cleanup tests use temporary directories and fake simulator commands; no developer cache or device was removed.
The cleanup contract explicitly excludes concurrent path mutation guarantees.

**Existing counterexamples:** fresh temporary-directory probes reproduced both filed atlas publication races at this cutoff.
Installation can replace an empty competing directory, and context exit can restore an old atlas after the committed destination moves.
A parser probe still rejects a parameterized Swift Testing completion while accepting an ordinary completion.
These results sharpen existing root items; the passing ordinary tests do not establish those missing guarantees.

**Documentation:** current Flyover READMEs/AGENTS describe thumbnail selection and device traits.
Tools guidance describes cleanup ownership and discovery retries; root guidance describes the split CI jobs and Xcode pin source.
No additional module architecture/API documentation mismatch was established in this window.
The missing Where group README remains filed. Generated agent mirrors were synchronized.

## Inventory changes

| Inventory | October 26 cutoff | November 4 cutoff |
|---|---:|---:|
| Leaf modules, each with README and AGENTS | 30 | 28 |
| Source Swift files | 914 | 890 |
| Test/support Swift files | 528 | 514 |
| Leaf image-suite Swift files | 69 | 69 |
| Additional tool image suites | 1 | 1 |
| Reference PNGs | 885 | 885 |
| Area backlog files | 12 | 11 |

Ledger removal accounts for the 24 source files, 14 test/support files, two modules, and one backlog file removed.
Reference count does not equal capture count: comparison sheets contain independently captured panels.
The shard plan remains 70 suites across 13 / 18 / 17 / 22 planned assignments and zero intake suites.

## Module inventory and Verified OK

Counts cover tracked `.swift` files under each leaf's `Sources/`, `Tests/`, and `SnapshotTests/`.
Test counts include support files, not test cases. Every row has both module documents.
The bounded results below are source checks unless the verification section explicitly names an executed check.

| Module | Source | Test/support | Image suite | Verified OK / bounded result |
|---|---:|---:|---:|---|
| [BroadwayCatalog](Shared/Broadway/BroadwayCatalog/README.md) | 2 | 1 | 0 | Target and iOS scheme still include the placeholder app and empty test. Neither is behavior coverage; the backlog retains both gaps. |
| [BroadwayCore](Shared/Broadway/BroadwayCore/README.md) | 19 | 13 | 0 | Context mutations still update the stylesheet key. Cache sharing remains explicit; unchanged-value and eviction gaps remain filed. |
| [BroadwayUI](Shared/Broadway/BroadwayUI/README.md) | 6 | 4 | 0 | Dependency points downward to BroadwayCore. The nested-observer TODO remains beside unconditional observer creation. |
| [CreditKit](Shared/CreditKit/README.md) | 2 | 3 | 0 | Foundation-only values and manifest-derived attribution ownership remain. The GitHub-slug parsing gap remains reproducible from source. |
| [Flyover](Shared/Flyover/README.md) | 66 | 19 | 1 | Thumbnail metadata reaches native export, Python validation, and browser selection. Device previews now supply layout traits; native interaction gaps remain open. |
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

- Partial test improvements need narrow closure criteria. Thumbnail tests and device traits do not prove native navigation or scroll reachability.
- Filesystem validation does not establish publication ownership. Both existing rename counterexamples remain reproducible despite ordinary recovery tests passing.
- A toolchain refresh invalidates old timing and visual assumptions. Reference replacement alone supplies neither live acceptance nor a new performance measurement.
- Independent CI jobs need independent required statuses. GitHub protection now names the three split jobs; no protection gap was found.
- Existing write fan-out and pre-attach durability gaps survive unrelated UI and tooling growth.

Pointers only; the owning backlogs contain evidence and proposed work.

| Area | Finding | Backlog |
|---|---|---|
| Bumper | Gregorian lint misses implicit `.current` | [Root P0](TODOs.md) |
| WhereCore | Daily-summary reconciliation absent from local fan-out | [Where P0](Where/TODOs.md) |
| PeriscopeCore | Pre-store-attach events lack durable journaling | [Periscope P0](Shared/Periscope/TODOs.md) |
| Scripts | Atlas replacement and committed-install recovery races | [Root P1](TODOs.md) |
| WhereCore / WhereUI | Residency requirements, attribution, picker fan-out, and display calendars | [Where P1](Where/TODOs.md) |
| Installer | Signed-device and update-flow acceptance | [Root P1](TODOs.md) |
| Snapshot infrastructure | Captured-model isolation and accessibility parse failures | [SnapshotKit](Shared/SnapshotKit/TODOs.md), [SnapshotKitTesting](Shared/SnapshotKitTesting/TODOs.md) |
| Flyover | Focused shortcuts, group identity, drawer bounds, and original errors | [Flyover P2](Shared/Flyover/TODOs.md) |

## Verification and limitations

This run used **macOS with Xcode 27.2 (27B52)**, not the Linux environment assumed by the skill's environment paragraph.
The final change is documentation-only. No executable, target, dependency, product copy, or reference image changed.

Executed at the reviewed source:

- `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=Tools/Tests python3 -m unittest test_circleci_pipeline test_circleci_distribution test_flyover_distribution test_flyover_images test_flyover_manifest test_flyover_publication test_worktree_cleanup test_worktree_command test_test_runner` — **99 tests passed**.
- `mise exec -- node --experimental-strip-types --test Shared/Flyover/Web/tests/thumbnail-selection.test.ts Shared/Flyover/Web/tests/catalog.test.ts` — **7 tests passed**.
- `./swiftformat --lint` — **0 of 1,482 files required formatting; 143 skipped**. Mise needed sandbox escalation to register the isolated checkout.
- `./snapshot-shards check` — valid, 70 suites with the assignments above.
- `./sync-agents` — passed; only ignored mirrors generated.
- Temporary-directory publication probes and a completion-parser probe reproduced the three existing defects described above.
- Tracked inventory, backlog source citations, local Markdown links, and `git diff --check` were checked during final review.

`./test`, architecture execution, simulator captures, browser execution, live VoiceOver, and physical-device installation were not run.
The documentation diff does not exercise those runtime paths; the original acceptance requirements remain open.
No new snapshot timing, memory, visual-reference approval, CloudKit delivery, or Linux portability result is claimed.
No signing, deployment, remote artifact deletion, or billing change occurred.

GitHub confirms that `kve-stuff/Stuff-CI-Benchmark` still exists and is not archived on November 4.
Billing, downgrade, and installed-integration state remain unverified.
The audit found no unfinished matching triage PR before branch creation.
CI results for the publication commit belong to its PR; historical green runs are not validation of that commit.
