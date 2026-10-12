# Swift Module Audit Report

**Date:** October 12, 2026
**Reviewed source:** `b591173f` (PR #364), fetched from `origin/main`.
**Prior audit:** October 5, 2026, report merged in PR #339 (`56c61635`), whose stated source coverage ended at PR #315 (`bfc0c94d`).

This report is derived from all 12 `TODOs.md` files and carries no actionable
items. The root [`TODOs.md`](TODOs.md) owns their format and placement. It is
true as of the header date and reviewed source, not as of later HEADs.

**Merge reconciliation:** the branch also includes later October 12 main commits
`d799a96a` (#365) and `ba3d8fb3` (#366). The live Where backlog preserves their
calendar-positioning requirement and completed calendar/year accessibility fixes.
Those closures and rendered-image evidence come from #366; this report retains
its original source cutoff and does not claim a new visual audit of those changes.

## Method and changes since the previous audit

The pass read every open area backlog, inspected cited source/test mechanisms,
and compared changed implementations with their existing acceptance conditions.
Tracked source, test/support, image-suite and reference files were recounted
against the manifests.
Unchanged areas were checked at the cited seams and against unchanged diffs;
this is a focused static review, not a fresh line-by-line review of all 791 sources.
Historical runtime observations remain historical. The inbox is empty.

The reviewed window is `bfc0c94d..b591173f`, including changes after the prior
report's source cutoff on October 5. GitHub merge metadata, rather than branch
commit dates, establishes the following landing dates (UTC):

| Merged | PRs | Surface reviewed |
|---|---|---|
| October 5 | #338, #339 | Historical device labels; prior audit |
| October 7 | #333, #340, #341 | Vector Flyover connectors; resumed-flight endpoints and point decisions; shard maintenance |
| October 8 | #342, #343 | Review-derived repository guidance and monthly review workflow |
| October 11 | #273, #269 | Classified logging runtime/macros, consumer migration, export controls and structured errors |
| October 11 | #354, #352, #355, #332, #356 | Shard rebalance/stability, Bumper timeout/cache, PR API and image guidance |
| October 12 | #364 | PR diagram guidance |

PR bodies supply intent and historical verification, not results from this run.
Compatibility and IdentifierKit work from the earlier stack remains outside this
source boundary; the current backup format is v6.

| Area | October 5 report | October 12 state |
|---|---|---|
| Source / test-support / image-suite files | 764 / 407 / 56 | **791 / 431 / 57** |
| Modules with leaf doc pairs | 27 | **28**, including PeriscopeMacros |
| PeriscopeCore | 38 / 33 | **53 / 49** source / test-support |
| WhereCore | 148 / 97 | **152 / 101** source / test-support |
| WhereUI | 321 / 124 / 53 | **323 / 124 / 54** |
| Reference images | 747 | **761**, including 750 WhereUI |
| Test bundles | 25 Tuist bundles | **25 Tuist + 1 SwiftPM host macro bundle** |
| Shard suite assignments | 13 / 15 / 18 + 10 intake | **16 / 19 / 22 + 0 intake** |
| Raised-floor configurations | 71 | **71**, unchanged; no fresh timing measurement |
| Backlog | RemoteLogField test gap open | **One item archived as superseded**, citations and inventories refreshed |

The retired RemoteLogField test request is archived with the API-removal evidence
and the replacement live/stored category-filtering guards. This does not claim
constructor-trap coverage. Previously completed export-policy/file-sharing entries
now name the actual October 11 merges instead of an unmerged stack. The CI
serial-axis documentation item was already closed by #342; its date is corrected
to the October 8 merge date. Priorities and original provenance are preserved.
No additional product defect was established beyond the existing backlog.

The Ledger backlog no longer claims Bumper excludes LedgerCore. Its dependency
and logging rules now apply there, while the Gregorian rule remains Where-only.
Documentation now describes span-only `@LogScope` enums and the broader Bumper
scope. Periscope's compatibility instructions distinguish manual development-store
reset from automatic deletion; historical records remain available as raw rows.
Two obsolete source-comment examples were removed or corrected. These edits
change no executable behavior, target, dependency, or concurrency boundary.

## New-surface review

**Classified logging:** macro field parsing is shared between scope and event
expansion. Explicit wire IDs and resolved field keys have validation; generated
methods use qualified runtime types and typed classified inputs. PeriscopeCore
applies export requirements before encoding, composes nested restrictions, and
never lets grants override `.never`. Permission trees persist beside local
payloads in store rows and journals. Existing tests cover denied encoders,
category mutation/decoding, custom encoders, invalid versions, and live/stored
projection parity. No privacy guarantee is inferred from a string's contents.

`NDJSONExporter` requires an explicit mode. Current manual-sharing callers remain
unfiltered by product choice. Filtered export uses stable messages, excludes folded
ambient snapshots, and treats historical rows without permissions conservatively.
The remote adapter uses framework context permissions independently of the UI's
combined switch; failures drop the remote record with an observable counter and
OSLog diagnostic. `LogError` retains bounded typed details without arbitrary
NSError userInfo. Local records remain complete. Network upload and live provider
behavior were not exercised.

**Flight review:** resumed cruise endpoints require measured-speed or bounded-gap
corroboration; a gap is not an observed leg or proof of arrival. Point edits use
completed flights on the point's own recording device, exclude pending/conflicting
identities and authoritative manual days, and count independent sample/manual
support. Inclusion and restoration recheck the reviewed evidence inside the
expected-generation transaction. Restoration appends a newer reset revision.
Source tests cover late evidence, generation changes, duplicate rows, support
retention, mixed reviews, and stale confirmations. Historical names include removed
profiles. The point-row matrix adds 14 references, but no rendering was accepted
or live navigation exercised here.

**Flyover and CI:** Flyover draws connector paths as vector views without a
catalog-sized bitmap. Its existing geometry tests and image inventory remain,
but the focus/menu/transition coverage item stays open. Shard rebalancing now
preserves assignments below the improvement threshold, assigns intake first,
and writes assignment-only plans; tests cover stable reruns, intake, threshold,
nonempty shards, and coverage preservation. The current plan passes static
validation. Bumper's CI evaluation timeout is 120 seconds and its cache key
includes runner configuration. These are source checks, not fresh CI timings.

## Top findings

Pointers only; evidence and proposed fixes live in the owning backlog.

| Area | Finding | Backlog |
|---|---|---|
| Bumper | Gregorian rule misses implicit `.current` | [Root P0](TODOs.md) |
| WhereCore | Daily summary absent from local fan-out | [Where P0](Where/TODOs.md) |
| PeriscopeCore | Pre-store-attach records absent from durable log | [Periscope P0](Shared/Periscope/TODOs.md) |
| WhereUI | Four production Gregorian defaults/helpers remain | [Where P1](Where/TODOs.md) |
| WhereCore | Picker fan-out and hard-deleting untracked regions | [Where P1](Where/TODOs.md) |
| WhereCore | Full report aggregation and attribution-history read amplification | [Where P1](Where/TODOs.md) |
| WhereUI | Full Timeline lacks a report loading gate | [Where P1](Where/TODOs.md) |
| WhereUI | Launch-time notification permission prompt | [Where P1](Where/TODOs.md) |
| SnapshotKit | Captured models shared across configurations | [SnapshotKit P1](Shared/SnapshotKit/TODOs.md) |
| WhereUI | Diagnostics apply failure loses durable error signal | [Where P2](Where/TODOs.md) |
| WhereUI | Pending flight guidance absent from Explore Features | [Where P2](Where/TODOs.md) |
| Scripts | Linux portability and Python-cache hygiene gaps | [Root P1](TODOs.md) |
| Repository | Missing Where and Ledger group docs | [Root P1](TODOs.md) |

The benchmark organization cleanup remains open after its saved September 9
plan-downgrade date. `gh repo view` confirms the repository exists and is not
archived on October 12. Billing, actual downgrade, and installed integrations
remain unverified. No deletion or billing action was taken.

## Cross-cutting themes

- **Export permissions and local durability are separate.** Classified logging
  improves filtered export; it does not close the pre-store journal or
  multi-process coordination gaps.
- **A replacement API changes the evidence needed to close a test request.**
  Removed names do not need namesake tests, but replacement privacy behavior
  needs its own positive and negative guards.
- **More review controls increase the importance of one coherent scan.** Point
  decisions preserve raw evidence and refresh through the same dismissal-aware
  result as bulk review; discovery still overlooks informational-only states.
- **Inventory is not behavior coverage or performance.** More tests/references
  and redistributed shards do not prove live reachability or faster rendering.
- **Documentation must follow expanded enforcement scope.** Periscope and
  LedgerCore now participate in Bumper without making every Where rule global.

## Module inventory and Verified OK

Counts are tracked `.swift` files under each module's `Sources/`, `Tests/`, and
`SnapshotTests/`; tests include support files and do not equal test cases.
All **28 leaf modules** have both README.md and AGENTS.md. Results below are
static unless explicitly identified as executed.

| Module | Source | Test/support | Image suite | Verified OK / bounded result |
|---|---:|---:|---:|---|
| [Ledger](Ledger/Ledger/README.md) | 8 | 0 | — | Native macOS app and hostless LedgerCore scheme remain separate from iOS; app has no test bundle by design. |
| [LedgerCore](Ledger/LedgerCore/README.md) | 16 | 14 | — | Explicit refresh-generation guard and scripted API/Keychain seams retained; 14 test/support files, with the three filed namesake gaps; the logging facade now uses the freeform scope API. |
| [BroadwayCatalog](Shared/Broadway/BroadwayCatalog/README.md) | 2 | 1 | — | Catalog target is in the iOS scheme; its placeholder and empty test are still accurately filed, not counted as behavior coverage. |
| [BroadwayCore](Shared/Broadway/BroadwayCore/README.md) | 18 | 12 | — | BScaledDimension uses explicit category metrics; category round-trip and ambient-trait independence tests are present. Cache and unchanged-value gaps remain. |
| [BroadwayUI](Shared/Broadway/BroadwayUI/README.md) | 6 | 4 | — | Depends downward on BroadwayCore; nested-observer TODO remains at the cited source. |
| [CreditKit](Shared/CreditKit/README.md) | 2 | 3 | — | Foundation-only value layer; attribution report passes at 13 credits; shipping reachability stops at macro targets. Generator slug issue remains localized to parsing. |
| [Flyover](Shared/Flyover/README.md) | 54 | 14 | 1 | Manifest has no Where dependency; 14 test/support files and one image suite remain. Connector paths now remain vector views rather than a graph-sized Canvas texture; interaction coverage remains separate. |
| [Inspector](Shared/Inspector/README.md) | 23 | 14 | 1 | One image suite has four references; relationship branch and three silent fetch defaults still match the backlog. |
| [JournalKit](Shared/JournalKit/README.md) | 2 | 3 | — | Concurrent append test checks recovered count, uniqueness, and writer order; swallowed error diagnostic is the actual remaining gap. |
| [LifecycleKit](Shared/LifecycleKit/README.md) | 8 | 10 | — | Duplicate-ID precondition is present; existing test files still cover typed launch and cancellation. Duplicate-ID exit-test gap remains. |
| [LifecycleKitUI](Shared/LifecycleKitUI/README.md) | 6 | 4 | — | Gate-registration uniqueness guard remains present; view-level splash ownership is unchanged. |
| [PeriscopeCore](Shared/Periscope/PeriscopeCore/README.md) | 53 | 49 | — | Span accessors downcast rather than store parallel span fields; journal still installs with the store. Classified export metadata is retained beside complete local payloads; category rejection has live and stored guards. |
| [PeriscopeMacros](Shared/Periscope/PeriscopeMacros/README.md) | 6 | 4 | — | New build-host-only target; expansion tests cover literal classifications, key collisions, static/conditional fields, reserved names, and qualified generated APIs. No runtime PeriscopeCore import. |
| [PeriscopeTools](Shared/Periscope/PeriscopeTools/README.md) | 27 | 27 | 1 | Hierarchy count/query asymmetry is explicitly pinned; 20 hosting-only assertions across 10 files and two image references remain. |
| [PeriscopeUI](Shared/Periscope/PeriscopeUI/README.md) | 1 | 2 | — | Single SwiftUI environment adapter imports only PeriscopeCore and SwiftUI; test/support inventory unchanged. |
| [SnapshotKit](Shared/SnapshotKit/README.md) | 8 | 3 | — | Shippable matrix remains separate from comparison engine; docs continue to disclose that the runner shares captured models across configurations. |
| [SnapshotKitTesting](Shared/SnapshotKitTesting/README.md) | 16 | 16 | — | Provider duplicate guard, cancellation outcome, parse failure paths and config loop match filed issues; shard plan validates all 57 suites; no capture-engine source changed. |
| [StuffTestHost](Shared/StuffTestHost/README.md) | 2 | 0 | — | UIKit shell delegates test-window setup to TestHostSupport; no WhereCore import or new source. |
| [TestHostSupport](Shared/TestHostSupport/README.md) | 1 | 0 | — | UIKit/Objective-C hosting seam remains app-independent; host smoke contract is exercised from LifecycleKit tests. |
| [RegionKit](Where/RegionKit/README.md) | 15 | 10 | — | GeoJSON decoding gap is honestly documented; source still throws for unsupported geometry. Logging uses classified macros and restricted original errors; geometry behavior and decoding coverage are unchanged. |
| [RegionViewer](Where/RegionViewer/README.md) | 1 | 0 | — | Bundled per-region data description remains correct; missing Broadway root is still filed in Where. |
| [Where](Where/Where/README.md) | 9 | 5 | — | Reporting uses stable event names and filtered projections; encoding failures are counted and logged through OSLog without recursive Periscope emission. Existing audience/runtime injection remains. |
| [WhereCore](Where/WhereCore/README.md) | 152 | 101 | — | Point decisions are limited to completed flights on the same device, preserve manual support, and recheck evidence inside the generation transaction. Historical labels include removed profiles. Backup remains v6. |
| [WhereCrashReporting](Where/WhereCrashReporting/README.md) | 3 | 2 | — | Capture SDK stays behind the dedicated adapter target; no source, dependency, or test changes in this window. |
| [WhereIntents](Where/WhereIntents/README.md) | 15 | 9 | — | Injected audience group reaches the snapshot reader; App Group-open failure is logged before report fallback. README states the perform-glue testing limitation. |
| [WhereShareExtension](Where/WhereShareExtension/README.md) | 6 | 0 | — | Extension validates its audience and uses local-only storage in that audience’s App Group. Pending-evidence construction and the filed form/testing gaps are unchanged. |
| [WhereUI](Where/WhereUI/README.md) | 323 | 124 | 54 | Point decisions refresh from the shared scan and invalidate stale confirmations. Point maps retain raw coordinates; new rows use shared styles and full-content fixtures. Live accessibility and scroll behavior were not exercised. |
| [WhereWidgets](Where/WhereWidgets/README.md) | 8 | 0 | — | Audience-specific group is injected into both snapshot and presentation stores; provider retains the midnight reload policy without opening the app’s SwiftData store. |

**Totals:** 791 source, 431 test/support, and 57 image-suite Swift files.
Inventory excludes two unwired journal-benchmark sources, six Bumper source/test
files, and CreditKit's Swift manifest fixture under its Ruby-tool tests.
`Package.swift` has 20 library targets plus one macro and one host test target.
`Project.swift` retains seven app/extension families and 25 test bundles:
20 iOS unit bundles, LedgerCoreTests, and four image bundles. The macro test
bundle is additional and runs on the host through `./test`.

**References:** 750 WhereUI, five Flyover, four Inspector, two PeriscopeTools:
761 total. WhereCore's basename proxy is 70 of 152 sources without a namesake
test, previously 69 of 148. This is not a count of untested behaviors.

**Group docs:** Broadway and Periscope have both docs; Where lacks its group
README and Ledger lacks both group docs. The existing root item remains open.

**Bumper:** ten Where rules have twelve test functions; six Periscope authoring
rules have six test functions (some parameterized). Graph mutation coverage still
omits duplicate ownership and declared cycles. The explicit Calendar filter
misses the same 11 implicit calendar sites: four production and seven DEBUG.
Source inspection supports these statements; architecture execution was not rerun.

## Verification and limitations

- `./swiftformat --lint` — passed, 0 of 1,287 files require formatting;
  135 skipped. Optional cache write was sandbox-blocked without changing the result.
- `./shellcheck` — passed.
- `./attribution --check` — passed, 13 credits current, including host-only SwiftSyntax.
- `./sf-symbols --lint` — passed.
- `./xcstrings --lint` — passed, seven catalogs match Xcode serialization;
  compiler-cache access was required after the initial sandbox failure.
- `./snapshot-shards check` — passed, all 57 suites assigned, no intake.
- `./sync-agents` and `git diff --check` — passed. Generated mirrors are ignored.
- Tracked-file inventory and edited Markdown link checks were performed separately.
- This host is **macOS**; this pass remains **static analysis** plus the supported
  checks above. The skill's Linux limitations remain: Tuist, Xcode, and simulator
  validation cannot run there. No runtime suite is implied by this audit.
- `./test`, architecture execution, macro/unit/image suites, and retained Python/Ruby
  tests were skipped for documentation/comment-only changes. No executable code,
  configuration, rendered copy, dependency, matrix, or reference was changed.
  Existing Linux portability findings were not reproduced or closed.
- No new screenshots, animations, VoiceOver sessions, scroll/year-switch gestures,
  device checks, or performance measurements were performed. Visual and runtime
  acceptance requirements remain open; prior PR evidence remains historical.
- CloudKit delivery/convergence, passive background location, multi-process
  journals, logging isolation, billing, and Ledger API/Keychain behavior were
  not exercised. Historical timings and spikes retain their environment limits.
