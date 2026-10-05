# Where 1.0: first external TestFlight release

Where helps people who split their time between regions understand their
region-by-day history. This release must establish useful history during
onboarding, record new activity reliably, and make gaps and recovery clear.

The target is an **external TestFlight beta for iPhone and iPad** on
iOS/iPadOS 27, matching [the target manifest](Project.swift). Required additions
are guided historical stays, optional photo history, and encrypted backups.
Release follows the readiness milestones below, with no calendar deadline.

**Status: planned.** This document records decisions and evidence. It does not
mean that the app changes or device acceptance checks are complete.

Start with the [milestones](#readiness-milestones), then the
[PR decisions](#appendix-a-open-pr-inventory-and-integration-decisions) and
[complete backlog review](#appendix-coverage).

## How to use this roadmap

The [canonical backlog](TODOs.md) owns issue details and priority buckets.
This document selects work for the beta and records completion criteria.
Each milestone points to its owning backlog. The appendices cover every item
and PR in the review baseline, including work excluded from this release.

| Disposition | Meaning |
| --- | --- |
| Required | Complete the stated work or acceptance check before external distribution. |
| Conditional | Apply the row's explicit trigger. Record whether it applies and the resulting evidence. |
| Deferred | Keep the item in the backlog for a later release. |
| Outside scope | The item belongs to another product or administrative concern. |
| Already addressed | The stated work is complete or represented by another canonical item, as explained in the row. |

A Required selection does not promote a P2 item to P0. A Deferred selection
does not erase an existing P0. A required measurement does not pre-approve an
unmeasured optimization. Review each conditional trigger against the final build.

When selected work lands, update its canonical TODO and the release evidence
below. Retain the dated baseline links so the original coverage remains auditable.
File new findings in the owning TODO before adding their release selection.

## Review baseline

- **Review date:** October 4, 2026, America/Los_Angeles.
- **Source:** [`bfc0c94d`](https://github.com/kyleve/Stuff/commit/bfc0c94d959207692f4636d12c2f2867b4c73fc5), which matched remote `main` during planning.
- **Checkout:** clean before this documentation change. No uncommitted app changes formed part of the baseline.
- **Coverage:** 21 open PRs and 133 explicit open TODO entries across 12 files.
- **Counting:** nested typed TODO bullets count separately. Untyped explanations and checklists remain part of their parent entry.
- **Inbox:** no open notes. Completed TODO sections were excluded from the open inventory.
- **Audit:** [`MODULE_AUDIT.md`](MODULE_AUDIT.md) is dated September 28. Current source, including merged flight work in #315, takes precedence.
- **Method:** source inspection, backlog review, PR metadata, and targeted diffs. No new app tests or signed-device checks support this document.

The 133-entry inventory is fixed to this source commit. New launch tasks appear
separately, so filing them does not silently change the review baseline.
PR checks are dated observations, not a claim about the final combined build.

## Readiness milestones

### 1. Establish the beta baseline

**Canonical work:** [Where backlog, P1](Where/TODOs.md#p1s-should-do), the beta
backup-upgrade task and existing photo-history item.

Admit encrypted backups from [#306](https://github.com/kyleve/Stuff/pull/306)
and rework photo history from [#201](https://github.com/kyleve/Stuff/pull/201).
Resolve both against current flight corrections, recording consent, and the
final archive format. A clean merge alone does not prove semantic compatibility.

Keep the compatibility stack #333 → #334 → #329 → #335 → #331 optional.
If it lands independently, respect its existing gates and archive contract.
Do not require general in-app migration, lazy upcasting, or historical
mixed-build support to prepare this beta.

The app currently exists on the owner's device only. The upgrade path is
export → external transform → import. The
[upgrade script](Where/Tools/upgrade-backup.rb) already supports main's v6
archive. Update it alongside each admitted schema change, using the final
format rather than reserving a guessed version now.

Preserve the source backup. Validate an upgraded copy through the
[backup-upgrade workflow](.agents/skills/upgrade-where-backup/SKILL.md), including
the production `BackupService` reader and referenced assets.

**Exit:** The chosen build loads the upgraded personal backup with expected
records and assets intact. Record the source/destination formats, build, and
validation results. An actual backup has not yet been supplied for this check.

### 2. Make onboarding establish useful history

**Canonical work:** [Where backlog, P1](Where/TODOs.md#p1s-should-do), guided
current-year history, photo import, manual range coverage, and contextual
notification consent.

Use this flow:

1. Give a brief introduction and select regions.
2. Enter historical stays for the current year through guided date ranges.
3. Optionally add photo-derived evidence.
4. Review the calendar, proposed entries, and remaining gaps.
5. Explain and configure recording on this device.

Reuse the existing manual-day and history services. Historical stays are
user-asserted history, separate from future itinerary planning in #316.
Users can review, correct, exclude, and approve photo-derived entries.
Keep their provenance distinct from automatic GPS.

Unconfirmed gaps remain unknown. A photograph does not establish residence
throughout the surrounding interval. Skipping history setup or Photos access
must still permit entry to the app. Explain when photo coverage is partial.

Retain restore and demo routes. Keep appearance customization secondary to
useful history. Preserve installation-local recording consent and phone/tablet
recommendations. Explain denied or limited permissions and the recovery action.
Request notification access only after an explicit, contextual choice.

**Exit:** A new user can enter and review a stay, skip or use Photos, identify
unknown days, and tell whether this device records automatically. No route
requires coaching, an unwanted permission, or invented history to complete.

### 3. Resolve history, recording, and accessibility defects

**Canonical work:** [Where](Where/TODOs.md#open-issues), the
[Gregorian guard](TODOs.md#p0s-must-do),
[JournalKit](Shared/JournalKit/TODOs.md#p2s-nice-to-have), and
[Periscope privacy tests](Shared/Periscope/TODOs.md#open-issues).

| Required outcome | Selected work |
| --- | --- |
| Historical attribution survives region deselection. | Retain the region information needed to interpret earlier GPS history. |
| Dates remain correct under non-Gregorian device calendars. | Fix display/helper calendars and the implicit-member architecture guard. |
| Published results follow local edits. | Reconcile summaries and widgets after day changes and region-selection changes, with regression coverage. |
| Loading and failures remain distinguishable from empty history. | Fix the full Timeline state and misleading badge/error fallbacks. |
| Recording failures remain observable. | Scope CloudKit readiness to the correct store, expose unavailable durable outboxes, and handle retry exhaustion honestly. |
| Full-sync failure cannot report success. | Propagate JournalKit's sync error before destructive follow-up. Preserve recoverable files and retry. |
| Core history and recovery remain accessible. | Fix calendar date truncation, year-picker overflow, and the maximum-text-size recovery action. Verify gallery semantics and phone/tablet reachability. |
| Privacy controls report their effective state and failures. | Fix diagnostic-apply errors and verify the closed remote-log field boundary. |

The JournalKit finding is a verified error-propagation gap: `F_FULLFSYNC`'s
return value is ignored. Actual location data loss was not reproduced.
Failure tests must not promise rollback of bytes already written or proof of
hardware power-loss durability.

**Exit:** No selected issue remains that can silently lose history, misstate
results, or block core onboarding/recovery. Each fix has relevant regression
or device evidence. Broader refactors remain deferred unless a fix requires them.

### 4. Prove encrypted recovery and daily operation

**Canonical work:** [Where backlog](Where/TODOs.md#open-issues), encrypted
backup acceptance, same-build device validation, and the existing stationary-day
and launch/write-frequency measurements.

Integrate #306 with the final onboarding, schema, and backup coordinator.
Exercise encrypted export/restore, recovery-key handling, independent offline
key creation, and subsequent iCloud synchronization. Explain that automatic
backups are encrypted while manual ZIP exports remain plaintext.

Use signed devices to exercise reboot before first unlock, ordinary relocking,
background expiration/cancellation, and iCloud Drive download/fallback recovery.
Verify the same-build iPhone/iPad flow for local recording choice, synced device
names, removal, and rejoining. Follow the existing
[CloudKit rollout procedure](Where/Where/README.md#cloudkit-rollout-and-device-validation)
for the final schema and deployment environment.

Measure stationary days without foreground use, passive movement capture,
launch/write frequency, and realistic-history performance. Cover midnight,
timezone changes, flights, manual corrections, and photo-derived history.
Compare app results with known inputs. Record unexplained gaps and publish
accurate limitations instead of promising an OS-guaranteed daily wakeup.

**Exit:** Signed-device evidence demonstrates usable recording, same-build
sync, and recovery. Critical gaps are resolved or the affected feature is
explicitly removed through a scope decision. No device result is currently claimed.

### 5. Prepare external TestFlight distribution

**Canonical work:** [Where backlog, P1](Where/TODOs.md#p1s-should-do), external
TestFlight readiness.

Complete onboarding usability checks, VoiceOver, large text, and permission-denied
paths. Record the final commit, version/build, CI results, device results, and
known limitations. Provide beta instructions, a feedback contact, accurate
privacy explanations, and review information.

Apple requires review of the first external TestFlight build. Keep approval
and tester availability as separate release steps after code acceptance.
See [Apple's external-testing instructions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers).

**Exit:** The reviewed build is approved and available to the intended external
tester group. Public App Store launch materials and distribution are a later milestone.

## Verification and release evidence

For this document, verify inventory completeness, source links, selections,
and unchanged backlog priorities. App tests and Swift formatting do not exercise
Markdown-only changes. Regenerate agent mirrors after the instruction change.

For implementation, use the [running-tests skill](.agents/skills/running-tests/SKILL.md).
Run focused `./test` checks during each change, including image checks for
changed UI. Use the pinned Xcode build for snapshot acceptance.

The final integration gate includes `./test --everything`, architecture checks,
format/catalog/attribution checks, and both audience builds. The live CI manifests
are [.github/workflows/ci.yml](.github/workflows/ci.yml) and
[.circleci/config.yml](.circleci/config.yml). They also run retained-tool checks
and the separate native-macOS suite. `./test --everything` alone is not every CI job.

| Area | Required scenarios |
| --- | --- |
| Onboarding | Skip, denied/limited permission, cancellation, retry, demo, restore, overlapping stays, unknown gaps, and repeated photo import. |
| History | Region removal, calendar systems, local edits, midnight/timezone changes, flight corrections, manual assertions, and mixed evidence sources. |
| Storage | Injected full-sync failure with original error, retained recoverable files, successful retry, and unchanged process-death behavior. |
| Backups | Ruby upgrader regressions, production archive/asset loading, final-format export/import, and encrypted key/recovery checks. |
| Accessibility | VoiceOver order and labels, maximum Dynamic Type, scrolling reachability, and phone/tablet permission-recovery screens. |
| Devices | Real same-build sync, installation-local consent, removal/rejoin, stationary/background recording, locked operation, and realistic-history performance. |

Simulator tests and old green PR checks cannot establish signed-device acceptance.
The personal pre-beta upgrade uses the external script. General migration
support remains deferred.

| Milestone | Current evidence | Completion evidence to record |
| --- | --- | --- |
| 1. Baseline | Main uses archive v6. Integration and personal-backup validation pending. | Final SHA/format, upgraded archive counts/assets, production-reader result. |
| 2. Onboarding | Existing flow and #201 reviewed. Guided history not implemented. | Usability results and focused unit/snapshot results for every route. |
| 3. Correctness | Required issues selected from source and backlog. Fixes pending. | Closing PRs and relevant regression/device results. |
| 4. Devices/recovery | Procedures and #306 reviewed. Physical acceptance pending. | Build/device/OS, scenario, expected/actual outcome, logs, and unresolved gaps. |
| 5. Distribution | Scope agreed. Final build, review, and availability pending. | Final CI/device evidence, beta instructions, review approval, tester availability. |

## Explicit deferrals

- Annual PDF export #164 and advanced future-stay planning #316.
- Mac support, public App Store launch, and a fixed release date.
- General schema migration/upcasting and historical mixed-build support.
- Broad controller, persistence-pipeline, build-system, and diagnostics redesigns.
- Porthole, Flagger, StorageKit, and other applications without a required beta dependency.

Deferred work stays in its canonical backlog or existing PR. The appendices
give individual reasons and conditional triggers rather than treating every
P0/P1 item as a beta prerequisite.

## Appendix A: open PR inventory and integration decisions

Observed **October 4, 2026, 8:00:55 p.m. PDT (America/Los_Angeles)**.
Source: GitHub through `gh pr list --state open --limit 100`, PR details, and targeted diffs.

The reviewed baseline contains **21 open PRs**. The refreshed inventory also contains **21**.
No PR entered or left that inventory. No baseline PR merged or closed.
The observed heads and bases are unchanged.
Remote `main` remains `bfc0c94d959207692f4636d12c2f2867b4c73fc5`.

Two pending check results changed since the earlier review.
#329's architecture check passed. #331's macOS check failed.
This inventory reports check results without diagnosing that failure.

Selected work supports external TestFlight for people who split their time across places, on iPhone and iPad.
The beta includes guided current-year stays, optional photo evidence, and encrypted backups.
PDF export and advanced future planning remain deferred.

### Complete reviewed inventory

**Required** means required beta work. **Conditional** means optional work that needs an explicit scope decision or independent merge.
**Deferred** means excluded from this beta. **Outside scope** means unrelated to the Where beta.

Counts describe reported GitHub check contexts, not test counts.
Latest contexts replace superseded cancelled runs with the same name.
Historical results predate current main and do not establish current integration safety.
“Blocked” is GitHub's merge state. It does not mean a merge conflict.
No stacked row with only three reported contexts establishes a fresh iOS integration run.

| PR and exact title | Decision | Observed merge/check state | Dependency or caveat |
| --- | --- | --- | --- |
| [#335](https://github.com/kyleve/Stuff/pull/335) — feat(WhereUI): expose live data feature availability | Conditional | Mergeable, blocked. 3/3 latest reported contexts passed. | After #329. Preserve live backup review if merged. |
| [#334](https://github.com/kyleve/Stuff/pull/334) — feat(WhereCore): establish data compatibility and backup contracts | Conditional | Mergeable, blocked. 3/3 reported contexts passed. | After #333. Adds backup v7 and shared data requirements. |
| [#333](https://github.com/kyleve/Stuff/pull/333) — fix(Flyover): preserve connectors in large catalogs | Conditional | Mergeable, clean. 8/8 reported contexts passed. | Base of compatibility stack. Fixes Flyover connectors, not beta behavior. |
| [#332](https://github.com/kyleve/Stuff/pull/332) — docs(github-workflow): explain API changes with code examples | Outside scope | Mergeable, clean. 8/8 reported contexts passed. | Independent workflow documentation. |
| [#331](https://github.com/kyleve/Stuff/pull/331) — refactor(WhereCore): scope UUID identities by domain | Conditional | Mergeable, blocked. macOS failed. Other 2 latest contexts passed. | After #335. Typed IDs preserve wire formats. Investigate failure before merge. |
| [#329](https://github.com/kyleve/Stuff/pull/329) — feat(Where): enforce data compatibility across app lifetime | Conditional | Mergeable, blocked. 3/3 reported contexts passed. | After #334. App enforcement and recovery, if selected. |
| [#317](https://github.com/kyleve/Stuff/pull/317) — feat(Porthole): add on-device investigations and phone-to-PR workflow | Deferred | Conflicting. Simulator compiler pairs and iOS CI failed. | Large debugger/AI workflow. Phone and App Review acceptance remain unproved. |
| [#316](https://github.com/kyleve/Stuff/pull/316) — feat(Where): add independent stays and configurable forecasts | Deferred | Conflicting. 8/8 historical contexts passed. | Future itinerary changes. Old planning and archive assumptions conflict with current work. |
| [#312](https://github.com/kyleve/Stuff/pull/312) — feat(Daylight): capture bay light with RAW preservation and Mastodon publishing | Outside scope | Mergeable, clean. 7/7 historical contexts passed. | Separate Daylight app. |
| [#306](https://github.com/kyleve/Stuff/pull/306) — feat(Where): add scheduled encrypted backups | Required | Mergeable, clean. 8/8 reported contexts passed. | Encrypted backups are required. Signed-device recovery acceptance remains. |
| [#295](https://github.com/kyleve/Stuff/pull/295) — Add NYC subway Transit view | Outside scope | Mergeable, blocked. 3/3 historical contexts passed. | After #293. Separate Throw feature. |
| [#293](https://github.com/kyleve/Stuff/pull/293) — feat(Throw): add ceiling flight projection app | Outside scope | Conflicting. 7/7 historical contexts passed. | Separate Throw app. |
| [#273](https://github.com/kyleve/Stuff/pull/273) — feat(Periscope): add classified event authoring | Conditional | Mergeable, clean. 8/8 reported contexts passed. | Logging foundation for #269. Optional hardening. |
| [#270](https://github.com/kyleve/Stuff/pull/270) — feat(Flyover): export a static QA atlas | Conditional | Mergeable, clean. 8/8 reported contexts passed. | Optional static QA atlas. No production feature dependency. |
| [#269](https://github.com/kyleve/Stuff/pull/269) — refactor(Logging): migrate app events to classified logging | Conditional | Mergeable, blocked. 3/3 latest reported contexts passed. | After #273. Broad logging migration, not a beta prerequisite. |
| [#260](https://github.com/kyleve/Stuff/pull/260) — fix(WhereUI): guard Settings navigation footprints | Conditional | Conflicting. Bumper Bowling failed. Other 5 contexts passed. | Reconcile with landed #327. Retain only needed navigation regression protection. |
| [#201](https://github.com/kyleve/Stuff/pull/201) — Import photo location history during onboarding | Required | Conflicting. 5/5 historical contexts passed. | Rework into guided history with optional photos. Stale backup v5 assumptions. |
| [#185](https://github.com/kyleve/Stuff/pull/185) — Add typed Flagger framework | Deferred | Mergeable, blocked. iOS build and aggregate CI failed. | Flagger is not wired into Where services. |
| [#164](https://github.com/kyleve/Stuff/pull/164) — Add annual PDF audit export | Deferred | Conflicting. 5/5 historical contexts passed. | PDF export excluded. Old audit path predates effective sample corrections. |
| [#131](https://github.com/kyleve/Stuff/pull/131) — Porthole: agent/MCP access to a running iOS app | Deferred | Conflicting. 3/3 historical contexts passed. | Older Porthole work overlaps #317. |
| [#47](https://github.com/kyleve/Stuff/pull/47) — Add StorageKit: containerized, mode-aware storage | Deferred | Conflicting. 2/2 historical contexts passed. | StorageKit has no required beta dependency. |

### Selected integration work

1. **Guided setup and #201:** Build a current-year stay review that permits manual entry, correction, and explicit unknown periods.
   Reuse optional photo evidence after reworking the branch.
   The existing photo draft only edits days with photo samples. It cannot fill unphotographed gaps.
   Its source-device heuristic cannot prove photo ownership and can omit useful history.
   Preserve photo provenance, repeat-import deduplication, and final installation-local recording consent.

2. **Encrypted recovery and #306:** Integrate automatic encrypted backups with the final onboarding, runtime, and archive format.
   Verify signed-device first-unlock behavior, ordinary locked recording, background expiration, recovery keys, restore, and iCloud Drive fallback.
   Verify normal sync and recording ownership on iPhone and iPad with the same beta build.
   Historical mixed-build migration is outside this milestone.

3. **External upgrade script:** Update `Where/Tools/upgrade-backup.rb` for the final selected data shape.
   Verify the existing owner's archive through upgrade and app import.
   Preserve current flight corrections and the selected photo provenance in that transformation.
   Do not add in-app migration, generalized upcasting, or a legacy-install support framework.

### Optional stacks and semantic overlap

The current compatibility chain is **main → #333 → #334 → #329 → #335 → #331**.
It is **not a beta prerequisite**. Existing data is on the owner's device, and the agreed upgrade path is the external script.
If this chain merges independently, selected work must honor its archive format, activation review, store guards, and recovery outcomes.
The chain does not add per-entity upcasting or an instantaneous stop across offline devices.

#306 and #201 overlap runtime composition, backup handling, services, and onboarding.
Clean Git mergeability against main does not prove their combined behavior.
The final selected tree needs its own test results and signed-device acceptance.

The logging chain is **main → #273 → #269**.
It changes event authoring and wire shapes but does not add a required user feature.
The separate Throw chain is **main → #293 → #295**.

#316's old backup v6 and planning shape cannot simply replace current v6 data semantics.
Historical stay entry for onboarding does not require its future-itinerary system.
#164's old audit read aggregates raw samples without current attribution revisions.
Any later PDF milestone must match the app's effective-history totals and preserve an explicitly raw appendix.

### Changes since the September 28 audit

GitHub lists these merges from September 28 onward:

- [#327 — fix(WhereUI): prevent Explore gallery stack overflows](https://github.com/kyleve/Stuff/pull/327), September 28.
- [#328 — docs: reconcile the September 28 backlog and module audit](https://github.com/kyleve/Stuff/pull/328), September 28.
- [#315 — fix(Where): recognize flights and wait for arrival before GPS corrections](https://github.com/kyleve/Stuff/pull/315), October 4.

#315 is the implementation change after the audit update.
It adds flight-aware corrections, immutable attribution revisions and reset tombstones, and backup format v6.
The external script and selected onboarding must preserve those records and effective-history semantics.
The PR does not establish production CloudKit schema deployment or live sync behavior.
Three optional archive tests lacked external inputs, so their skipped results are not evidence about the owner's archive.
Beta acceptance needs the selected build's schema and ordinary iPhone/iPad sync verification, without a broad migration project.

## Appendix coverage

The baseline appendices contain **133 unique entries**: 26 Required,
13 Conditional, 84 Deferred, 9 Outside scope, and 1 Already addressed by
another entry. Counts include parent entries and their typed dependents.
They are not estimates of PR count or implementation effort.

| Baseline file | Explicit open entries |
| --- | ---: |
| [Where](Where/TODOs.md) | 75 |
| [Repository](TODOs.md) | 11 |
| [Broadway](Shared/Broadway/TODOs.md) | 8 |
| [CreditKit](Shared/CreditKit/TODOs.md) | 1 |
| [Flyover](Shared/Flyover/TODOs.md) | 1 |
| [Inspector](Shared/Inspector/TODOs.md) | 4 |
| [JournalKit](Shared/JournalKit/TODOs.md) | 2 |
| [LifecycleKit](Shared/LifecycleKit/TODOs.md) | 1 |
| [Periscope](Shared/Periscope/TODOs.md) | 20 |
| [SnapshotKit](Shared/SnapshotKit/TODOs.md) | 1 |
| [SnapshotKitTesting](Shared/SnapshotKitTesting/TODOs.md) | 6 |
| [Ledger](Ledger/TODOs.md) | 3 |
| **Total** | **133** |

This change adds five required P1 entries to the Where backlog, for **138 open
entries after filing**. It expands the existing photo-import and JournalKit
items without moving their priority buckets. The new entries are listed at the
end of Appendix B and are excluded from the baseline count.

## Appendix B: Where backlog disposition

The current [Where backlog](Where/TODOs.md) owns the implementation tasks.
The table reviews every open Where entry at `bfc0c94d`, including nested bullets and the deferred snapshot list.
Its 75 rows are 65 parent or standalone entries and 10 nested entries, not 75 new tasks.
The baseline links remain stable when the current backlog changes.

The disposition is **23 required, 11 conditional, 40 deferred, and 1 already addressed by another entry**.
Required rows include measurements and parent entries, so this count is not a PR or task estimate.
Conditional work has an explicit trigger in its row.
Deferred work remains in the backlog with its existing priority.
L89 points to L35 and does not claim a shipped fix.

### Exploratory items

| Baseline | Backlog item | Disposition | Rationale or trigger |
| --- | --- | --- | --- |
| [L13](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L13) | Explore one explicit filesystem layout for store and sidecars | Deferred | The current item describes organization, not a verified loss of data. |
| [L14](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L14) | Re-shape the write path as an explicit pipeline | Deferred | Fix the existing notification and widget refresh paths before a pipeline redesign. |
| [L15](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L15) | Explore retaining a prior store in another folder on reset | Deferred | Folder rotation needs separate CloudKit and recovery design. |
| [L16](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L16) | Explore coverage for a stationary day when the app is never foregrounded | Required | Measure real-device day coverage. Change capture policy only if those results require it. |

### P0 items

| Baseline | Backlog item | Disposition | Rationale or trigger |
| --- | --- | --- | --- |
| [L19](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L19) | `DailySummaryReconciler.reconcile()` is absent from the post-day-change fan-out | Required | Local edits and GPS writes must refresh the scheduled summary. |
| [L20](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L20) | Mutate data and assert the summary notification body updates without a re-`configure` | Required | Add the local-write regression test with the summary fix. |
| [L21](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L21) | Measure automatic launch and GPS-write frequency before changing the movement threshold | Required | Measure launch, write, and energy behavior. A 1 km filter is not a preset requirement. |

### P1 items

| Baseline | Backlog item | Disposition | Rationale or trigger |
| --- | --- | --- | --- |
| [L24](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L24) | Scope initial CloudKit-import readiness to Where's expected store/container | Required | Onboarding must use the intended store's device list. |
| [L25](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L25) | Remove `StoredContext.CodingKeys` | Deferred | This removes redundant code without changing release behavior. |
| [L26](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L26) | Add an optional onboarding step that backfills the current year from photo GPS metadata | Required | Ship the optional photo import with local processing, review, provenance, deduplication, and skip. |
| [L27](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L27) | Scope diagnostic emission for Flyover's unactivated sibling demo world | Deferred | This concerns developer diagnostics. The sibling's user data and external effects are already isolated. |
| [L28](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L28) | `CalendarDay.displayDate` resolves through `Calendar.current` | Required | A non-Gregorian device must still show the correct stored day. |
| [L29](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L29) | `WhereServices.setPrimaryRegions(_:)` skips post-write reconciliation | Required | Region changes must refresh widgets and scheduled notifications. |
| [L30](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L30) | Soft-delete untracked regions | Required | Removing a selected region must not rewrite its past GPS days as Other. |
| [L31](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L31) | The retry queue evicts FIFO at its 1000-sample capacity | Required | Define the bounded loss policy and show recording degradation instead of hiding it in logs. |
| [L32](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L32) | `PresenceTimelineList` derives `[]` whenever `report.report` is nil | Required | Loading or failure must not appear as an empty history. |
| [L33](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L33) | Extract a shared `ReportLoadGate` | Deferred | The Timeline fix can use the existing loading pattern without a shared-view refactor. |
| [L34](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L34) | Split `WhereSession` into an always-on coordinator and a presentation model | Deferred | This is a broad ownership refactor with no demonstrated launch defect. |
| [L35](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L35) | `ManualDayView` range mode has no test coverage | Required | Pin the range flow that guided history uses, including both date controls. |
| [L36](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L36) | `RegionMapView` live `Map` branch is no longer constructed by any test | Conditional | Add focused coverage if launch work changes this branch or device checks reveal a map failure. |
| [L37](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L37) | Extract one shared region-selection form | Deferred | Reuse can accompany onboarding work, but consistency alone does not block release. |
| [L38](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L38) | Notification authorization is requested during launch, without context | Required | Request permission after an explained user choice. Launch must only reconcile existing authorization. |
| [L39](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L39) | Identify remaining invalid controller states before another state-machine rewrite | Deferred | No concrete remaining invalid state is identified by this item. |
| [L40](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L40) | Give the feature-discovery widget gallery a complete VoiceOver pass | Required | The release accessibility pass must distinguish each widget kind and family. |
| [L41](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L41) | Give the evidence feature-discovery panels clear accessibility semantics | Required | The release accessibility pass must make each walkthrough step understandable. |
| [L42](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L42) | Consolidate the share/add evidence form | Deferred | Two form implementations are maintainability work, not a confirmed release defect. |
| [L43](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L43) | Consider incremental year-report reads or memoization | Deferred | Keep the current architecture unless device checks demonstrate an unacceptable cost. |
| [L44](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L44) | Review whether the `.accessibilityIdentifier` modifiers are needed | Deferred | The item identifies no user-facing defect. |
| [L45](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L45) | Keep the current region visible after dismissing its welcome | Deferred | Persistent decoration is outside the agreed onboarding and accuracy work. |
| [L46](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L46) | Per-entity schema versioning and lazy upcasting for CloudKit sync drift | Deferred | The beta uses the external backup upgrader. General migration and mixed-version support are outside launch scope. |
| [L47](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L47) | Make record-to-value conversion a version-aware upcaster | Deferred | The agreed beta scope does not add in-app migration. |
| [L48](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L48) | Persist a `minReaderVersion` per entity | Deferred | A general cross-version reader protocol is outside this beta release. |
| [L49](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L49) | Make durable write-back an opportunistic read-repair process | Deferred | The agreed beta scope does not add record repair or a preservation program. |
| [L50](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L50) | Design the exclusion UX for data from a newer reader version | Deferred | Same-build device validation replaces mixed-version compatibility work for this beta. |
| [L51](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L51) | Fix the broken renderings pinned by the snapshot suite | Required | Close the calendar and Year accessibility defects. Treat the cosmetic badge child separately. |
| [L52](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L52) | The calendar day grid breaks at accessibility Dynamic Type | Required | Every date must remain complete and distinguishable at AX5. |
| [L53](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L53) | `YearView` overflows horizontally at AX5 | Required | The calendar and mode picker must fit without hiding history or controls. |
| [L54](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L54) | The Resolve toolbar badge sits awkwardly on the glass toolbar button | Conditional | Fix if the candidate clips the count or tap target. Defer alignment-only polish. |
| [L56](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L56) | Keep the welcome recovery action readable at maximum Dynamic Type | Required | Users must be able to read and activate the recording recovery action. |

### P2 items

| Baseline | Backlog item | Disposition | Rationale or trigger |
| --- | --- | --- | --- |
| [L59](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L59) | Distinguish stream completion from timeout in the HistoryObserver lifetime test | Deferred | The production source finishes its stream. This is a narrower test-precision improvement. |
| [L60](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L60) | Synchronize both coalesced callers before testing cancellation | Conditional | Fix if candidate runs expose this scheduling race or launch work changes the coalescing tests. |
| [L61](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L61) | Complete the welcome overlay's scrolling and iPad coverage | Required | Validate phone and tablet scrolling, first greeting, VoiceOver, and accessibility text sizes. |
| [L62](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L62) | Consider the user-assigned device-name entitlement | Deferred | Generic hardware names and editable nicknames are sufficient for this beta. |
| [L63](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L63) | Give the app a branded launch screen | Deferred | The launch-screen polish is outside the required onboarding and accuracy work. |
| [L64](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L64) | Make scene-scoped model wiring compiler-checked | Deferred | This is architecture hardening rather than a demonstrated release failure. |
| [L65](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L65) | Split `YearReportModel` further | Deferred | Keep the working model unless a required change needs a focused extraction. |
| [L66](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L66) | Move `RegionDays` and `RegionRanking` from WhereUI into WhereCore | Deferred | This changes layering without resolving a confirmed launch defect. |
| [L67](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L67) | `ReminderReconciler` contributes zero when the issue scan throws | Required | A failed scan must preserve honest badge state. |
| [L68](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L68) | Distinguish missing files from read failures in both widget stores | Conditional | Add the missing diagnostics if device checks expose file-read failures or launch work changes these stores. |
| [L69](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L69) | A failed remote-logging apply is unlogged and shows a Swift reflection dump | Required | Privacy controls need clear failure text and a local diagnostic event. |
| [L70](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L70) | Make `LocationNamer` cancellation-aware | Conditional | Fix if large-history device checks show excessive geocoding or delayed response after a year change. |
| [L71](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L71) | Replace the hardcoded English caption in `IntentSnippets` | Conditional | Required if the release advertises a non-English locale. Otherwise defer to the localization pass. |
| [L72](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L72) | Remove the orphaned `WhereFormat.locationCardEstimatedDays` helper | Deferred | Dead code cleanup does not change the release behavior. |
| [L73](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L73) | Surface the `applicationSupport()` to `NoOpLocationOutbox` fallback | Required | The app must not claim durable recording when retries cannot survive process death. |
| [L74](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L74) | Close the share-evidence and widget-midnight test gaps | Conditional | Add focused tests when launch work changes those paths. Device acceptance still covers the advertised extension behavior. |
| [L75](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L75) | Add `GeoJSONTests.swift` | Conditional | Add decoding and degradation tests if launch work changes the region data or decoder. |
| [L76](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L76) | Add the missing namesake test for `LocationNamer` | Conditional | Add cache and coalescing tests with the geocoding fix. The old calendar-scroll test request is obsolete. |
| [L77](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L77) | Test `RegionSpotlightIndexer` | Deferred | Retain device validation for advertised search behavior. Dedicated indexer coverage can follow. |
| [L78](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L78) | Close the WhereCore namesake-test debt | Deferred | A namesake count does not measure behavior coverage. The current recount is 69 of 148 files. |
| [L80](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L80) | Drop the remaining Core API parameter defaults | Deferred | This is convention cleanup. |
| [L81](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L81) | Finish the intent/viewer polish | Deferred | Trip shortcut discovery and developer-viewer styling are outside launch scope. App Group injection already shipped. |
| [L82](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L82) | Use a generated catalog symbol for `region.other` | Deferred | This is convention cleanup. |
| [L83](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L83) | Profile the security-print rosette | Conditional | Profile if device checks show slow scrolling or high energy use. Optimize only a measured bottleneck. |
| [L84](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L84) | Remove three source literals that create value-less catalog entries | Deferred | This is catalog cleanup. The date-number change can accompany the required calendar fix. |
| [L85](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L85) | Add a raw data browser | Deferred | This is a new power-user feature. |
| [L86](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L86) | Add comments to strings in the xcstrings files | Deferred | Add comments to new onboarding copy. Defer the catalog-wide pass. |
| [L87](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L87) | Use full-content snapshots for `DeveloperDemoLaunchSheet` | Deferred | This concerns a developer-only form. |
| [L88](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L88) | Move the pinned widget fixture instant away from midnight | Deferred | This is fixture cleanup rather than a production date defect. |
| [L89](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L89) | Fill the remaining snapshot matrix gaps | Already addressed | The remaining range case is row L35. This is a duplicate cross-reference, not a shipped completion. |
| [L90](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L90) | Add snapshots for four Settings-reachable screens | Conditional | Add cases for screens changed by launch work, prioritizing recording recovery and alerts. Device acceptance covers the existing recovery flow. |

### Deferred snapshot items

| Baseline | Backlog item | Disposition | Rationale or trigger |
| --- | --- | --- | --- |
| [L99](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L99) | Investigate the iPad AX5 sheet-offset shift | Deferred | Investigate a recurrence. Do not replace references to hide nondeterminism. |
| [L100](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L100) | Make the `root.LoggedIn` fixture retain its seeded sample report | Deferred | Other loaded-history snapshots cover content. This fixture improvement does not block release. |
| [L101](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L101) | Remove `AddEvidenceView` DatePicker wall-clock capture dependence | Deferred | Apply the existing date-picker stand-in when this screen gains snapshot coverage. |
| [L102](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L102) | Replace immediate settling and nested navigation in `appIcon.Default` | Deferred | Fix a reproduced capture failure without changing unrelated production behavior. |
| [L103](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Where/TODOs.md#L103) | Replace the `root.LoggedIn` post-ready settle floor with a completion signal | Deferred | Add a deterministic signal if this capture fails again. |

### New Where 1.0 backlog entries

Five new P1 entries in the [current Where backlog](Where/TODOs.md#p1s-should-do) own the newly agreed work.
The existing photo-import entry was expanded instead of duplicated.
These entries are separate from the 75-row baseline review.

| Exact backlog title | Launch outcome |
| --- | --- |
| [Build guided current-year history during onboarding](Where/TODOs.md#p1s-should-do) | Optional dated stays, one review with photo proposals, visible unknown days, and skip. |
| [Validate beta schema changes with the backup upgrader](Where/TODOs.md#p1s-should-do) | The external upgrader and actual-backup import checks support beta schema changes. No in-app migration or preservation program. |
| [Integrate encrypted backups and verify device recovery](Where/TODOs.md#p1s-should-do) | PR #306 works with the final archive and passes key, interruption, retention, and device-recovery checks. |
| [Validate capture and sync on devices with the same build](Where/TODOs.md#p1s-should-do) | An iPhone and iPad pass capture, consent, sync, freshness, and recovery checks with recorded evidence. |
| [Complete the Where 1.0 TestFlight release checks](Where/TODOs.md#p1s-should-do) | The candidate passes the required fixes, release configuration, privacy, accessibility, and distribution checks. |

The existing required photo task keeps its title: “Add an optional onboarding step that backfills the current year from the GPS metadata of photos in the user's library.”

## Appendix C: repository, shared-module, and Ledger backlog review

Review date: October 4, 2026. The baseline is commit `bfc0c94d959207692f4636d12c2f2867b4c73fc5`.

This inventory covers all 58 baseline entries: 11 repository entries, 44 shared-module entries, and 3 Ledger entries.
It includes the two typed dependent Periscope items. Untyped subtasks remain with their parent entries.
The disposition is 3 required, 2 conditional, 44 deferred, and 9 outside this release. Deferred includes one dormant and one declined item.
These release decisions do not change the existing P0, P1, or P2 buckets.
The baseline links preserve the reviewed entries. Each section also links to the current backlog, which owns the issue details.

### Repository — [current backlog](TODOs.md)

| Baseline item | Disposition | Reason |
|---|---|---|
| [L97: Gregorian calendar guard](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/TODOs.md#L97) | Required | Pairs with the production Gregorian fixes and prevents recurrence. |
| [L100: CI documentation](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/TODOs.md#L100) | Deferred | The launch gate points to both authoritative CI manifests. The broader documentation repair can follow. |
| [L103: Tool portability and cache hygiene](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/TODOs.md#L103) | Deferred | Includes shell status, Ruby discovery in two paths, and Python bytecode. These do not block the macOS gate. |
| [L109: Remove benchmark organization](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/TODOs.md#L109) | Outside scope | Administrative work, separate from the Where release. |
| [L110: Architecture graph mutation tests](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/TODOs.md#L110) | Deferred | Useful guard coverage, with no demonstrated production failure. |
| [L111: Missing feature-group documents](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/TODOs.md#L111) | Deferred | Where and Ledger documentation gaps do not prevent the beta. |
| [L114: Cache snapshot LFS objects](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/TODOs.md#L114) | Deferred | Performance work requires fresh measurements. |
| [L126: Native-macOS test tier](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/TODOs.md#L126) | Outside scope | This improves the Ledger workflow. |
| [L127: Replace the affected-bundle parser](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/TODOs.md#L127) | Deferred | The parser has direct tests. CI already selects complete suites. |
| [L128: Vendor the local package through Tuist](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/TODOs.md#L128) | Deferred | A broad build-system change introduces unnecessary release risk. |
| [L132: Dynamically link SnapshotKitTesting](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/TODOs.md#L132) | Deferred | Reconsider only if test bundles share a host process. |

### Broadway — [current backlog](Shared/Broadway/TODOs.md)

| Baseline item | Disposition | Reason |
|---|---|---|
| [L13: Catalog test host](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Broadway/TODOs.md#L13) | Outside scope | This affects the separate showcase app. |
| [L14: Catalog Broadway root](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Broadway/TODOs.md#L14) | Outside scope | This affects the separate showcase app. |
| [L15: Empty Catalog test suite](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Broadway/TODOs.md#L15) | Outside scope | This affects the separate showcase app. |
| [L16: Nested UIKit root observers](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Broadway/TODOs.md#L16) | Deferred | No current nested Where path demonstrates this latent issue. |
| [L19: Unchanged context invalidation](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Broadway/TODOs.md#L19) | Deferred | A performance improvement without a demonstrated launch failure. |
| [L20: Stylesheet cache eviction](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Broadway/TODOs.md#L20) | Conditional | Observe memory during the device soak. Implement eviction if measured growth blocks the gate. |
| [L21: Missing namesake tests](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Broadway/TODOs.md#L21) | Deferred | Coverage debt for three shared helpers. |
| [L22: Catalog documentation and gallery](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Broadway/TODOs.md#L22) | Outside scope | This affects the separate showcase app. |

### CreditKit — [current backlog](Shared/CreditKit/TODOs.md)

| Baseline item | Disposition | Reason |
|---|---|---|
| [L10: Validate GitHub slugs](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/CreditKit/TODOs.md#L10) | Deferred | The generator consumes repository-controlled pins. This is error reporting, not an injection defect. |

### Flyover — [current backlog](Shared/Flyover/TODOs.md)

| Baseline item | Disposition | Reason |
|---|---|---|
| [L17: Interactive surface coverage](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Flyover/TODOs.md#L17) | Deferred | Image coverage for a debug tool. |

### Inspector — [current backlog](Shared/Inspector/TODOs.md)

| Baseline item | Disposition | Reason |
|---|---|---|
| [L10: Quarantined search-field snapshot](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Inspector/TODOs.md#L10) | Deferred | A known image mismatch in a debug surface. |
| [L19: Bare-identifier relationship coverage](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Inspector/TODOs.md#L19) | Deferred | A debug-tool regression gap. |
| [L25: Additional image cases](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Inspector/TODOs.md#L25) | Deferred | A debug-tool coverage gap. |
| [L33: Fetch helpers hide errors](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Inspector/TODOs.md#L33) | Deferred | This affects developer recovery. App Store entry points exclude Inspector. |

### JournalKit — [current backlog](Shared/JournalKit/TODOs.md)

| Baseline item | Disposition | Reason |
|---|---|---|
| [L10: Surface concurrent-test append errors](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/JournalKit/TODOs.md#L10) | Deferred | Current count and order assertions already detect lost entries. |
| [L11: Full-sync error propagation and coverage](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/JournalKit/TODOs.md#L11) | Required | The unchecked sync result reaches the location outbox. Require observable errors before subsequent file removal. |

### LifecycleKit — [current backlog](Shared/LifecycleKit/TODOs.md)

| Baseline item | Disposition | Reason |
|---|---|---|
| [L10: Duplicate registration trap tests](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/LifecycleKit/TODOs.md#L10) | Deferred | Covers duplicate plan nodes and gate views. No production collision is established. |

### Periscope — [current backlog](Shared/Periscope/TODOs.md)

| Baseline item | Disposition | Reason |
|---|---|---|
| [L14: Span record modeling](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Periscope/TODOs.md#L14) | Deferred | A type-design change without a demonstrated launch failure. |
| [L15: Split pipeline and store responsibilities](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Periscope/TODOs.md#L15) | Deferred | Broad internal refactoring is unnecessary for the beta. |
| [L16: Readable scope identifiers](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Periscope/TODOs.md#L16) | Deferred | Avoid changes to persisted identities for readability alone. |
| [L17: Parent context hierarchy](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Periscope/TODOs.md#L17) | Deferred | An additional logging capability. |
| [L18: Resume surviving spans](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Periscope/TODOs.md#L18) | Deferred | Where has no production use of this policy. |
| [L19: Journal before store attachment](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Periscope/TODOs.md#L19) | Deferred | Early diagnostic events lack durable storage. This does not lose recorded location samples. |
| [L22: External journal attachments](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Periscope/TODOs.md#L22) | Deferred | Large diagnostic attachments remain outside the crash journal. |
| [L23: Multiple processes sharing the log store](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Periscope/TODOs.md#L23) | Deferred | Where extensions attach no Periscope store and remain OSLog-only. |
| [L24: Hierarchy count semantics](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Periscope/TODOs.md#L24) | Deferred | This affects the developer viewer. |
| [L27: RemoteLogField privacy tests](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Periscope/TODOs.md#L27) | Required | Pin approved categories, rejected values, and event-kind fields at the remote-export boundary. |
| [L28: Open-span containment semantics](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Periscope/TODOs.md#L28) | Deferred | This affects the developer viewer. |
| [L29: Dependent overlapping-span regression](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Periscope/TODOs.md#L29) | Deferred | Follows the containment decision in the preceding item. |
| [L30: Inject density preferences](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Periscope/TODOs.md#L30) | Deferred | This affects the developer viewer and test isolation. |
| [L31: Incremental tree updates](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Periscope/TODOs.md#L31) | Deferred | A developer-viewer performance improvement. |
| [L32: Dependent incremental inspector query](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Periscope/TODOs.md#L32) | Deferred | A developer-inspector performance improvement. |
| [L33: Rename scope derivation](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Periscope/TODOs.md#L33) | Deferred | An API readability change across many consumers. |
| [L34: Value-form emit overload](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Periscope/TODOs.md#L34) | Deferred | An additive logging convenience. |
| [L35: Inspect individual objects](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Periscope/TODOs.md#L35) | Deferred | An additional developer capability. |
| [L36: Eager store handle](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Periscope/TODOs.md#L36) | Deferred | The existing lifecycle already distinguishes unavailable and failed states. |
| [L37: Replace hosting smoke tests](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/Periscope/TODOs.md#L37) | Deferred | Image coverage for developer views. No new test-bundle infrastructure is necessary. |

### SnapshotKit — [current backlog](Shared/SnapshotKit/TODOs.md)

| Baseline item | Disposition | Reason |
|---|---|---|
| [L9: Isolate models across image variants](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/SnapshotKit/TODOs.md#L9) | Deferred | New launch fixtures must avoid shared mutable models until this change lands. |

### SnapshotKitTesting — [current backlog](Shared/SnapshotKitTesting/TODOs.md)

| Baseline item | Disposition | Reason |
|---|---|---|
| [L9: Accessibility parse errors crash the host](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/SnapshotKitTesting/TODOs.md#L9) | Conditional | Escalate if this prevents the required launch coverage. |
| [L10: Pipeline regression gaps](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/SnapshotKitTesting/TODOs.md#L10) | Deferred | Includes safe-area mapping, lazy convergence, environment parsing, and tile seams. |
| [L16: Reduce image settle cost](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/SnapshotKitTesting/TODOs.md#L16) | Deferred | Performance work must preserve readiness and native-chrome settling. |
| [L21: Byte-equality comparison shortcut](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/SnapshotKitTesting/TODOs.md#L21) | Deferred | Keep the measured rejection. Reconsider only after new evidence changes the tradeoff. |
| [L22: Skip comparison after cancellation](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/SnapshotKitTesting/TODOs.md#L22) | Deferred | Improves cancellation diagnostics in the test pipeline. |
| [L23: Inline duplicate-identifier guard](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Shared/SnapshotKitTesting/TODOs.md#L23) | Deferred | Additional test-author protection. |

### Ledger — [current backlog](Ledger/TODOs.md)

| Baseline item | Disposition | Reason |
|---|---|---|
| [L14: Gregorian spend calendar](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Ledger/TODOs.md#L14) | Outside scope | Ledger is a separate macOS app. |
| [L15: Missing namesake tests](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Ledger/TODOs.md#L15) | Outside scope | Ledger is a separate macOS app. |
| [L16: App-shell test bundle](https://github.com/kyleve/Stuff/blob/bfc0c94d959207692f4636d12c2f2867b4c73fc5/Ledger/TODOs.md#L16) | Outside scope | Ledger is a separate macOS app. |
