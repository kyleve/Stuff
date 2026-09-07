# Swift Module Audit Report

**Date:** September 7, 2026
**Reviewed source:** `5f65b9f0` (PR #311), fetched from `origin/main`.
**Prior audit:** September 6, 2026, report merged in PR #310 (`1f6162ba`), whose stated source coverage ended at PR #307 (`1e9c9289`).

This report is derived from all 12 `TODOs.md` files and carries no actionable
items. The root [`TODOs.md`](TODOs.md) owns their format and placement. This
report is true as of the header date and source boundary, not as of later HEADs.

## Method and changes since the previous audit

The pass read every open area backlog, checked cited current source and test
seams, compared the covered source boundary with current main, and enumerated
tracked sources, tests, references, module docs, and manifest wiring. Unchanged
areas were checked against their current cited mechanisms and the unchanged
source diff; this was not a fresh line-by-line review of all 709 source files.
Exploratory directions remain decisions, rather than being promoted to bugs.

The commit window is `1e9c9289..5f65b9f0`: PR #309's welcome feature, PR #310's
audit/documentation changes, and PR #311's welcome motion/reset changes. The
prior report missed #309 even though it was already an ancestor of that report's
merge. Both feature PR bodies were read to distinguish intent and reported
validation from what this pass itself verified.

| Area | Prior report | September 7 state |
|---|---|---|
| Source / test-support / image-suite files | 704 / 369 / 49 | **709 / 371 / 49** |
| WhereCore | 128 / 83 | **129 / 84**; resolver and namesake tests added |
| WhereUI | 285 / 103 | **289 / 104**; four welcome types and model tests added |
| Reference images | 490 | **495**; five welcome references added, ten Appearance references updated |
| Module / test bundle count | 27 / 25 | **27 / 25**, unchanged |
| Inbox | Empty | **Empty**; no notes to promote or decline |
| Backlog | Some shipped/overstated claims still open | **Three entries archived**, two welcome findings filed; partial requests and citations corrected |
| Documentation | Reconciliation and snapshot-isolation overclaims | Current behavior and remaining exceptions explicitly documented |

The three archived entries are logged-in/out scope modeling (shipped via
PR #150), local ingest/manual-sample fan-out (shipped August 4), and the stale
WhereCore documentation cluster corrected in this pass. The missing daily
summary and picker fan-outs remain open. The current-location UI request is
partly fulfilled by #309; its persistent-marker decision remains open.

Other corrections distinguish actual consequences from inherited claims:
JournalKit's append test detects missing records but loses the original error;
WhereModel already has a typed log-store state; accessibility parse failure can
kill the current bundle's host, not every bundle's host; Ledger has 14
test/support files; RegionKit's README already admits its decoding-test gap;
and the tool-portability failures do not all share one missing-Ruby cause.
Snapshot backlog headers now link to the root format instead of maintaining
separate instructions.

## New-surface review

**Verified OK in source and existing tests:** `CurrentRegionResolver` checks
recording authority before and after acquiring a fix, rejects `.other`, and
reuses the composition root's ingestor and attributor. The new test file covers
missing/outside fixes and revocation during an awaited request.
`LocationWelcomeModel` rejects cancellation, a disabled preference, and stale
request sequences before publishing; dismissal alone persists the region.
Its tests cover cancellation, disabling during lookup, replay after the DEBUG
reset, and suppression of the acknowledged region. Preferences and the report
mirror have existing round-trip/reset and visibility tests.

The UI uses generated localized copy, typed region values, the existing planned
stay editor, an independent scrim layer, modal accessibility traits and
screen-change notifications. The stylesheet supplies separate arrival/departure
motion and a nonspatial Reduce Motion alternative. The reset is DEBUG-only and
clears only the acknowledged region. These are source-level checks, not a claim
that live transition timing or VoiceOver focus was exercised here.

**Filed:** “Refresh the live-region welcome when the scene becomes active”
(Where P1), and “Cover the welcome overlay's scrolling and modal semantics”
(Where P2). Both are in [`Where/TODOs.md`](Where/TODOs.md); the report does not
duplicate their implementation proposals. The former needs a retained-tab
foreground reproduction; the latter records the fixed-frame, semantic-capture,
and iPad coverage gaps without claiming a screenshot proves broken rendering.

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
| WhereUI | Welcome lookup lacks foreground refresh trigger | [Where P1](Where/TODOs.md) |
| CI / scripts | Serial-axis documentation and Linux portability gaps | [Root P1](TODOs.md) |
| Repository | Missing group doc pairs for Where and Ledger | [Root P1](TODOs.md) |

The nearest dated external task remains the benchmark organization cleanup,
after the saved **September 9** plan downgrade (two days from this audit).
`gh repo view` confirms the benchmark repository exists and is not archived.
Billing state, installed integrations, and downgrade scheduling were not
independently verified; no deletion or billing action was taken.

## Cross-cutting themes

- **A report date does not identify its source coverage.** Use the explicit
  covered commit, including same-day merges the prior report omitted.
- **Passing tests and good coverage are different claims.** The journal test
  catches loss despite poor diagnostics; welcome model coverage does not prove
  foreground wiring, scroll reachability, or live motion.
- **Describe present behavior separately from intended invariants.** The
  corrected reconciliation and snapshot docs now name the limitations that
  remain filed. Documentation repairs do not imply runtime fixes.
- **Keep historical measurements historical.** Current references are 495;
  the 260-reference settle measurements still require remeasurement. The
  addressable raised-floor set remains 39 configurations, not a new timing result.

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
| [SnapshotKit](Shared/SnapshotKit/README.md) | 8 | 3 | — | Shippable matrix remains separate from comparison engine; docs now disclose that the runner shares captured models across configurations. |
| [SnapshotKitTesting](Shared/SnapshotKitTesting/README.md) | 16 | 16 | — | Provider duplicate guard, cancellation outcome, parse failure paths and config loop match filed issues; shard plan validates all 49 suites. |
| [StuffTestHost](Shared/StuffTestHost/README.md) | 2 | 0 | — | UIKit shell delegates test-window setup to TestHostSupport; no WhereCore import or new source. |
| [TestHostSupport](Shared/TestHostSupport/README.md) | 1 | 0 | — | UIKit/Objective-C hosting seam remains app-independent; host smoke contract is exercised from LifecycleKit tests. |
| [RegionKit](Where/RegionKit/README.md) | 15 | 10 | — | GeoJSON decoding gap is honestly documented; source still throws for unsupported geometry. No new source in the window. |
| [RegionViewer](Where/RegionViewer/README.md) | 1 | 0 | — | Bundled per-region data description remains correct; missing Broadway root is still filed in Where. |
| [Where](Where/Where/README.md) | 8 | 4 | — | Runtime selection and intent handoff remain in the app shell; new welcome work did not add a second store or runtime. |
| [WhereCore](Where/WhereCore/README.md) | 129 | 84 | — | New resolver rechecks recording authority after suspension and uses the injected attributor; revoked-authorization regression exists. |
| [WhereCrashReporting](Where/WhereCrashReporting/README.md) | 3 | 2 | — | Capture SDK stays behind the dedicated adapter target; no source, dependency, or test changes in this window. |
| [WhereIntents](Where/WhereIntents/README.md) | 15 | 9 | — | Intent services remain injected; four shortcuts and the perform-glue testing limitation match source. No new source in the window. |
| [WhereShareExtension](Where/WhereShareExtension/README.md) | 5 | 0 | — | Compose model still builds pending evidence; no test bundle was silently added. Shared form/testing gaps remain filed. |
| [WhereUI](Where/WhereUI/README.md) | 289 | 104 | 46 | Welcome cancellation/preference guards, dismissal-only persistence, localized controls, and Reduce Motion tokens have source/test evidence; see new-surface review below. |
| [WhereWidgets](Where/WhereWidgets/README.md) | 7 | 0 | — | Provider retains midnight reload policy and reads published stores; no direct new service or welcome dependency. |

**Totals:** 709 source, 371 test/support, and 49 image-suite Swift files.
The inventory excludes two unwired Periscope journal-benchmark sources and
four Bumper rule/test files. `Package.swift` declares 20 library targets;
`Project.swift` declares seven app/extension targets and 25 test bundles:
20 unit bundles in `Stuff-iOS-Tests`, LedgerCoreTests in `Ledger-macOS-Tests`,
and four image bundles in `StuffSnapshotTests`. Neither manifest changed in
the reviewed window.

**References:** 484 WhereUI, five Flyover, four Inspector, two PeriscopeTools,
for 495 total. The 49 addressable suites retain assignments 13 / 15 / 18 plus
three on the intake shard. The shard validator passes. WhereCore's basename
coverage proxy remains 60 sources without a namesake test among 129 sources;
logging types and record shells mean that is not a list of 60 untested behaviors.

**Group docs:** Broadway and Periscope have both docs; Where lacks its group
README and Ledger lacks both group docs. Their leaf modules are complete.
The existing root item remains open, with its stale 28-leaf count corrected.

**Bumper and tooling:** the ten `where.*` rules and eleven source-rule test
functions remain; the explicit-calendar filter and mutation fixtures still
miss the 12 implicit calendar sites (four production, eight DEBUG fixtures).
`component_boundary` and `forbidden_import` have mutation tests; the two other
graph assertions remain filed for missing mutation coverage. Source review
establishes that mechanism; no fresh architecture run is claimed. The 18 root
commands, retained tooling layer, and CI configuration had no executable change.

## Verification and limitations

- `./swiftformat --lint` — passed, 0 of 1,136 files require formatting;
  125 skipped. The sandbox prevented writing its optional cache, without
  affecting the lint result.
- `./shellcheck` — passed.
- `./attribution --check` — passed, 12 credits current.
- `./snapshot-shards check` — passed, all 49 suites assigned.
- `./sync-agents` — passed after instruction edits; generated mirrors remain
  ignored. `git diff --check` — passed.
- This run is on **macOS**, but the audit remains **static analysis** plus the
  supported host checks above. The skill's Linux limitations still apply to
  Linux runs: no Tuist, Xcode, simulator, or runtime validation is implied.
- `./test`, architecture execution, simulator/image suites, and the retained
  Python/Ruby suites were skipped because this change is Markdown and Swift
  comments only. There are no executable, matrix, reference, or rendered-copy
  changes. Prior PR test counts were read as historical evidence, not reported
  as this run's results. The prior Ruby sandbox failure was not rerun or closed.
- No fresh screenshots or live animations were inspected. Existing visual
  defects and quarantines remain open; the welcome's focus, foreground
  lifecycle, and motion need device/simulator validation when addressed.
- CloudKit readiness, passive background delivery, multi-process journals,
  runtime diagnostic routing, and Ledger's live API/Keychain behavior were not
  exercised. Historical timing/spike conclusions remain conditional on their
  stated measurement environment.
