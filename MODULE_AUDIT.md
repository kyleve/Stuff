# Swift Module Audit Report

**Date:** October 5, 2026
**Reviewed source:** `bfc0c94d` (PR #315), fetched from `origin/main`.
**Prior audit:** September 28, 2026, report merged in PR #328 (`77e65f8e`), whose stated source coverage ended at PR #326 (`e15577ad`).

This report is derived from all 12 `TODOs.md` files and carries no actionable
items. The root [`TODOs.md`](TODOs.md) owns their format and placement. This
report is true as of the header date and source boundary, not as of later HEADs.

## Method and changes since the previous audit

The pass read every open area backlog, checked cited source/test mechanisms,
reviewed the covered-source commit window and merged PR descriptions, and
recounted tracked sources, tests, reference images, module doc pairs, and target
wiring. Unchanged areas were checked against their cited seams and unchanged
diffs; this was not a fresh line-by-line review of all 764 sources. Historical
spikes and runtime observations remain historical, not newly reproduced facts.

The source window is `e15577ad..bfc0c94d`: the Explore Features stack fix
(#327, `ddca3c88`), the prior audit (#328, `77e65f8e`), and flight recognition
with sample attribution corrections (#315, `bfc0c94d`). GitHub merge metadata
confirms the first two landed on September 28 after the previous source boundary,
and #315 on October 4. PR descriptions supplied intent and historical validation;
their runtime test counts are not results from this run. Follow-up compatibility
and IdentifierKit work described by #315 is outside this reviewed main branch.
The shipped backup format here is v6, not the proposed follow-up v7.

| Area | September 28 report | October 5 state |
|---|---|---|
| Source / test-support / image-suite files | 731 / 382 / 55 | **764 / 407 / 56** |
| WhereCore | 132 / 86 | **148 / 97**; flight assessment, correction history, and projection seams |
| WhereUI | 304 / 110 / 52 suites | **321 / 124 / 53 suites**; flight reviews, map geometry, and gallery boundaries |
| Reference images | 575 | **747**, including 736 WhereUI references |
| Module / test bundle count | 27 / 25 | **27 / 25**, unchanged |
| Inbox | Empty | **Empty**; no notes to promote or decline |
| Backlog | Open shared-primary policy request | **One item archived**, one gallery gap filed; existing performance item refined |
| Raised-floor configurations | 55 | **71**; eleven Locations cases contribute 38 one-second configurations |

The request to move RegionDays/RegionRanking into Core is archived because its
headless-scanning goal already shipped in #65 (`26ac3e3a`). Both the scanner
and UI ranking use `Region.primaryRegions`; the presentation structs remain in
WhereUI. This is a corrected stale backlog entry, not a change shipped this week.

The new P2 gallery item records missing pending-flight guidance and the
zero-actionable-issue link restriction. The existing report-performance item now
includes attribution-history read amplification; no latency regression was
measured. The hard-delete item distinguishes uncorrected raw region membership
from explicit correction replacements. The Gregorian count falls from 12 to 11
because a DEBUG flight fixture was replaced; all four production sites remain.
Moved citations and inventories were refreshed without changing priorities or
original provenance. Historical timing numbers were not recalculated.

Documentation corrections align the feature overview and Core report tour with
effective attribution and manual-day precedence, narrow the motion claim to the
speed veto actually implemented, update GPS span guidance, and reconcile Core's
test guidance with the existing isolated temporary-store tests. The Core tour
also distinguishes service consumers from snapshot-only widget reads. No target
or build/test flow changed, and these instruction edits introduce no new
concurrency boundary. Agent mirrors are synchronized after instruction edits.

## New-surface review

**Verified OK in source and existing tests:** `FlightTrajectoryAnalyzer` groups
raw observations by recording source, requires sustained positional jet-speed
legs, and uses arrival ground dwell rather than silence to complete a flight.
Sparse or stale observations remain uncertain. Reported speed can veto a ground
anchor; altitude does not establish a flight. Tests include pending, completed,
sparse, source-separated, and motion-evidence cases. No live flight trace was
replayed during this audit.

`SampleCorrectionAssessment` analyzes raw evidence before day bucketing and
projects contextual attribution separately. It keeps supported pending-flight
samples out of boundary cleanup while allowing independent completed corrections.
Proposals carry exact sample edits in stable order. `SampleCorrectionCoordinator`
rechecks the proposal inside an expected-generation transaction and returns stale
when the reviewed evidence changed. `LocationHistoryReader` applies removal
visibility and effective revisions against the live tracked-region snapshot.
The store checks immutable-revision conflicts; manual-day reset writes newer
correction tombstones. Backup v6 and the external upgrader preserve motion and
revision history. These checks do not prove CloudKit convergence at runtime.

`DataIssueScanner` publishes a coherent result with actionable issues,
informational reviews, and a reassessment deadline, guarded by its invalidation
epoch. `YearReportModel` rejects stale request publication and schedules pending
review refreshes. Resolve presents pending flight reviews even at zero actionable
count. The new discovery gap is confined to Explore Features, as filed in Where's
P2 backlog; zero issues alone is not proof of an all-clear GPS review.

`RecordedMapData` limits pin and route geometry while retaining route endpoints.
The four new Locations flight fixtures and FlightReview image suite increase
coverage inventory, but no new reference was rendered or visually accepted here.
The existing map/rosette performance and layout items remain open.

PR #327 extracts eight gallery Forms/row groups behind named views; Estimated
Time was already separated. Body-size tests cover the nine destinations and
wrapper with a 16 KB budget. This source boundary supports the documented device
stack-overflow fix; the PR's device and snapshot results remain historical.

## Top findings

Pointers only; evidence and proposed fixes live in the backlog.

| Area | Finding | Backlog |
|---|---|---|
| Bumper | Gregorian rule misses implicit `.current` | [Root P0](TODOs.md) |
| WhereCore | Daily summary absent from local fan-out | [Where P0](Where/TODOs.md) |
| PeriscopeCore | Pre-store-attach records absent from durable log | [Periscope P0](Shared/Periscope/TODOs.md) |
| WhereUI | Four production Gregorian defaults/helpers remain | [Where P1](Where/TODOs.md) |
| WhereCore | Picker fan-out and hard-deleting untracked regions | [Where P1](Where/TODOs.md) |
| WhereCore | Full report aggregation and attribution-history read amplification | [Where P1](Where/TODOs.md) |
| WhereUI | Full Timeline still lacks a report loading gate | [Where P1](Where/TODOs.md) |
| WhereUI | Launch-time notification permission prompt | [Where P1](Where/TODOs.md) |
| SnapshotKit | Captured models shared across configurations | [SnapshotKit P1](Shared/SnapshotKit/TODOs.md) |
| WhereCore tests | History-source termination conflated with timeout | [Where P2](Where/TODOs.md) |
| WhereUI | Pending flight review absent from discovery guidance | [Where P2](Where/TODOs.md) |
| CI / scripts | Serial-axis documentation and Linux portability gaps | [Root P1](TODOs.md) |
| Repository | Missing group doc pairs for Where and Ledger | [Root P1](TODOs.md) |

The benchmark organization cleanup remains open after the saved September 9
plan-downgrade date. `gh repo view` confirms the repository exists and is not
archived on October 5. Actual downgrade, billing, and installed integrations
remain unverified; no deletion or billing action was taken.

## Cross-cutting themes

- **Raw observations and effective history have different consumers.** Flight
  review and backups retain evidence; reports and maps apply current attribution.
  Documentation that says every raw point contributes is now misleading.
- **Shared policy can resolve an older layering request.** The primary-region
  helper fulfills headless scanning without moving presentation containers.
- **Actionable counts do not describe all review states.** Pending flight
  evidence appears in Resolve without incrementing the badge; discovery content
  must account for that distinction.
- **Asynchronous assertions must distinguish outcomes.** The existing location
  waiter's registration gap and history test's termination gap remain separate
  coverage issues, not reproduced failures in this run.
- **Readiness, cost, and inventory are separate evidence.** The 71 raised-floor
  configurations do not update the historical 260-reference timing experiment.
  More correction-history reads warrant profiling, not an invented latency claim.

## Module inventory and Verified OK

Counts are tracked `.swift` files under each module's `Sources/`, `Tests/`, and
`SnapshotTests/`; tests include fixtures/support and do not equal test cases.
All **27 leaf modules** have both README.md and AGENTS.md. Results below are
static unless explicitly identified as executed. Shared and Ledger source files
are unchanged in this review window.

| Module | Source | Test/support | Image suite | Verified OK / bounded result |
|---|---:|---:|---:|---|
| [Ledger](Ledger/Ledger/README.md) | 8 | 0 | — | Native macOS app and hostless LedgerCore scheme remain separate from iOS; app has no test bundle by design. |
| [LedgerCore](Ledger/LedgerCore/README.md) | 16 | 14 | — | Explicit refresh-generation guard and scripted API/Keychain seams retained; 14 test/support files, with the three filed namesake gaps. |
| [BroadwayCatalog](Shared/Broadway/BroadwayCatalog/README.md) | 2 | 1 | — | Catalog target is in the iOS scheme; its placeholder and empty test are still accurately filed, not counted as behavior coverage. |
| [BroadwayCore](Shared/Broadway/BroadwayCore/README.md) | 18 | 12 | — | BScaledDimension uses explicit category metrics; category round-trip and ambient-trait independence tests are present. Cache and unchanged-value gaps remain. |
| [BroadwayUI](Shared/Broadway/BroadwayUI/README.md) | 6 | 4 | — | Depends downward on BroadwayCore; nested-observer TODO remains at the cited source. |
| [CreditKit](Shared/CreditKit/README.md) | 2 | 3 | — | Foundation-only value layer; attribution report passes at 12 credits. Generator slug issue remains localized to parsing. |
| [Flyover](Shared/Flyover/README.md) | 54 | 14 | 1 | Manifest has no Where dependency; 14 test/support files and one image suite remain. Canvas math coverage is distinct from interactive coverage. |
| [Inspector](Shared/Inspector/README.md) | 23 | 14 | 1 | One image suite has four references; relationship branch and three silent fetch defaults still match the backlog. |
| [JournalKit](Shared/JournalKit/README.md) | 2 | 3 | — | Concurrent append test checks recovered count, uniqueness, and writer order; swallowed error diagnostic is the actual remaining gap. |
| [LifecycleKit](Shared/LifecycleKit/README.md) | 8 | 10 | — | Duplicate-ID precondition is present; existing test files still cover typed launch and cancellation. Duplicate-ID exit-test gap remains. |
| [LifecycleKitUI](Shared/LifecycleKitUI/README.md) | 6 | 4 | — | Gate-registration uniqueness guard remains present; view-level splash ownership is unchanged. |
| [PeriscopeCore](Shared/Periscope/PeriscopeCore/README.md) | 38 | 33 | — | Span accessors downcast rather than store parallel span fields; journal still installs with the store. No new source in the window. |
| [PeriscopeTools](Shared/Periscope/PeriscopeTools/README.md) | 27 | 27 | 1 | Hierarchy count/query asymmetry is explicitly pinned; 20 hosting-only assertions across 10 files and two image references remain. |
| [PeriscopeUI](Shared/Periscope/PeriscopeUI/README.md) | 1 | 2 | — | Single SwiftUI environment adapter imports only PeriscopeCore and SwiftUI; test/support inventory unchanged. |
| [SnapshotKit](Shared/SnapshotKit/README.md) | 8 | 3 | — | Shippable matrix remains separate from comparison engine; docs continue to disclose that the runner shares captured models across configurations. |
| [SnapshotKitTesting](Shared/SnapshotKitTesting/README.md) | 16 | 16 | — | Provider duplicate guard, cancellation outcome, parse failure paths and config loop match filed issues; shard plan validates all 56 suites. |
| [StuffTestHost](Shared/StuffTestHost/README.md) | 2 | 0 | — | UIKit shell delegates test-window setup to TestHostSupport; no WhereCore import or new source. |
| [TestHostSupport](Shared/TestHostSupport/README.md) | 1 | 0 | — | UIKit/Objective-C hosting seam remains app-independent; host smoke contract is exercised from LifecycleKit tests. |
| [RegionKit](Where/RegionKit/README.md) | 15 | 10 | — | GeoJSON decoding gap is honestly documented; source still throws for unsupported geometry. No new source in the window. |
| [RegionViewer](Where/RegionViewer/README.md) | 1 | 0 | — | Bundled per-region data description remains correct; missing Broadway root is still filed in Where. |
| [Where](Where/Where/README.md) | 9 | 5 | — | Audience selection validates compiler condition against plist metadata and injects one environment into launch and intents; hosted tests select the in-memory/no-op path. |
| [WhereCore](Where/WhereCore/README.md) | 148 | 97 | — | Raw flight evidence stays separate from effective attribution; exact-sample correction proposals are revalidated under the generation guard. Scanner retains informational reviews separately from actionable issues. Backup v6 retains motion and revision history. |
| [WhereCrashReporting](Where/WhereCrashReporting/README.md) | 3 | 2 | — | Capture SDK stays behind the dedicated adapter target; no source, dependency, or test changes in this window. |
| [WhereIntents](Where/WhereIntents/README.md) | 15 | 9 | — | Injected audience group reaches the snapshot reader; App Group-open failure is logged before report fallback. README states the perform-glue testing limitation. |
| [WhereShareExtension](Where/WhereShareExtension/README.md) | 6 | 0 | — | Extension validates its audience and uses local-only storage in that audience’s App Group. Pending-evidence construction and the filed form/testing gaps are unchanged. |
| [WhereUI](Where/WhereUI/README.md) | 321 | 124 | 53 | Scene scan publication rejects superseded requests; pending-flight reviews remain visible without an actionable count. Map geometry budgets bound pins and route points. Gallery forms have named body boundaries and size guards. |
| [WhereWidgets](Where/WhereWidgets/README.md) | 8 | 0 | — | Audience-specific group is injected into both snapshot and presentation stores; provider retains the midnight reload policy without opening the app’s SwiftData store. |

**Totals:** 764 source, 407 test/support, and 56 image-suite Swift files.
Inventory excludes two unwired Periscope journal-benchmark sources and four
Bumper rule/test files. Manifests still declare 20 library targets, seven
app/extension targets, and 25 test bundles: 20 unit bundles in Stuff-iOS-Tests,
LedgerCoreTests in Ledger-macOS-Tests, and four image bundles in StuffSnapshotTests.
The package change excludes scoped AGENTS files from source discovery; the
iOS 27 / macOS 26 deployment split is unchanged.

**References:** 736 WhereUI, five Flyover, four Inspector, two PeriscopeTools:
747 total, up by 172. Shard validation passes with assignments 13 / 15 / 18 plus
ten on the intake shard. WhereCore's basename coverage proxy is 69 of 148 sources
without a namesake test, previously 61 of 132; this is not a count of untested
behaviors.

**Group docs:** Broadway and Periscope have both docs; Where lacks its group
README and Ledger lacks both group docs. Their leaves are complete. The existing
root item remains open.

**Bumper and tooling:** there are ten `where.*` rules and twelve source-rule
test functions, including the added sample-attribution transaction-boundary test.
The explicit Calendar filter and mutation fixtures still miss 11 implicit calendar
sites in Sources (four production, seven DEBUG fixtures). Graph mutation coverage
still covers component boundaries and forbidden imports, not duplicate ownership
or declared cycles. Source inspection supports those statements; architecture
execution was not rerun.

## Verification and limitations

- `./swiftformat --lint` — passed, 0 of 1,234 files require formatting;
  128 skipped. Its optional cache write was sandbox-blocked without changing
  the lint result.
- `./shellcheck` — passed.
- `./attribution --check` — passed, 12 credits current.
- `./sf-symbols --lint` — passed.
- `./xcstrings --lint` — passed, seven catalogs match Xcode serialization;
  rerun with compiler-cache access after the sandbox blocked that cache.
- `./snapshot-shards check` — passed, all 56 suites assigned.
- `./sync-agents` and `git diff --check` — passed; generated mirrors are ignored.
- This host is **macOS**; this audit remains **static analysis** plus the
  supported checks above. The skill's Linux limitations remain: Linux cannot
  run Tuist, Xcode, or simulator validation. No runtime suite is implied.
- `./test`, architecture execution, image/simulator suites, and retained
  Python/Ruby tests were skipped for Markdown-only edits. No executable,
  dependency, matrix, reference, or rendered-copy change was made. Module
  instruction edits describe existing seams; they introduce no concurrency
  boundary. Existing Linux portability findings were not reproduced or closed.
- No fresh screenshots, animations, VoiceOver sessions, live scroll/year-switch
  gestures, device checks, or performance measurements were performed. Prior PR
  validation remains historical. Inspector's quarantine and filed layout defects
  remain open.
- CloudKit readiness/delivery/convergence, passive background location,
  multi-process journals, runtime logging isolation, billing, and Ledger
  API/Keychain behavior were not exercised. Historical performance and spike
  results retain their original environment limits.
