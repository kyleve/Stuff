# Swift Module Audit Report

**Date:** October 26, 2026 (America/New_York; refreshed after the later main merges)
**Reviewed source:** `123272e3f2361a9fa2d23879d654eede6d90b072` (PR #449), fetched from `origin/main`.
**Prior audit:** October 19, 2026, merged in PR #401 (`f8ad52b9e`), with full source coverage through `2d686c95d` (PR #391).

This report is derived from all 12 `TODOs.md` files and carries no actionable
items. The root [`TODOs.md`](TODOs.md) owns their format and placement. It is
true as of the header date and reviewed source, not as of later HEADs.

**Post-audit removal (October 26, 2026):** This branch removes Ledger and LedgerCore.
Their rows and counts below describe the audited revision; the documentation links
are pinned to that revision. Their retired backlog remains in the root
[`TODOs.md`](TODOs.md#completed-issues). This note does not extend the audit cutoff.

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

The reviewed window is `2d686c95d..123272e3f`, 51 merged commits.
The initial pass ended at `820030f68`; this follow-up reconciles 14 additional
merges against the audit and backlog. It traces changed publication, guard and
fixture contracts, not every line of the newly extracted browser implementation.
The full window includes #392/#369, which the prior report covered only as merge reconciliation. Dates
below are GitHub merge dates (UTC), not earlier branch commit dates.

| Merged | PRs | Surface reviewed |
|---|---|---|
| October 19 | #392, #369, #401 | Host-check split; reference groups and settling noise; previous audit |
| October 20 | #404, #407, #402, #405 | Bounded settling retries; backup sharing; Flat; typed style overrides |
| October 22 | #403, #409, #375, #394, #412, #396, #397, #398, #408, #414, #358 | Elsewhere and Locations stack; sparse flights and uncertain arrival; capture memory; generated journeys and evidence fixtures/replay; coordinate exports; generic Flyover exporter |
| October 23 | #359, #361, #423, #416, #421 | Flyover web viewer/hosted adapter; sheet backgrounds; estimates and Timeline |
| October 24 | #426, #427, #429, #428, #430, #431, #432, #433 | Installer asset validation, refresh lifetime, preparation pages, PR titles, site snapshots, multi-app catalog and PR signing |
| October 26 | #422, #434, #400, #435, #362, #436 | Calendar overview; shard rebalance; feed bootstrap; explicit snapshot matrices; transactional Flyover atlas; comparison sheets |
| October 26 | #438, #439, #270, #442, #415, #417, #419, #420, #440, #443, #444 | Reduced screen matrices and focused presets; shard rebalance; local/LAN atlas preview; shared Astro tooling; typed browser modules and accessibility; publication recovery; daily hosting and quality gates |
| October 27 UTC (October 26 Eastern) | #446, #450, #449 | Python/CSS formatting; atlas retention; code-review procedure and architecture mutation guards |

Open compatibility/IdentifierKit and other unmerged work is not shipped evidence.
Backup remains v7; later branch proposals do not change this audit's cutoff.

| Area | October 19 report | October 26 state |
|---|---|---|
| Source / test-support / leaf image-suite files | 851 / 474 / 65 | **914 / 528 / 69** |
| Leaf modules with both docs | 30 | **30** |
| Additional tool image suites | 1 | **1**; 70 suite files total |
| WhereCore | 161 / 112 | **169 / 126** source / test-support |
| WhereUI | 335 / 134 / 57 | **360 / 151 / 61** |
| Reference PNGs | 1,043 | **885**, including 744 WhereUI, 106 InstallerKitUI and 24 Tools |
| Test bundles | 29 Tuist + host macro bundle | **Unchanged** |
| Shard assignment counts | 13 / 15 / 18 / 18 + 2 intake | **13 / 18 / 17 / 22 + 0 intake** |
| Raised-floor configurations | 82 | **84**; 106 before #438; no new timing measurement |
| Backlog closure | Feed bootstrap was proposed | **Bootstrap archived; graph-mutation closure from #449 retained** |

Comparison sheets store several independent panel captures in one PNG. Reference
count is therefore no longer capture count. Representative matrices, retries and
memory changes also invalidate extrapolation from old timing samples; the
SnapshotKitTesting performance entry retains that measurement limit.

The bootstrap closure covers the signing-independent publication dependency,
empty-branch handling and preservation of existing catalog/manifests. It does
not close signed-device installation or update acceptance. A published Where IPA
now makes the original signing-setup blocker historical; device acceptance stays
open. Calendar positioning now names #422's layout-keyed reconciliation and zoom tests while retaining the
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
exact-build manifests are preserved. The initial 50 feed/site tests and the merged tree's 43 tests cover these
paths, including multi-app and retired history. Draft-release validation checks
available asset names; preparation pages retain typed app/channel links; optional
PR titles flow through the feed/UI. UpdatePageRefresh cancels replaced and
abandoned work, with source tests controlling superseded results. Signing setup
keeps registered app identity and PR source selection explicit. Release metadata confirms a published `app.ipa` at
`installer-where-main-40428575955-1`. No credential change, release publication,
Pages deployment, signing or device operation was performed by this audit.

**Flyover:** the web viewer now uses the shared root npm workspace, typed client
modules and component CSS layers. Browser tests exercise URL restoration,
keyboard/focus behavior, failed-image recovery, touch input, axe scans and image
budgets. Those browser tests were inspected but not rerun in this follow-up.
The native manifest/profile/export changes preserve schema-1 compatibility
while supplying numeric viewport sizes and a shared cross-language fixture.

Local/LAN preview validates and privately copies generated artifacts. Tool policy,
pure validation, descriptor-based file access and publication recovery now have
separate owners. Daily capture uses registered unsigned simulator adapters and
skips shared executable caches; shared Pages includes validated release bundles.
Retention runs only after deployment, protects the deployed/newest bundles and
seven days of history, and excludes drafts/unrelated releases. The 91 retained
Flyover tests passed on this merged tree; no live publication or deletion ran.

The newer root backlog records two reproduced publication races: installing over
an empty competing directory and restoring the old atlas after the committed
directory moves. The audit therefore makes no general rollback-safety claim.
New Flyover findings also retain capture-focused shortcuts, group-ID collision,
drawer bounds and original-error loss; Where retains eager Elsewhere descriptors.
These findings arrived in #449 and remain open. Synthetic span capture still does
not reroute WhereLog's process-global facade.

**Capture, Broadway and CI:** BModeVarying selects authored values by explicit
mode; WhereThemeOverrides resolves typed optional fields against the trait-adjusted
base, preserving zero as an override and nil as inheritance. Explicit representative
and compact matrices replace broad default selection. Comparison sheets validate panel identity and metadata, then
compare independently captured panels through the shared reference path. Bounded
retries apply to settling failures, not mismatches or cancellation; readiness
hooks remain repeatable. Normalized image/pixel lifetime changes and the current
70-suite shard plan were inspected. Plan validation passes; no fresh timing,
image capture or memory measurement is claimed.

**Documentation:** root guidance now describes the shared npm workspace, lint
gates, daily Flyover publication and the new code-review procedure. SnapshotKit's
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
| Scripts | Atlas publication ownership and commit-state races | [Root P1](TODOs.md) |
| Flyover | Browser controls/filtering and error preservation | [Flyover P2](Shared/Flyover/TODOs.md) |
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
- **Validation and filesystem ownership need separate guards.** Validated atlas
  contents do not prevent a competing rename or prove that cleanup preserves a
  committed installation. Those races remain filed despite passing ordinary tests.
- **Existing write fan-out gaps survive UI growth.** New presentation consumes
  more shared state without repairing missing local notification reconciliation.

## Module inventory and Verified OK

Counts are tracked `.swift` files under each leaf module's `Sources/`, `Tests/`,
and `SnapshotTests/`; tests include support files and do not equal test cases.
All **30 leaf modules** have both README.md and AGENTS.md. Results below are
static unless explicitly identified as executed.

| Module | Source | Test/support | Image suite | Verified OK / bounded result |
|---|---:|---:|---:|---|
| [Ledger](https://github.com/kyleve/Stuff/blob/123272e3f2361a9fa2d23879d654eede6d90b072/Ledger/Ledger/README.md) | 8 | 0 | — | Native macOS app and hostless LedgerCore scheme remain separate from iOS; app has no test bundle by design. |
| [LedgerCore](https://github.com/kyleve/Stuff/blob/123272e3f2361a9fa2d23879d654eede6d90b072/Ledger/LedgerCore/README.md) | 16 | 14 | — | Refresh-generation guards and scripted API/Keychain seams are unchanged; 14 test/support files remain, with the three namesake gaps still filed. |
| [BroadwayCatalog](Shared/Broadway/BroadwayCatalog/README.md) | 2 | 1 | — | Catalog target is in the iOS scheme; its placeholder and empty test are still accurately filed, not counted as behavior coverage. |
| [BroadwayCore](Shared/Broadway/BroadwayCore/README.md) | 19 | 13 | — | BModeVarying selects authored light/dark values from an explicit mode and has namesake tests. Category metrics remain explicit; cache and unchanged-value gaps are still filed. |
| [BroadwayUI](Shared/Broadway/BroadwayUI/README.md) | 6 | 4 | — | Depends downward on BroadwayCore; nested-observer TODO remains at the cited source. |
| [CreditKit](Shared/CreditKit/README.md) | 2 | 3 | — | Foundation-only value layer and manifest-derived reachability remain; attribution passes with 29 credits. The malformed GitHub-slug parser remains filed. |
| [Flyover](Shared/Flyover/README.md) | 66 | 19 | 1 | Generic web export validates capture policy, resets screens per profile, and checks cancellation before publishing. Numeric viewport sizes have a shared wire fixture; browser checks are separate from the five native references. The four new browser/error findings remain filed. |
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
| [SnapshotKit](Shared/SnapshotKit/README.md) | 13 | 9 | — | Focused AX5/annotation presets preserve explicit configuration identity and order, with source assertions for each preset. Single-view and cutsheet subjects are mutually exclusive; empty sheets and duplicate panel IDs are rejected. |
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

**Leaf totals:** 914 source, 528 test/support and 69 image-suite Swift files.
Tools adds one `InstallerSiteSnapshotTests.swift` suite and 24 PNG references.
Inventory excludes two unwired journal benchmark sources, seven Bumper source/test
files, and CreditKit's Swift manifest fixture under its Ruby-tool tests.
`Package.swift` has 22 library targets plus one macro and one host test target.
`Project.swift` has seven app/extension families and 29 test bundles: 22 iOS unit
bundles, LedgerCoreTests and six image bundles. The macro test bundle is additional
and runs on the host through `./test`.

**References:** 744 WhereUI, 106 InstallerKitUI, 24 Tools, five Flyover,
four Inspector and two PeriscopeTools: 885 total. WhereCore's basename proxy is
73 of 169 sources without a namesake test, previously 70 of 161. This is not a
count of untested behaviors.

**Group docs:** Broadway and Periscope have both docs; Where lacks its group
README and Ledger lacks both group docs. The existing root item remains open.

**Bumper:** the explicit Calendar filter still misses 11 implicit sites: four
production and seven DEBUG fixtures. The mutation fixture uses explicit
`Calendar.current`. PR #449 now exercises duplicate ownership, declared cycles
and duplicate-module rejection using the production graph and retained rule settings.
The Gregorian implicit-member gap remains separate.

## Verification and limitations

The original pass at `820030f68` passed SwiftFormat, ShellCheck, attribution,
symbol/catalog lint, shard validation, 50 feed/site tests, agent sync and diff/link
checks. Its old PR head also passed GitHub and CircleCI CI before this refresh.
Those results are historical and do not establish the new head's CI result.

Follow-up checks on the merged `123272e3f` source:

- `mise exec -- npm ci` installed the root workspace lockfile.
- `mise exec -- npm run lint` passed Ruff, typed ESLint/Astro, Stylelint and
  formatting (213 Python files). `npm run test:lint` passed eight failing-input
  and valid-exception probes.
- `mise exec -- npm run check` passed both sites: 25 installer and 38 Flyover
  files, zero diagnostics.
- `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tools/Tests -p 'test_flyover*.py'`
  passed **91 tests**. Controllers, retention and publication use test doubles or
  temporary directories; this did not publish or delete remote artifacts.
- `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=Tools/Tests python3 -m unittest test_installer_update_feed test_installer_update_site`
  passed **43 tests** after the shared-site extraction.
- `./attribution --check` passed with 29 credits; ShellCheck and SF Symbol lint passed.
- `./snapshot-shards check` passed: 70 suites, assignments 13 / 18 / 17 / 22 + 0 intake.
- `./test --architecture-only` passed configuration validation, **28 rule tests**
  and architecture lint, including the new graph mutation guards.
- `./sync-agents`, complete-branch diff checks, Markdown links, tracked inventory
  and preservation of main's new backlog entries and completed history passed.

This host is macOS. The pass remains a focused static audit plus the checks above;
the skill's Linux/Tuist/Xcode/simulator limitation remains explicit. The final PR
changes only Markdown relative to its new main base. No new app rendering,
VoiceOver, navigation, scroll reachability, device/signing, CloudKit or timing
validation is claimed. The browser implementation was reviewed at its changed
contracts and filed-finding seams; this is not an exhaustive review of every new
TypeScript/CSS line. Browser end-to-end and Swift UI/image suites were not rerun.
Linux portability findings remain open. New main findings and completed history
are preserved, and unmerged work remains outside the cutoff.
