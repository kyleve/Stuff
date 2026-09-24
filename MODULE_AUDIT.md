# Swift Module Audit Report

**Date:** September 21, 2026
**Reviewed source:** `a32b8b05` (PR #318), fetched from `origin/main`.
**Prior audit:** September 7, 2026, report merged in PR #313 (`c62c1afb`), whose stated source coverage ended at PR #311 (`5f65b9f0`).

This report is derived from all 12 `TODOs.md` files and carries no actionable
items. The root [`TODOs.md`](TODOs.md) owns their format and placement. This
report is true as of the header date and source boundary, not as of later HEADs.

## Method and changes since the previous audit

The pass read every open area backlog, checked current cited source and test
seams, reviewed changes from the covered source boundary to current main, and
enumerated tracked sources, tests, references, module docs, and manifest wiring.
Unchanged areas were checked against their cited mechanisms and the unchanged
source diff; this was not a new line-by-line review of all 717 source files.
Exploratory directions remain decisions rather than being promoted to bugs.

The commit window is `5f65b9f0..a32b8b05`: PR #313's audit, PR #174's audience
builds, PR #314's foreground welcome and current-location confidence flow, and
PR #318's iOS 27 minimum. It includes changes since the previous report even
though the scheduled automation also lists a September 14 run. Feature PR bodies
were read to distinguish reported validation from this pass's own checks.
PR #319's HistoryObserver work is open, not merged, at this audit boundary.

| Area | September 7 report | September 21 state |
|---|---|---|
| Source / test-support / image-suite files | 709 / 371 / 49 | **717 / 374 / 50** |
| WhereCore | 129 / 84 | **132 / 86**; typed location outcomes, confidence telemetry, and fake-driver tests |
| WhereUI | 289 / 104 | **291 / 104**; app-shell welcome/accessory state replaces tab-local ownership |
| App / share extension / widgets sources | 8 / 5 / 7 | **9 / 6 / 8**; audience environments added |
| Reference images | 495 | **506**; 16 MainTabs references replace five Locations welcome references |
| Module / test bundle count | 27 / 25 | **27 / 25**, unchanged |
| Inbox | Empty | **Empty**; no notes to promote or decline |
| Backlog | Partial requests and stale claims | **One item archived**, one test synchronization finding filed; partial requests narrowed |
| Deployment / build selection | iOS 26; single Where audience | **iOS 27**; Development, Beta, and App Store audiences; macOS remains 26 |

The per-intent `perform()` testing item is archived through its documented-
limitation option: the README now agrees with the existing agent guidance.
No new intent runtime coverage is claimed. Foreground welcome refresh was
already archived by PR #314; its completion reference is corrected here.
The persistent current-region marker remains a separate product decision.
Welcome semantic captures now exist, while scrolling, iPad, and first-greeting
coverage remain open. The intent App Group-open logging subtask shipped in
PR #174; the widget stores' separate silent file-read failures remain open.

Documentation now admits the injected-driver exception to the CoreLocation
unit-test prohibition, locates welcome ownership in the app shell, and points
to this derived report for the current snapshot inventory. The Linux section
no longer attributes all portability failures to a missing Ruby. Backlog
citations follow the new manifests, and the CI recipe item no longer claims
that `./test --everything` omits architecture validation.

## New-surface review

**Verified OK in source and existing tests:** audience descriptors centralize
bundle IDs, App Groups, primary icons, configuration, and host compiler
conditions. The app validates the condition/plist selection and injects storage,
group, widget refresher, and icon selection from one environment. Development
uses its isolated local store; Beta and App Store share the production family.
The share extension uses local-only access to its matching group, and widgets
read published stores from that group. Hosted app tests use in-memory storage
and a no-op refresher. The icon tool guards every configured primary asset.
CircleCI now contains two release-audience build-only shards alongside the
existing simulator test pipeline; this pass did not run those builds.

The current-location source has explicit idle/pending request state, coalesces
waiters, stops the request when its final waiter cancels, and checks request
identity when timing out. Stale or negative-accuracy callbacks do not complete
a request. Its fake-driver tests cover reduced precision, denied authorization,
provider failure, timeout, cancellation, retry, and synchronous completion.
`CurrentRegionResolver` checks recording authority before and after suspension,
rejects fixes older than 60 seconds or worse than 1 km accuracy, and requires
accuracy to fit within the region-boundary distance. Telemetry uses bounded
outcome and accuracy categories. These are source/test-inspection results.

`MainTabs` keys welcome lookup to scene activity and the enabled preference,
independently of selected tab. The model rejects cancellation and stale request
sequences and persists acknowledgement only on dismissal. The accessory can
surface a retry/status action. The modal hides underlying tabs from accessibility,
and the four app-shell image cases include semantic captures. Existing tests
exercise the model's cancellation, confidence/status, acknowledgement, and
repeat-resolution paths. Live lifecycle delivery, VoiceOver focus, and animation
were not exercised in this pass.

**Filed:** the new coalesced-waiter cancellation test waits for one system
request, which does not prove both callers have registered. Its scheduling
assumption and unbounded yield helper are recorded in the Where P2 backlog.
This is a static synchronization finding, not a reproduced CI failure.

## Top findings

Pointers only; evidence and proposed fixes live in the backlog.

| Area | Finding | Backlog |
|---|---|---|
| Bumper | Gregorian rule misses implicit `.current` | [Root P0](TODOs.md) |
| WhereCore | Daily summary absent from local fan-out | [Where P0](Where/TODOs.md) |
| PeriscopeCore | Pre-store-attach records absent from durable log | [Periscope P0](Shared/Periscope/TODOs.md) |
| WhereUI | Four production Gregorian-calendar defaults/helpers remain | [Where P1](Where/TODOs.md) |
| WhereCore | Picker fan-out and hard-deleting untracked regions | [Where P1](Where/TODOs.md) |
| WhereUI | Launch-time notification permission prompt | [Where P1](Where/TODOs.md) |
| SnapshotKit | Captured models shared across configurations | [SnapshotKit P1](Shared/SnapshotKit/TODOs.md) |
| WhereCore tests | Coalesced cancellation lacks a two-waiter handshake | [Where P2](Where/TODOs.md) |
| WhereUI snapshots | Welcome scrolling, iPad, and first-greeting gaps | [Where P2](Where/TODOs.md) |
| CI / scripts | Serial-axis documentation and Linux portability gaps | [Root P1](TODOs.md) |
| Repository | Missing group doc pairs for Where and Ledger | [Root P1](TODOs.md) |

The benchmark organization cleanup remains open after the saved **September 9**
plan-downgrade date. `gh repo view` confirms the benchmark repository still
exists and is not archived on September 21. The actual downgrade, billing, and
installed integrations were not independently verified; no deletion or billing
action was taken.

## Cross-cutting themes

- **Partial completion needs a precise remainder.** The iOS uplift is shipped,
  HistoryObserver is pending, semantic welcome captures exist, and the matrix
  still lacks other coverage. Original priorities and origins are preserved.
- **Injection makes a test seam possible, not automatically deterministic.**
  The fake location driver avoids live requests; the cancellation test still
  needs to establish its two-waiter precondition before testing it.
- **Opening a store and reading a file are different failure boundaries.**
  The intent now logs group-open failure; the widget stores' read defaults
  remain a separate visibility gap.
- **Model tests and image references establish different facts.** Neither
  establishes live scene delivery, scroll reachability, or VoiceOver focus.
- **Keep historical performance measurements historical.** There are now
  506 references and 43 raised-floor configurations; neither count refresh
  remeasures the 260-reference timing experiment or proves a floor removable.

## Module inventory and Verified OK

Counts are tracked `.swift` files under each module's `Sources/`, `Tests/`, and
`SnapshotTests/`; tests include fixtures/support files and do not equal test
cases. All **27 leaf modules** have both README.md and AGENTS.md. The following
checks are static unless explicitly identified as executed.

| Module | Source | Test/support | Image suite | Verified OK / bounded result |
|---|---:|---:|---:|---|
| [Ledger](Ledger/Ledger/README.md) | 8 | 0 | — | Native macOS app and hostless LedgerCore scheme remain separate from iOS; app has no test bundle by design. |
| [LedgerCore](Ledger/LedgerCore/README.md) | 16 | 14 | — | Explicit refresh-generation guard and scripted API/Keychain seams retained; 14 test/support files, with the three filed namesake gaps. |
| [BroadwayCatalog](Shared/Broadway/BroadwayCatalog/README.md) | 2 | 1 | — | Catalog target is in the iOS scheme; its placeholder and empty test are still accurately filed, not counted as behavior coverage. |
| [BroadwayCore](Shared/Broadway/BroadwayCore/README.md) | 17 | 10 | — | Cache and unchanged-value invalidation sites match the existing backlog; manifest remains free of app dependencies. |
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
| [SnapshotKitTesting](Shared/SnapshotKitTesting/README.md) | 16 | 16 | — | Provider duplicate guard, cancellation outcome, parse failure paths and config loop match filed issues; shard plan validates all 50 suites. |
| [StuffTestHost](Shared/StuffTestHost/README.md) | 2 | 0 | — | UIKit shell delegates test-window setup to TestHostSupport; no WhereCore import or new source. |
| [TestHostSupport](Shared/TestHostSupport/README.md) | 1 | 0 | — | UIKit/Objective-C hosting seam remains app-independent; host smoke contract is exercised from LifecycleKit tests. |
| [RegionKit](Where/RegionKit/README.md) | 15 | 10 | — | GeoJSON decoding gap is honestly documented; source still throws for unsupported geometry. No new source in the window. |
| [RegionViewer](Where/RegionViewer/README.md) | 1 | 0 | — | Bundled per-region data description remains correct; missing Broadway root is still filed in Where. |
| [Where](Where/Where/README.md) | 9 | 5 | — | Audience selection validates compiler condition against plist metadata and injects one environment into launch and intents; hosted tests select the in-memory/no-op path. |
| [WhereCore](Where/WhereCore/README.md) | 132 | 86 | — | Resolver rechecks authority after suspension and gates freshness, accuracy, and boundary confidence; fake-driver tests cover explicit one-shot outcomes. The new synchronization finding concerns test orchestration. |
| [WhereCrashReporting](Where/WhereCrashReporting/README.md) | 3 | 2 | — | Capture SDK stays behind the dedicated adapter target; no source, dependency, or test changes in this window. |
| [WhereIntents](Where/WhereIntents/README.md) | 15 | 9 | — | Injected audience group reaches the snapshot reader; App Group-open failure is logged before report fallback. README now states the perform-glue testing limitation. |
| [WhereShareExtension](Where/WhereShareExtension/README.md) | 6 | 0 | — | Extension validates its audience and uses local-only storage in that audience’s App Group. Pending-evidence construction and the filed form/testing gaps are unchanged. |
| [WhereUI](Where/WhereUI/README.md) | 291 | 104 | 47 | MainTabs keys welcome lookup to active scene + enabled preference; model guards stale sequences and dismissal-only acknowledgement. Modal hides underlying tab accessibility; matrix now includes semantic captures. |
| [WhereWidgets](Where/WhereWidgets/README.md) | 8 | 0 | — | Audience-specific group is injected into both snapshot and presentation stores; provider retains the midnight reload policy without opening the app’s SwiftData store. |

**Totals:** 717 source, 374 test/support, and 50 image-suite Swift files.
The inventory excludes two unwired Periscope journal-benchmark sources and
four Bumper rule/test files. `Package.swift` declares 20 library targets;
`Project.swift` declares seven app/extension targets and 25 test bundles:
20 unit bundles in `Stuff-iOS-Tests`, LedgerCoreTests in `Ledger-macOS-Tests`,
and four image bundles in `StuffSnapshotTests`. Manifest changes add audience
configuration and raise the iOS minimum, without adding test bundles.

**References:** 495 WhereUI, five Flyover, four Inspector, two PeriscopeTools,
for 506 total. The 50 suites retain assignments 13 / 15 / 18 plus four on the
intake shard. The shard validator passes. WhereCore's basename coverage proxy
is 61 sources without a namesake test among 132 sources, previously 60 of 129.
Logging types and record shells mean this is not a count of untested behaviors.
The coalesced-source and resolver-log tests add namesake coverage; two new typed
location outcomes are tested through consumers rather than namesake files.

**Group docs:** Broadway and Periscope have both docs; Where lacks its group
README and Ledger lacks both group docs. Their leaf modules are complete.
The existing root item remains open.

**Bumper and tooling:** the ten `where.*` rules and eleven source-rule test
functions remain; the explicit-calendar filter and mutation fixtures still
miss the 12 implicit calendar sites (four production, eight DEBUG fixtures).
`component_boundary` and `forbidden_import` have mutation tests; the other two
graph assertions remain filed for missing mutation coverage. This is source
inspection, not a fresh architecture execution. The icon tooling now understands
audience primaries, CircleCI has release build shards, and the snapshot renderer
pin changed in PR #314. Retained tooling suites were not rerun for this audit's
documentation-only edits.

## Verification and limitations

- `./swiftformat --lint` — passed, 0 of 1,148 files require formatting;
  125 skipped. The sandbox prevented writing its optional cache without
  affecting the lint result.
- `./shellcheck` — passed.
- `./attribution --check` — passed, 12 credits current.
- `./snapshot-shards check` — passed, all 50 suites assigned.
- `./sync-agents` — passed after instruction edits; generated mirrors remain
  ignored. `git diff --check` — passed.
- This run is on **macOS**, but the audit remains **static analysis** plus the
  supported host checks above. The skill's Linux limitations still apply to
  Linux runs: no Tuist, Xcode, simulator, or runtime validation is implied.
- `./test`, architecture execution, simulator/image suites, and retained
  Python/Ruby suites were skipped because this change is Markdown and Swift
  comments only. There are no executable, matrix, reference, or rendered-copy
  changes. Prior PR test counts are historical evidence, not this run's results.
  Existing Linux/tool-portability findings were not reproduced or closed.
- No fresh screenshots or live animations were inspected. Existing visual
  defects and the Inspector/Elsewhere quarantines remain open; the new welcome
  still needs device/simulator validation for lifecycle, focus, and scrolling.
- CloudKit readiness, passive background delivery, multi-process journals,
  runtime diagnostic routing, and Ledger's live API/Keychain behavior were not
  exercised. Historical timing/spike conclusions remain conditional on their
  stated measurement environment.
