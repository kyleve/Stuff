# Swift Module Audit Report

**Date:** October 19, 2026
**Reviewed source:** `2d686c95d` (PR #391), fetched from `origin/main`.
**Prior audit:** October 12, 2026, merged in PR #368 (`2e73fd018`), with stated source coverage through `b591173f` (PR #364).

This report is derived from all 12 `TODOs.md` files and carries no actionable
items. The root [`TODOs.md`](TODOs.md) owns their format and placement. It is
true as of the header date and reviewed source, not as of later HEADs.

**Later merge reconciliation:** this branch also includes `8d73c08e0` from main
(PRs #392 and #369). Their CI host-check split, snapshot reference grouping and
settling-noise fix are retained, including the completed SnapshotKitTesting item.
The full audit and inventory below retain the `2d686c95d` cutoff; this integration
check does not extend the weekly source review to those two PRs.
The merged-tree check ran `./test SnapshotKitTestingTests`: 86 tests passed,
along with 25 architecture rule tests, architecture lint, and host regressions
(attribution: 1 test/3 assertions; backup upgrader: 16 tests/58 assertions).
The two affected tooling suites passed 22 tests; SwiftFormat (0/1,405, 148
skipped), ShellCheck, shard validation, agent sync and diff checks also passed.
No app image suite or live user-interaction validation was repeated.

**Post-audit removal (October 26, 2026):** Ledger and LedgerCore have been removed.
Their rows and counts below describe the audited revision; the documentation links
are pinned to that revision. Their retired backlog is preserved in the root
[`TODOs.md`](TODOs.md#completed-issues). This note does not extend the audit cutoff.

## Method and changes since the previous audit

The pass read every open area backlog, inspected cited source/test mechanisms,
and compared changed implementations with their acceptance conditions. Unchanged
areas were checked at their cited seams and against the source diff. This is a
focused static review, not a fresh line-by-line review of all 851 source files.
Tracked source, test/support, image-suite and reference files were recounted
against the manifests. Test presence is not a claim that tests ran this week.

Both inbox notes are now filed together in Where's P1 backlog: residency
requirements with a dependent remaining-days display. Their human origin remains
October 12, when the notes were written; their PR merged on October 13. The inbox
is empty. Existing priorities and completed history are preserved.

The reviewed window is `b591173f..2d686c95d`, including #365/#366, which the prior
report mentioned only as later merge reconciliation. GitHub merge metadata, not
branch commit dates, establishes these landing dates (UTC):

| Merged | PRs | Surface reviewed |
|---|---|---|
| October 12 | #365, #366, #368 | Planning snapshot groundwork; calendar/year accessibility; prior audit |
| October 13 | #371, #316 | Residency notes; independent stays, Home choice, uncertain forecasts and backup v7 |
| October 16 | #373, #357 | Completed flights in history; hosted PNG capture and cancellation |
| October 18 | #389, #381, #382, #383 | Shard maintenance; ad hoc archive/publication; hosted install-site snapshots |
| October 18 | #374, #370, #384, #385, #386, #380 | Quiet first welcome baseline; PR guidance; shared update engine/UI, host integration and failure descriptions |
| October 18 | #388, #390 | Astro install site; shared Fastlane signing/archive tooling |
| October 19 | #391 | Fourth planned snapshot worker plus intake |

Open proposals are not shipped evidence. In particular, the feed-bootstrap fix
#400, sparse-flight/arrival work, compatibility stack, Duo adoption, Flyover web
export, and snapshot-selection experiment remain outside this source cutoff.
Backup is now v7 because #316 landed, independently of the unmerged compatibility work.

| Area | October 12 report | October 19 state |
|---|---|---|
| Source / test-support / leaf image-suite files | 791 / 431 / 57 | **851 / 474 / 65** |
| Leaf modules with both docs | 28 | **30**, adding InstallerKit and InstallerKitUI |
| Additional tool image suite | None | **1**, ToolsSnapshotTests; 66 total suite files |
| WhereCore | 152 / 101 | **161 / 112** source / test-support |
| WhereUI | 323 / 124 / 54 | **335 / 134 / 57** |
| Reference images | 761 | **1,043**, including 898 WhereUI, 106 InstallerKitUI and 28 Tools |
| Test bundles | 25 Tuist + host macro bundle | **29 Tuist + host macro bundle** |
| Shard assignment counts | 16 / 19 / 22 + 0 intake | **13 / 15 / 18 / 18 + 2 intake** |
| Raised-floor configurations | 71 | **82**; no fresh timing measurement |
| Backlog | Empty inbox; Timeline lacked a gate | **Two human notes promoted**, Timeline narrowed, first-feed bootstrap filed |

The Timeline's initial-loading and failure branches shipped in #316. Its backlog
item now retains rendered-state and live year-switch verification, with the shared
ReportLoadGate extraction still open. The old calendar-property test wording no
longer claims that deleting a property proves positioning: the current
`initiallyPositionedYear` gate and live layout acceptance remain filed.
The existing hosted-capture cancellation closure now names #357's October 16
merge and its replacement guards. No additional visual/runtime item was closed.

The first-publication feed dependency is filed at root, with #400 explicitly
identified as an unmerged proposed fix. Source citations and inventories were
refreshed in the affected backlogs. The existing native-macOS test-runner item
retains #390's historical affected-selection failure; this run did not reproduce it.

## New-surface review

**Planning and residency:** `PlannedStayCoordinator` reads independent stay
registers and Home intent in one store snapshot, preserves completed plans and
delete tombstones, and refuses edits that would resurrect a deleted plan.
`PlanningSnapshot` projects only future days. `LocationForecast` deduplicates
region-days, distinguishes Home from historical gaps, and computes independent
bounds rather than adding incompatible component extrema. Source tests cover
uncertain overlaps, leap days, year boundaries, and exhaustive feasible scenarios.
These are projection inputs; no residency-requirement or remaining-allowance model
was found. Backup v7 and the offline upgrader carry the new planning shapes;
the module README already states the old-build synchronization limitation.

**History and welcome:** completed flights are derived before review dismissal
and retain local-day coverage across report boundaries. `PresenceJourneyItem`
splits recorded stays for display while preserving each region-day, with tests
for interleaving and deduplication. Calendar accessibility now describes monthly
totals, stays and dated badges through `CalendarMonthAccessibilityTests`.
`LocationWelcomeModel` seeds absent history quietly after a successful live lookup;
explicit DEBUG reset remains distinct. Cancellation and supersession precede the
history write. A current welcome AX5 reference still visibly truncates “Precise
off…”, and the current NewStay iPad reference still shows the Save-button band.
Both items remain open; reference inspection does not establish live behavior.

**Installer:** signed metadata distinguishes local revisions from published
channel/run/attempt identity. The engine validates app/bundle selection, exact
manifest paths, release ordering, and connected predecessor history. Cached
foreground reads do not supersede active manual checks; cancelled/older completions
cannot replace a newer cache or model snapshot. Tests control competing requests
and verify last-good-state retention. UI descriptions preserve original HTTP and
transport diagnostics, with shared localized presentation.

The trusted controller selects same-repository labeled PRs, checks live SHA/label
and mergeability, and publishes verified artifacts before advertising installs.
Signing policy is shared below the app wrappers; CI archives are read-only toward
the signing repository. Astro consumes validated prepared data and production
CSS/artwork also feeds the offline WebKit snapshots. The initial feed still depends
on publication/retirement and the Pages workflow assumes its branch exists; the
root backlog owns that bootstrap finding. No live signing, installation, release,
network-delivery, credential or Pages operation was performed by this audit.

**Capture and CI:** hosted PNG, native assertions, and HTML assertions share
`renderSnapshotCapture`, cancellation and the capture lock. WebKit waits for
navigation/fonts/paint and measures document height before generic capture; its
internal scroll-size mirror is excluded from the fallback. The fourth planned
worker is configured with a separate intake worker, and the current plan validates
all 66 suites. Two suites remain intake. Plan validity is not a new timing result.

**Documentation:** root guidance now names the InstallerKit/InstallerKitUI
architecture boundaries; Tools points to the relocated Astro instructions;
SnapshotKit points to the manifest for consumers; SnapshotKitTesting names the
shared capture entry point and image-only wrapper. The week's module READMEs
already cover independent planning, v7, welcome baselining, updates, and hosted
capture. Agent mirrors were synchronized. These corrections change no API,
dependency, target, concurrency policy, executable source, or rendered copy.

## Top findings

Pointers only; evidence and proposed fixes live in the owning backlog.

| Area | Finding | Backlog |
|---|---|---|
| Bumper | Gregorian rule misses implicit `.current` | [Root P0](TODOs.md) |
| WhereCore | Daily summary absent from local fan-out | [Where P0](Where/TODOs.md) |
| PeriscopeCore | Pre-store-attach records absent from durable log | [Periscope P0](Shared/Periscope/TODOs.md) |
| InstallerKit/tooling | Initialize the feed independently of a signed build | [Root P1](TODOs.md) |
| WhereCore / WhereUI | Residency requirements and remaining-day display | [Where P1](Where/TODOs.md) |
| WhereUI | Four production Gregorian defaults/helpers remain | [Where P1](Where/TODOs.md) |
| WhereCore | Picker fan-out, hard-delete attribution, report/history read amplification | [Where P1](Where/TODOs.md) |
| WhereUI | Timeline acceptance and shared report-load gate | [Where P1](Where/TODOs.md) |
| WhereUI | Launch-time notification permission prompt | [Where P1](Where/TODOs.md) |
| SnapshotKit | Captured models shared across configurations | [SnapshotKit P1](Shared/SnapshotKit/TODOs.md) |
| WhereUI | Diagnostics apply failure loses durable error signal | [Where P2](Where/TODOs.md) |
| WhereUI | Pending flight guidance absent from Explore Features | [Where P2](Where/TODOs.md) |
| Scripts / docs | Linux portability and missing feature-group docs | [Root P1](TODOs.md) |

`gh repo view` confirms the benchmark repository still exists and is not archived
on October 19. Billing, the scheduled downgrade and installed integrations remain
unverified. No destructive or billing action was taken.

## Cross-cutting themes

- **Projections need explicit provenance.** Recorded days, planned bounds, Home
  assumptions and residency requirements are distinct inputs and meanings.
- **Publication needs an empty state before a first success.** Honest client errors
  preserve diagnosis but do not initialize missing server infrastructure.
- **Shared capture adds consumers without closing old acceptance gaps.** More
  references and new export APIs do not prove live navigation, scroll reachability,
  parser recovery, or isolation between snapshot configurations.
- **One source snapshot should drive related presentation.** Planning, flight
  history and correction reviews now preserve more coherent state; existing
  write fan-out and full-history read costs remain independent backlog concerns.
- **Documentation must follow ownership changes.** Manifest pointers and the real
  shared entry point are more durable than old consumer lists or moved paths.

## Module inventory and Verified OK

Counts are tracked `.swift` files under each leaf module's `Sources/`, `Tests/`,
and `SnapshotTests/`; tests include support files and do not equal test cases.
All **30 leaf modules** have both README.md and AGENTS.md. Results below are
static unless explicitly identified as executed.

| Module | Source | Test/support | Image suite | Verified OK / bounded result |
|---|---:|---:|---:|---|
| [Ledger](https://github.com/kyleve/Stuff/blob/2d686c95d/Ledger/Ledger/README.md) | 8 | 0 | — | Native macOS app and hostless LedgerCore scheme remain separate from iOS; app has no test bundle by design. |
| [LedgerCore](https://github.com/kyleve/Stuff/blob/2d686c95d/Ledger/LedgerCore/README.md) | 16 | 14 | — | Explicit refresh-generation guard and scripted API/Keychain seams retained; 14 test/support files, with the three filed namesake gaps; the logging facade now uses the freeform scope API. |
| [BroadwayCatalog](Shared/Broadway/BroadwayCatalog/README.md) | 2 | 1 | — | Catalog target is in the iOS scheme; its placeholder and empty test are still accurately filed, not counted as behavior coverage. |
| [BroadwayCore](Shared/Broadway/BroadwayCore/README.md) | 18 | 12 | — | BScaledDimension uses explicit category metrics; category round-trip and ambient-trait independence tests are present. Cache and unchanged-value gaps remain. |
| [BroadwayUI](Shared/Broadway/BroadwayUI/README.md) | 6 | 4 | — | Depends downward on BroadwayCore; nested-observer TODO remains at the cited source. |
| [CreditKit](Shared/CreditKit/README.md) | 2 | 3 | — | Foundation-only value layer and manifest-derived reachability remain; attribution passes with 19 credits. The malformed GitHub-slug parser remains filed. |
| [Flyover](Shared/Flyover/README.md) | 54 | 14 | 1 | Vector connector paths and 14 test/support files are unchanged. Five references remain; focused inspector/menu/transition coverage is still separate. |
| [Inspector](Shared/Inspector/README.md) | 23 | 14 | 1 | One image suite has four references; relationship branch and three silent fetch defaults still match the backlog. |
| [InstallerKit](Shared/InstallerKit/README.md) | 10 | 11 | — | App and bundle identity gate channel selection; exact manifest paths, run/attempt ordering, last-good cache preservation, and supersession guards are present with focused tests. Local builds do not acquire automatic update badges. |
| [InstallerKitUI](Shared/InstallerKitUI/README.md) | 25 | 7 | 5 | Shared screens own localized failure descriptions and cached-result disclosure; typed browser selection resolves against the current catalog. Five image suites contain 106 references; no live navigation was exercised. |
| [JournalKit](Shared/JournalKit/README.md) | 2 | 3 | — | Concurrent append test checks recovered count, uniqueness, and writer order; swallowed error diagnostic is the actual remaining gap. |
| [LifecycleKit](Shared/LifecycleKit/README.md) | 8 | 10 | — | Duplicate-ID precondition is present; existing test files still cover typed launch and cancellation. Duplicate-ID exit-test gap remains. |
| [LifecycleKitUI](Shared/LifecycleKitUI/README.md) | 6 | 4 | — | Gate-registration uniqueness guard remains present; view-level splash ownership is unchanged. |
| [PeriscopeCore](Shared/Periscope/PeriscopeCore/README.md) | 53 | 49 | — | Span identity remains computed by downcast; the journal still attaches with the store. The only source change here removes an obsolete comment example; durability and category-filter guards remain unchanged. |
| [PeriscopeMacros](Shared/Periscope/PeriscopeMacros/README.md) | 6 | 4 | — | Build-host-only target and four test files are unchanged; generated classification rules remain outside shipping runtime dependencies. |
| [PeriscopeTools](Shared/Periscope/PeriscopeTools/README.md) | 27 | 27 | 1 | Hierarchy count/query asymmetry is explicitly pinned; 20 hosting-only assertions across 10 files and two image references remain. |
| [PeriscopeUI](Shared/Periscope/PeriscopeUI/README.md) | 1 | 2 | — | Single SwiftUI environment adapter imports only PeriscopeCore and SwiftUI; test/support inventory unchanged. |
| [SnapshotKit](Shared/SnapshotKit/README.md) | 8 | 4 | — | Explicit idiom/size-class traits contribute stable configuration identifiers and have a new namesake test. Shippable matrix remains separate from the comparison engine; captured-model sharing remains documented and open. |
| [SnapshotKitTesting](Shared/SnapshotKitTesting/README.md) | 20 | 19 | — | PNG and offline HTML captures share the hosted capture lock/pipeline. Cancellation stops capture; tests cover queued cancellation, throwing readiness hooks, layout traits, and WebKit sizing. Model-sharing, parser-trap, and inline duplicate-identifier gaps remain. |
| [StuffTestHost](Shared/StuffTestHost/README.md) | 2 | 0 | — | UIKit shell delegates test-window setup to TestHostSupport; no WhereCore import or new source. |
| [TestHostSupport](Shared/TestHostSupport/README.md) | 1 | 0 | — | UIKit/Objective-C hosting seam remains app-independent; host smoke contract is exercised from LifecycleKit tests. |
| [RegionKit](Where/RegionKit/README.md) | 15 | 10 | — | GeoJSON decoding gap is honestly documented; source still throws for unsupported geometry. Logging uses classified macros and restricted original errors; geometry behavior and decoding coverage are unchanged. |
| [RegionViewer](Where/RegionViewer/README.md) | 1 | 0 | — | Bundled per-region data description remains correct; missing Broadway root is still filed in Where. |
| [Where](Where/Where/README.md) | 9 | 5 | — | Regular runtime owns one optional UpdateModel, constructed from Development-only identity with ephemeral networking and injected preferences. Other audiences and Inspector retain their separate runtime paths. |
| [WhereCore](Where/WhereCore/README.md) | 161 | 112 | — | Independent stay revisions and Home intent are read in one snapshot; uncertain forecast bounds preserve separate provenance. Backup v7 includes both planning registers. Completed-flight history is derived before review dismissal. |
| [WhereCrashReporting](Where/WhereCrashReporting/README.md) | 3 | 2 | — | Capture SDK stays behind the dedicated adapter target; no source, dependency, or test changes in this window. |
| [WhereIntents](Where/WhereIntents/README.md) | 15 | 9 | — | Injected audience group reaches the snapshot reader; App Group-open failure is logged before report fallback. README states the perform-glue testing limitation. |
| [WhereShareExtension](Where/WhereShareExtension/README.md) | 6 | 0 | — | Extension validates its audience and uses local-only storage in that audience’s App Group. Pending-evidence construction and the filed form/testing gaps are unchanged. |
| [WhereUI](Where/WhereUI/README.md) | 335 | 134 | 57 | Timeline now gates initial loading/failure, but those rendered states and live year switching remain unverified. First live-region lookup quietly seeds history; cancellation/supersession tests protect that write. Shared update UI stays behind audience/demo gates. |
| [WhereWidgets](Where/WhereWidgets/README.md) | 8 | 0 | — | Audience-specific group is injected into both snapshot and presentation stores; provider retains the midnight reload policy without opening the app’s SwiftData store. |

**Leaf totals:** 851 source, 474 test/support and 65 image-suite Swift files.
Tools adds one `InstallerSiteSnapshotTests.swift` suite and 28 PNG references
outside the leaf-module convention. Inventory excludes two unwired journal
benchmark sources, six Bumper source/test files, and CreditKit's Swift manifest
fixture under its Ruby-tool tests. `Package.swift` has 22 library targets plus
one macro and one host test target. `Project.swift` has seven app/extension
families and 29 test bundles: 22 iOS unit bundles, LedgerCoreTests and six image
bundles. The macro test bundle is additional and runs on the host through `./test`.

**References:** 898 WhereUI, 106 InstallerKitUI, 28 Tools, five Flyover,
four Inspector and two PeriscopeTools: 1,043 total. WhereCore's basename proxy
is 70 of 161 sources without a namesake test, previously 70 of 152. This is
not a count of untested behaviors.

**Group docs:** Broadway and Periscope have both docs; Where lacks its group
README and Ledger lacks both group docs. The existing root item remains open.

**Bumper:** ten Where rules have twelve test functions; six Periscope authoring
rules have six test functions (some parameterized). New InstallerKit boundaries
have graph tests, while duplicate ownership and declared cycles still have no
mutation fixtures. The Calendar filter still misses 11 implicit sites: four
production and seven DEBUG fixtures. Architecture execution was not rerun.

## Verification and limitations

- `./swiftformat --lint` — passed, 0 of 1,399 files require formatting;
  144 skipped. Optional cache write was blocked without affecting the result.
- `./shellcheck` — passed.
- `./attribution --check` — passed, 19 credits current.
- `./sf-symbols --lint` — passed.
- `./xcstrings --lint` — passed, eight catalogs match Xcode serialization;
  compiler-cache access required escalation after the sandboxed attempt failed.
- `./snapshot-shards check` — passed, 66 suites, four planned workers plus
  intake: 13 / 15 / 18 / 18 + 2.
- `./sync-agents` and `git diff --check` — passed. Generated mirrors are ignored.
- Tracked-file inventory and edited Markdown local-link checks were verified separately.
- This host is **macOS**; this pass remains **static analysis** plus the checks
  above and inspection of two existing rendered references. The skill's Linux
  limitations remain: Tuist, Xcode and simulator validation cannot run there.
- `./test`, architecture execution, macro/unit/image suites, retained Python/Ruby
  tests and Astro type checking were skipped for Markdown-only changes. No code,
  configuration, dependency, rendered copy, matrix or reference changed. Existing
  Linux portability findings were not reproduced or closed.
- No new screenshot capture, animation, VoiceOver session, live scroll/year-switch
  gesture, device check or performance measurement was performed. Visual and
  runtime acceptance requirements remain open; prior PR evidence is historical.
- CloudKit convergence, passive background location, multi-process journals,
  logging isolation, signing/distribution, billing and Ledger API/Keychain behavior
  were not exercised. No remote CI pass is inferred from the checks above.
