# Swift Module Audit Report

**Date:** October 26, 2026
**Reviewed source:** `820030f6847db856a40393aa2e40814b1bef60de` (PR #436), fetched from `origin/main`.
**Prior audit:** October 19, 2026, merged in PR #401 (`f8ad52b9e`), with full source coverage through `2d686c95d` (PR #391).

This report is derived from all 12 `TODOs.md` files and carries no actionable
items. The root [`TODOs.md`](TODOs.md) owns their format and placement. It is
true as of the header date and reviewed source, not as of later HEADs.

## Method and changes since the previous audit

Every open area backlog was rechecked against current source, test mechanisms,
and the week's diff. Unchanged areas were checked at their cited seams; this is
not a fresh line-by-line review of all 914 source files. Tracked source,
test/support, image-suite and reference files were recounted against the
manifests. Test presence is not a claim that the tests ran this week.

`INBOX.md` has no open notes, so no promotion or decline was needed. Existing
priorities, human origins and completed history are preserved. Two terse existing
human requests now have source context: a domain raw-data browser and translator
comments. No additional independent defect was established beyond the existing
backlog; changed implementations sharpened those entries instead of creating
duplicates.

The reviewed window is `2d686c95d..820030f68`, 37 merged commits. It includes
#392/#369, which the prior report covered only as merge reconciliation. Dates
below are GitHub merge dates (UTC), not earlier branch commit dates.

| Merged | PRs | Surface reviewed |
|---|---|---|
| October 19 | #392, #369, #401 | Host-check split; reference groups and settling noise; previous audit |
| October 20 | #404, #407, #402, #405 | Bounded settling retries; backup sharing; Flat; typed style overrides |
| October 22 | #403, #409, #375, #394, #412, #396, #397, #398, #408, #414, #358 | Elsewhere and Locations stack; sparse flights and uncertain arrival; capture memory; generated journeys and evidence fixtures/replay; coordinate exports; generic Flyover exporter |
| October 23 | #359, #361, #423, #416, #421 | Flyover web viewer/hosted adapter; sheet backgrounds; estimates and Timeline |
| October 24 | #426, #427, #429, #428, #430, #431, #432, #433 | Installer asset validation, refresh lifetime, preparation pages, PR titles, site snapshots, multi-app catalog and PR signing |
| October 26 | #422, #434, #400, #435, #362, #436 | Calendar overview; shard rebalance; feed bootstrap; explicit snapshot matrices; transactional Flyover atlas; comparison sheets |

Open compatibility/IdentifierKit and other unmerged work is not shipped evidence.
Backup remains v7; later branch proposals do not change this audit's cutoff.

| Area | October 19 report | October 26 state |
|---|---|---|
| Source / test-support / leaf image-suite files | 851 / 474 / 65 | **914 / 527 / 69** |
| Leaf modules with both docs | 30 | **30** |
| Additional tool image suites | 1 | **1**; 70 suite files total |
| WhereCore | 161 / 112 | **169 / 126** source / test-support |
| WhereUI | 335 / 134 / 57 | **360 / 151 / 61** |
| Reference PNGs | 1,043 | **953**, including 812 WhereUI, 106 InstallerKitUI and 24 Tools |
| Test bundles | 29 Tuist + host macro bundle | **Unchanged** |
| Shard assignment counts | 13 / 15 / 18 / 18 + 2 intake | **13 / 19 / 16 / 22 + 0 intake** |
| Raised-floor configurations | 82 | **106**; no new timing measurement |
| Backlog closure | Feed bootstrap was proposed | **Bootstrap archived after #400 and 50 passing feed/site tests** |

Comparison sheets store several independent panel captures in one PNG. Reference
count is therefore no longer capture count. Representative matrices, retries and
memory changes also invalidate extrapolation from old timing samples; the
SnapshotKitTesting performance entry retains that measurement limit.

The bootstrap closure covers the signing-independent publication dependency,
empty-branch handling and preservation of existing catalog/manifests. It does
not close signed-device installation or update acceptance. Calendar positioning
now names #422's layout-keyed reconciliation and zoom tests while retaining the
original app-shell runtime requirement. Elsewhere naming now runs sequentially
through a protocol, but the production namer's shared-task cancellation/cache
gaps remain. Ordinary snapshots still share captured models across configurations;
#436's fresh panel builders narrow that claim without closing it.

## New-surface review

**Flights, history and evidence:** sparse endpoint corroboration is bounded by
travel evidence, positional uncertainty and ground vetoes. Arrival is represented
as observed ground or uncertain timing; supported flight intervals, rather than
silence through the arrival window, drive completed-day coverage. Historical and
correction replay preserve these distinctions. Source fixtures cover sparse,
misleading and boundary evidence. The generator defaults to 1,000 seeds across
12 profiles (12,000 synthetic journeys). Those Swift tests were not executed
in this documentation pass.
Backup sharing owns a prepared archive through its presentation lifetime; the
backup format remains v7. JSON/coordinate export remains distinct from bundled
polygon display detail.

**Where presentation:** Flat shares region/year data with the existing card
surfaces. ElsewhereModel publishes only current request results and separates
Home presentation from historical gaps. Locations delegates cards and state
presentation to child views. CalendarPresentationModel holds overview/month
presentation state, while measured frames gate zoom transitions; loading/failure
and initial app-shell positioning acceptance remain separate. Timeline presentation
splits at interior visit starts and flight departures while retaining each region-day
once; one-day cards use their own sizing policy. The new tests and snapshot cases
are evidence of declared coverage, not a live gesture or visual review by this audit.

**Installer:** Pages now runs on trusted main without a signed archive. A missing
publication branch yields an empty schema-3 catalog; an existing branch with a
missing catalog or failed read still fails honestly. The deployed catalog and
exact-build manifests are preserved. The executed 50 feed/site tests cover these
paths, including multi-app and retired history. Draft-release validation checks
available asset names; preparation pages retain typed app/channel links; optional
PR titles flow through the feed/UI. UpdatePageRefresh cancels replaced and
abandoned work, with source tests controlling superseded results. Signing setup
keeps registered app identity and PR source selection explicit. No credential,
release, Pages deployment, signing or device operation was performed here.

**Flyover:** the generic exporter validates policy before capture and checks
cancellation before publication. The Where adapter uses synthetic fixtures and
captures through SnapshotKitTesting without importing it into Flyover. The static
web viewer consumes validated manifest/assets. The root `flyover` wrapper stages
output beside its destination, validates the export and ownership marker, and
replaces the old output only after success. Existing source tests cover failure
preservation and path/symlink rejection. Synthetic span capture does not reroute
WhereLog's static facade; the existing diagnostic-isolation item remains open.

**Capture, Broadway and CI:** BModeVarying selects authored values by explicit
mode; WhereThemeOverrides resolves typed optional fields against the trait-adjusted
base, preserving zero as an override and nil as inheritance. Explicit representative
and compact matrices replace broad default selection. Comparison sheets validate panel identity and metadata, then
compare independently captured panels through the shared reference path. Bounded
retries apply to settling failures, not mismatches or cancellation; readiness
hooks remain repeatable. Normalized image/pixel lifetime changes and the current
70-suite shard plan were inspected. Plan validation passes; no fresh timing,
image capture or memory measurement is claimed.

**Documentation:** root guidance already includes the `flyover` command. SnapshotKit's
README and AGENTS now distinguish ordinary-case model sharing from fresh cutsheet
panel builders and retry reuse. The week's other owning docs already describe
the new flight/arrival, Flat/Elsewhere, calendar, installer and export contracts.
Agent mirrors were synchronized. This audit changes no executable code, target,
dependency, concurrency contract, matrix, reference or product copy.

## Top findings

Pointers only; evidence and proposed fixes live in the owning backlog.

| Area | Finding | Backlog |
|---|---|---|
| Bumper | Gregorian rule misses implicit `.current` | [Root P0](TODOs.md) |
| WhereCore | Daily summary absent from local fan-out | [Where P0](Where/TODOs.md) |
| PeriscopeCore | Pre-store-attach records absent from durable log | [Periscope P0](Shared/Periscope/TODOs.md) |
| Installer / tooling | Live signed distribution and update verification | [Root P1](TODOs.md) |
| WhereCore / WhereUI | Residency requirements and remaining-day display | [Where P1](Where/TODOs.md) |
| WhereUI | Four production Gregorian defaults/helpers remain | [Where P1](Where/TODOs.md) |
| WhereCore | Picker fan-out, hard-delete attribution, report/history reads | [Where P1](Where/TODOs.md) |
| WhereUI | Timeline acceptance and shared report-load gate | [Where P1](Where/TODOs.md) |
| WhereUI | Launch-time notification permission prompt | [Where P1](Where/TODOs.md) |
| SnapshotKit | Ordinary captured models shared across configurations | [SnapshotKit P1](Shared/SnapshotKit/TODOs.md) |
| WhereUI | Calendar initial positioning and geocoding cancellation | [Where P2](Where/TODOs.md) |
| Scripts / docs | Linux portability and missing feature-group docs | [Root P1](TODOs.md) |

`gh repo view` confirms the benchmark repository still exists and is not archived
on October 26. Billing, the scheduled downgrade and installed integrations remain
unverified. No destructive or billing action was taken.

## Cross-cutting themes

- **Evidence and presentation are different contracts.** Supported flight time,
  uncertain arrival, Home assumptions and planned bounds retain distinct meaning.
- **Partial improvements need narrow closure criteria.** Bootstrap tests close a
  publication dependency; new calendar transitions do not prove initial scroll
  reachability, and a caller seam does not test the production geocoder.
- **More capture forms require explicit fixture ownership.** Ordinary content,
  comparison panels and retries have different construction lifetimes. A lower
  PNG count says little about total captures or cost.
- **Validated staging protects publication.** Installer assets and the Flyover
  atlas are advertised only after validation; their empty, failed and superseded
  states matter as much as successful output.
- **Existing write fan-out gaps survive UI growth.** New presentation consumes
  more shared state without repairing missing local notification reconciliation.

## Module inventory and Verified OK

Counts are tracked `.swift` files under each leaf module's `Sources/`, `Tests/`,
and `SnapshotTests/`; tests include support files and do not equal test cases.
All **30 leaf modules** have both README.md and AGENTS.md. Results below are
static unless explicitly identified as executed.

| Module | Source | Test/support | Image suite | Verified OK / bounded result |
|---|---:|---:|---:|---|
| [Ledger](Ledger/Ledger/README.md) | 8 | 0 | — | Native macOS app and hostless LedgerCore scheme remain separate from iOS; app has no test bundle by design. |
| [LedgerCore](Ledger/LedgerCore/README.md) | 16 | 14 | — | Refresh-generation guards and scripted API/Keychain seams are unchanged; 14 test/support files remain, with the three namesake gaps still filed. |
| [BroadwayCatalog](Shared/Broadway/BroadwayCatalog/README.md) | 2 | 1 | — | Catalog target is in the iOS scheme; its placeholder and empty test are still accurately filed, not counted as behavior coverage. |
| [BroadwayCore](Shared/Broadway/BroadwayCore/README.md) | 19 | 13 | — | BModeVarying selects authored light/dark values from an explicit mode and has namesake tests. Category metrics remain explicit; cache and unchanged-value gaps are still filed. |
| [BroadwayUI](Shared/Broadway/BroadwayUI/README.md) | 6 | 4 | — | Depends downward on BroadwayCore; nested-observer TODO remains at the cited source. |
| [CreditKit](Shared/CreditKit/README.md) | 2 | 3 | — | Foundation-only value layer and manifest-derived reachability remain; attribution passes with 19 credits. The malformed GitHub-slug parser remains filed. |
| [Flyover](Shared/Flyover/README.md) | 66 | 18 | 1 | Generic web export validates capture policy, resets screens per profile, and checks cancellation before publishing. Manifest identities and asset paths are validated; five native references do not establish web interaction coverage. |
| [Inspector](Shared/Inspector/README.md) | 23 | 14 | 1 | One image suite has four references; relationship branch and three silent fetch defaults still match the backlog. |
| [InstallerKit](Shared/InstallerKit/README.md) | 10 | 11 | — | App/bundle selection, exact manifest paths, release ordering and last-good cache guards remain. Optional PR-title metadata preserves older feed decoding; no live server or device check was performed. |
| [InstallerKitUI](Shared/InstallerKitUI/README.md) | 27 | 8 | 5 | UpdatePageRefresh owns replacement/disappearance cancellation and has focused supersession tests. Typed channel destinations and localized failure descriptions remain; five suites contain 106 references. |
| [JournalKit](Shared/JournalKit/README.md) | 2 | 3 | — | Concurrent append test checks recovered count, uniqueness, and writer order; swallowed error diagnostic is the actual remaining gap. |
| [LifecycleKit](Shared/LifecycleKit/README.md) | 8 | 10 | — | Duplicate-ID precondition is present; existing test files still cover typed launch and cancellation. Duplicate-ID exit-test gap remains. |
| [LifecycleKitUI](Shared/LifecycleKitUI/README.md) | 6 | 4 | — | Gate-registration uniqueness guard remains present; view-level splash ownership is unchanged. |
| [PeriscopeCore](Shared/Periscope/PeriscopeCore/README.md) | 53 | 49 | — | Source and tests are unchanged in this window. Span identity remains computed by downcast; store attachment and category-filter mechanisms still match the filed durability/filtering gaps. |
| [PeriscopeMacros](Shared/Periscope/PeriscopeMacros/README.md) | 6 | 4 | — | Build-host-only target and four test files are unchanged; generated classification rules remain outside shipping runtime dependencies. |
| [PeriscopeTools](Shared/Periscope/PeriscopeTools/README.md) | 27 | 27 | 1 | Hierarchy count/query asymmetry is explicitly pinned; 20 hosting-only assertions across 10 files and two image references remain. |
| [PeriscopeUI](Shared/Periscope/PeriscopeUI/README.md) | 1 | 2 | — | Single SwiftUI environment adapter imports only PeriscopeCore and SwiftUI; test/support inventory unchanged. |
| [SnapshotKit](Shared/SnapshotKit/README.md) | 13 | 9 | — | Explicit representative/compact matrices preserve configuration identity. Single-view and cutsheet subjects are mutually exclusive; empty sheets and duplicate panel IDs are rejected. |
| [SnapshotKitTesting](Shared/SnapshotKitTesting/README.md) | 30 | 30 | — | Single views and cutsheets share configured capture/reference helpers. Panels are freshly built per configuration; retries reuse supplied model objects. Tests cover metadata geometry, panel comparison, settling retries and normalized memory handling; ordinary model isolation remains open. |
| [StuffTestHost](Shared/StuffTestHost/README.md) | 2 | 0 | — | UIKit shell delegates test-window setup to TestHostSupport; no WhereCore import or new source. |
| [TestHostSupport](Shared/TestHostSupport/README.md) | 1 | 0 | — | UIKit/Objective-C hosting seam remains app-independent; host smoke contract is exercised from LifecycleKit tests. |
| [RegionKit](Where/RegionKit/README.md) | 15 | 10 | — | Geometry behavior and tests are unchanged; decoding throws for unsupported geometry and logs restricted original errors. Documentation now distinguishes coordinate evidence from bundled polygon display detail. |
| [RegionViewer](Where/RegionViewer/README.md) | 1 | 0 | — | Bundled per-region data description remains correct; missing Broadway root is still filed in Where. |
| [Where](Where/Where/README.md) | 9 | 5 | — | Regular runtime owns one optional UpdateModel, constructed from Development-only identity with ephemeral networking and injected preferences. Other audiences and Inspector retain their separate runtime paths. |
| [WhereCore](Where/WhereCore/README.md) | 169 | 126 | — | Sparse-flight inference distinguishes supported flight intervals from uncertain arrival timing. Ground vetoes and positional uncertainty remain explicit. Historical/correction replay and generated journeys have source tests; backup remains v7. |
| [WhereCrashReporting](Where/WhereCrashReporting/README.md) | 3 | 2 | — | Capture SDK stays behind the dedicated adapter target; no source, dependency, or test changes in this window. |
| [WhereIntents](Where/WhereIntents/README.md) | 15 | 9 | — | Injected audience group reaches the snapshot reader; App Group-open failure is logged before report fallback. README states the perform-glue testing limitation. |
| [WhereShareExtension](Where/WhereShareExtension/README.md) | 6 | 0 | — | Extension validates its audience and uses local-only storage in that audience’s App Group. Pending-evidence construction and the filed form/testing gaps are unchanged. |
| [WhereUI](Where/WhereUI/README.md) | 360 | 151 | 61 | Flat/Elsewhere and calendar overview use shared report inputs and guarded publication. New zoom tests exercise transitions; they do not establish original MainTabs positioning or Timeline live year-switch acceptance. Flyover uses a synthetic export world. |
| [WhereWidgets](Where/WhereWidgets/README.md) | 8 | 0 | — | Audience-specific group is injected into both snapshot and presentation stores; provider retains the midnight reload policy without opening the app’s SwiftData store. |

**Leaf totals:** 914 source, 527 test/support and 69 image-suite Swift files.
Tools adds one `InstallerSiteSnapshotTests.swift` suite and 24 PNG references.
Inventory excludes two unwired journal benchmark sources, six Bumper source/test
files, and CreditKit's Swift manifest fixture under its Ruby-tool tests.
`Package.swift` has 22 library targets plus one macro and one host test target.
`Project.swift` has seven app/extension families and 29 test bundles: 22 iOS unit
bundles, LedgerCoreTests and six image bundles. The macro test bundle is additional
and runs on the host through `./test`.

**References:** 812 WhereUI, 106 InstallerKitUI, 24 Tools, five Flyover,
four Inspector and two PeriscopeTools: 953 total. WhereCore's basename proxy is
73 of 169 sources without a namesake test, previously 70 of 161. This is not a
count of untested behaviors.

**Group docs:** Broadway and Periscope have both docs; Where lacks its group
README and Ledger lacks both group docs. The existing root item remains open.

**Bumper:** the explicit Calendar filter still misses 11 implicit sites: four
production and seven DEBUG fixtures. The mutation fixture uses explicit
`Calendar.current`; duplicate ownership and declared-cycle mutation gaps remain.
Architecture execution was not rerun.

## Verification and limitations

- `./swiftformat --lint` — passed, 0 of 1,519 files require formatting;
  107 skipped. Optional cache warnings did not affect the result.
- `./shellcheck` — passed.
- `./attribution --check` — passed, 19 credits current.
- `./sf-symbols --lint` — passed.
- `./xcstrings --lint` — passed, eight catalogs; compiler-cache access required
  escalation after the sandboxed attempt failed.
- `./snapshot-shards check` — passed, 70 suites, four planned workers plus
  intake: 13 / 19 / 16 / 22 + 0.
- `mise exec -- npm ci --prefix Tools/InstallerKit/Site` installed locked
  dependencies without changing the lockfile. Then
  `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=Tools/Tests python3 -m unittest test_installer_update_feed test_installer_update_site`
  passed **50 tests**. The initial invocation lacked the test fixture import path
  and hit sandbox write restrictions; the corrected run passed with worktree access.
- `./sync-agents` and `git diff --check` — passed; generated mirrors are ignored.
  Tracked-file inventory, completed-history preservation and edited Markdown
  local-link checks were verified separately.
- This host is **macOS**, but the pass remains **static analysis plus the checks
  above**. The skill's Linux limitation remains: Tuist, Xcode and simulator
  validation cannot run there. Linux portability findings were not reproduced
  or closed by a macOS test pass.
- `./test`, architecture execution, macro/unit/image suites, remaining retained
  tool suites and Astro type checking were skipped for Markdown-only changes.
  No new screenshot capture or rendered-reference inspection, animation,
  VoiceOver session, live scroll/year-switch gesture, device check or performance
  measurement was performed. Visual/runtime acceptance remains open; prior PR
  evidence is historical.
- CloudKit convergence, passive background location, multi-process journals,
  diagnostic isolation, signing/distribution, billing and Ledger API/Keychain
  behavior were not exercised. No remote CI pass is inferred from local checks.
