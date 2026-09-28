# Swift Module Audit Report

**Date:** September 28, 2026
**Reviewed source:** `e15577ad` (PR #326), fetched from `origin/main`.
**Prior audit:** September 21, 2026, report merged in PR #321 (`1675151c`), whose stated source coverage ended at PR #318 (`a32b8b05`).

This report is derived from all 12 `TODOs.md` files and carries no actionable
items. The root [`TODOs.md`](TODOs.md) owns their format and placement. This
report is true as of the header date and source boundary, not as of later HEADs.

## Method and changes since the previous audit

The pass read every open area backlog, checked cited source/test mechanisms,
reviewed the covered-source commit window and merged PR descriptions, and
recounted tracked sources, tests, reference images, module doc pairs, and target
wiring. Unchanged areas were checked against their cited seams and unchanged
diffs; this was not a fresh line-by-line review of all 731 sources. Historical
spikes and runtime observations remain historical, not newly reproduced facts.

The source window is `a32b8b05..e15577ad`: the prior audit (#321), HistoryObserver
(#319), Elsewhere passport card (#322), stylesheet slicing (#323), Locations
background (#324), shared artwork loading (#325), and Explore Features (#326).
GitHub merge metadata confirms all seven PRs landed. Descriptions supplied
intent and prior validation; their test counts are not results from this run.

| Area | September 21 report | September 28 state |
|---|---|---|
| Source / test-support / image-suite files | 717 / 374 / 50 | **731 / 382 / 55** |
| BroadwayCore | 17 / 10 | **18 / 12**; explicit-category scaling and category conversion tests |
| WhereCore | 132 / 86 | **132 / 86**; remote-change source replaced in place |
| WhereUI | 291 / 104 / 47 suites | **304 / 110 / 52 suites**; artwork and gallery additions |
| Reference images | 506 | **575**, including 564 WhereUI references |
| Module / test bundle count | 27 / 25 | **27 / 25**, unchanged |
| Inbox | Empty | **Empty**; no notes to promote or decline |
| Backlog | Partial iOS uplift and Timeline coverage | **Two items archived**, one source-test finding filed; other priorities retained |
| Raised-floor configurations | 43 | **55**; all seven Locations cases now have a one-second floor |

The originating iOS 27 / HistoryObserver request is archived with both shipping
PRs. The joined Timeline row's AX5 coverage item is archived through the new
Places & Year gallery: it renders the production shared rows with the same
planned-stay fixture in the full-content phone/tablet matrix. The dedicated
full Timeline PlannedStay case still lacks its own AX5 configuration; the
closure is about shared row rendering, not full-screen scroll validation.

PR #322 had already archived the Elsewhere localization and broken-reference
items. Inspector now accurately records the only remaining `withKnownIssue`
quarantine. The Gregorian item credits Timeline's newly explicit calendar while
retaining the four implicit definitions. The loading-gate item distinguishes
the gallery's honest unavailable state from the full Timeline's empty fallback.
The rosette profiling item now includes the full-viewport background without
claiming a measured performance regression. Moved citations and snapshot counts
were refreshed; historical timing numbers were not recalculated.

Documentation now describes the share extension's HistoryObserver refresh path
and untested extension glue, the group's isolated location/history test seams,
and the Estimated Time gallery's intentional grayscale examples while Off.
The week's Core and Broadway API documentation, stylesheet slicing guide, and
Explore Features ownership already match their new implementation. No target
or build/test flow changed in this window, so no new root contract edit was
needed. Agent mirrors were synchronized after the module instruction edits.

## New-surface review

**Verified OK in source and existing tests:** HistoryObserver is scoped to the
opened ModelContainer. Persistent-history classification continues to suppress
the store instance's author, and a startup catch-up follows observer setup.
Both streams coalesce candidates; classification failure logs and forwards a
refresh. Deinitialization cancels the observation and classification tasks and
finishes the streams. Six tests cover scripted delivery, external same-file
writes, the baseline/setup interval, local author rejection, unrelated stores,
and source release. They use isolated temporary containers without CloudKit.
Live CloudKit delivery remains outside this pass.

The new lifetime test checks source deallocation, but its helper gives timeout
and stream completion the same result. That assertion gap is filed in the
Where P2 backlog. No production leak or failed runtime run was observed.

`BScaledDimension` resolves against an explicit content-size category rather
than ambient traits. Existing tests compare system metrics and all 12 category
round trips. Where's stylesheet selects component layout, compact copy, motion,
and appearance policies; RootView now reads those policies beneath its own
Broadway root. Scoped widget/theme overrides align SwiftUI and Broadway traits.
Live launch and ranking transitions were not replayed.

The Elsewhere card uses one ordered secondary-region list for count and artwork,
localized plural forms, separate silhouettes, and a catch-all globe. Locations
background membership uses visited geographic regions in catalog order, omits
Other, and hides decorative ink for Reduce Transparency. Layout tests cover
stagger, overscan, full membership, and separate silhouette cells. These source
checks do not replace visual review of the new references.

`RegionArtworkModel` separates request identity from display compatibility and
rejects cancelled or superseded results with a unique token. The shared modifier
includes cache identity and display key in its task identity. Tests cover stale
keys, overlapping same-key work, retained artwork, cancellation, cache replacement,
and cache removal. Region cards keep compatible outlines during point refreshes.

Explore Features now has nine destinations. New galleries are read-only at the
browsing boundary, use explicit links into existing editors, pass process-effective
diagnostics, and suppress demo-unavailable links. The shared Timeline excerpt
uses the production row/join builder and passes the report calendar explicitly.
Empty and unavailable history are distinguished in excerpts, and zero issue
count no longer claims a completed all-clear scan. New gallery matrices cover
phone/tablet, AX5, semantic accessibility, and relevant empty/denied/demo states.
The existing widget-family and evidence walkthrough semantic issues remain open.

## Top findings

Pointers only; evidence and proposed fixes live in the backlog.

| Area | Finding | Backlog |
|---|---|---|
| Bumper | Gregorian rule misses implicit `.current` | [Root P0](TODOs.md) |
| WhereCore | Daily summary absent from local fan-out | [Where P0](Where/TODOs.md) |
| PeriscopeCore | Pre-store-attach records absent from durable log | [Periscope P0](Shared/Periscope/TODOs.md) |
| WhereUI | Four production Gregorian defaults/helpers remain | [Where P1](Where/TODOs.md) |
| WhereCore | Picker fan-out and hard-deleting untracked regions | [Where P1](Where/TODOs.md) |
| WhereUI | Full Timeline still lacks a report loading gate | [Where P1](Where/TODOs.md) |
| WhereUI | Launch-time notification permission prompt | [Where P1](Where/TODOs.md) |
| SnapshotKit | Captured models shared across configurations | [SnapshotKit P1](Shared/SnapshotKit/TODOs.md) |
| WhereCore tests | History-source termination conflated with timeout | [Where P2](Where/TODOs.md) |
| WhereUI snapshots | Welcome scrolling, iPad, and first-greeting gaps | [Where P2](Where/TODOs.md) |
| CI / scripts | Serial-axis documentation and Linux portability gaps | [Root P1](TODOs.md) |
| Repository | Missing group doc pairs for Where and Ledger | [Root P1](TODOs.md) |

The benchmark organization cleanup remains open after the saved September 9
plan-downgrade date. `gh repo view` confirms the repository exists and is not
archived on September 28. Actual downgrade, billing, and installed integrations
remain unverified; no deletion or billing action was taken.

## Cross-cutting themes

- **Credit the shipped boundary precisely.** HistoryObserver replaces the
  remote-change bridge, not the separate CloudKit onboarding-readiness observer.
  Timeline gallery coverage executes shared rows without proving full-screen
  scrolling. Original priorities and origins remain intact.
- **Sharing UI can close coverage gaps.** The new gallery exercises the real
  joined-row builder. A duplicate illustration would not provide that coverage.
- **Asynchronous assertions must distinguish outcomes.** The older location
  test's waiter-registration gap and the new history test's termination gap
  concern different preconditions; neither is a reproduced CI failure.
- **Readiness and timing remain separate.** Cache warming, model publication,
  and native glass adaptation are different events. The 55 raised-floor count
  does not update the historical 260-reference timing experiment.
- **Documentation must follow consumers too.** The Core HistoryObserver docs
  were current, while the extension still described the removed bridge.

## Module inventory and Verified OK

Counts are tracked `.swift` files under each module's `Sources/`, `Tests/`, and
`SnapshotTests/`; tests include fixtures/support and do not equal test cases.
All **27 leaf modules** have both README.md and AGENTS.md. Results below are
static unless explicitly identified as executed.

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
| [SnapshotKitTesting](Shared/SnapshotKitTesting/README.md) | 16 | 16 | — | Provider duplicate guard, cancellation outcome, parse failure paths and config loop match filed issues; shard plan validates all 55 suites. |
| [StuffTestHost](Shared/StuffTestHost/README.md) | 2 | 0 | — | UIKit shell delegates test-window setup to TestHostSupport; no WhereCore import or new source. |
| [TestHostSupport](Shared/TestHostSupport/README.md) | 1 | 0 | — | UIKit/Objective-C hosting seam remains app-independent; host smoke contract is exercised from LifecycleKit tests. |
| [RegionKit](Where/RegionKit/README.md) | 15 | 10 | — | GeoJSON decoding gap is honestly documented; source still throws for unsupported geometry. No new source in the window. |
| [RegionViewer](Where/RegionViewer/README.md) | 1 | 0 | — | Bundled per-region data description remains correct; missing Broadway root is still filed in Where. |
| [Where](Where/Where/README.md) | 9 | 5 | — | Audience selection validates compiler condition against plist metadata and injects one environment into launch and intents; hosted tests select the in-memory/no-op path. |
| [WhereCore](Where/WhereCore/README.md) | 132 | 86 | — | HistoryObserver is container-scoped, retains author filtering and startup catch-up, and tears down both tasks. Six source tests include real temporary-store writes; lifetime termination assertion is now filed as a coverage gap. |
| [WhereCrashReporting](Where/WhereCrashReporting/README.md) | 3 | 2 | — | Capture SDK stays behind the dedicated adapter target; no source, dependency, or test changes in this window. |
| [WhereIntents](Where/WhereIntents/README.md) | 15 | 9 | — | Injected audience group reaches the snapshot reader; App Group-open failure is logged before report fallback. README now states the perform-glue testing limitation. |
| [WhereShareExtension](Where/WhereShareExtension/README.md) | 6 | 0 | — | Extension validates its audience and uses local-only storage in that audience’s App Group. Pending-evidence construction and the filed form/testing gaps are unchanged. |
| [WhereUI](Where/WhereUI/README.md) | 304 | 110 | 52 | Artwork model rejects superseded/cancelled results; modifier keys cache identity. Galleries reuse production Timeline rows, pass effective diagnostics, and hide unavailable demo links. Trait policies resolve in stylesheet slices. |
| [WhereWidgets](Where/WhereWidgets/README.md) | 8 | 0 | — | Audience-specific group is injected into both snapshot and presentation stores; provider retains the midnight reload policy without opening the app’s SwiftData store. |


**Totals:** 731 source, 382 test/support, and 55 image-suite Swift files.
Inventory excludes two unwired Periscope journal-benchmark sources and four
Bumper rule/test files. Unchanged manifests declare 20 library targets, seven
app/extension targets, and 25 test bundles: 20 unit bundles in Stuff-iOS-Tests,
LedgerCoreTests in Ledger-macOS-Tests, and four image bundles in StuffSnapshotTests.
The iOS 27 / macOS 26 deployment split is unchanged.

**References:** 564 WhereUI, five Flyover, four Inspector, two PeriscopeTools:
575 total. Shard validation passes with assignments 13 / 15 / 18 plus nine on
the intake shard. WhereCore's basename coverage proxy remains 61 of 132 sources
without a namesake test; this is not a count of untested behaviors.

**Group docs:** Broadway and Periscope have both docs; Where lacks its group
README and Ledger lacks both group docs. Their leaves are complete. The existing
root item remains open.

**Bumper and tooling:** the ten `where.*` rules and eleven source-rule test
functions remain. The explicit Calendar filter and mutation fixtures still miss
12 implicit calendar sites in Sources (four production, eight DEBUG fixtures).
Graph mutation coverage still covers component boundaries and forbidden imports,
not duplicate ownership or declared cycles. Source inspection and unchanged
diffs support those statements; architecture execution was not rerun.

## Verification and limitations

- `./swiftformat --lint` — passed, 0 of 1,175 files require formatting;
  125 skipped. Its optional cache write was sandbox-blocked without changing
  the lint result.
- `./shellcheck` — passed.
- `./attribution --check` — passed, 12 credits current.
- `./sf-symbols --lint` — passed.
- `./xcstrings --lint` — passed, seven catalogs match Xcode serialization;
  rerun with compiler-cache access after the sandbox blocked that cache.
- `./snapshot-shards check` — passed, all 55 suites assigned.
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
  gestures, or device checks were performed. Prior PR validation remains
  historical. The Inspector quarantine and filed layout defects remain open.
- CloudKit readiness/delivery, passive background location, multi-process
  journals, runtime logging isolation, billing, and Ledger API/Keychain behavior
  were not exercised. Historical performance and spike results retain their
  original environment limits.
