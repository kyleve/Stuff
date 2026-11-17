# Compatibility access and review follow-up

## Planning checkpoint

- Updated: 2026-11-17, starting at `743f8c96a059bdee05a7f97c26e377a76f78c43c`.
- Operation: plan and execute the second human review of [PR #495](https://github.com/kyleve/Stuff/pull/495), explicitly approved in the conversation on 2026-11-17.
- Stage: plan 01 executing; reviewed plan published in `a0f844ec9`.
- Completed: read all 17 new comments across 14 threads and their earlier discussion; source review confirmed local bypasses, signed-out lockout, unchecked widget snapshots, and repeated lockout presentation.
- Pending: finish verification and publication for [01](01-unified-access.md); refine 02/03 at their recorded triggers.
- Next action: publish verified 01 and its replies, then review/promote the refined 02 draft. The final 55-test rerun passed after the full-suite fixture fixes; 53 formal outcomes matched expectations and independent source/model review is complete.

## Outcome and scope

Use one compatibility decision path across cloud and local installations, support local operation without an iCloud account, and require compatible access before extensions read or open user data. Preserve pre-open admission, recorder-only cloud publication, monotonic version evidence, and whole-scope retirement. Simplify the lockout presentation and move foreground business work behind the app runtime.

This series follows the completed [ownership review](../2026-11-17-compatibility-review/README.md). Its completion record remains unchanged. [STU-334](https://linear.app/kve/issue/STU-334) owns this selected work, following [STU-333](https://linear.app/kve/issue/STU-333). [STU-335](https://linear.app/kve/issue/STU-335) owns the deferred onboarding/session model split.

## User stories

| ID | Story |
| --- | --- |
| US-01 | A user without iCloud can use local history without bypassing a known incompatible data version. |
| US-02 | A user sees a consistent compatibility decision in the app, share extension, and widgets. |
| US-03 | Maintainers exercise the same coordinator behavior in Development and shipping builds and can follow lifecycle ownership. |

## Requirements

| ID | Requirement | Story | Plan |
| --- | --- | --- | --- |
| R-01 | Require a transport/receipt dependency; local builds use a local implementation rather than an absent coordinator backend. | US-03 | [01](01-unified-access.md) |
| R-02 | Distinguish configured-local, available cloud account, confirmed no account, and unavailable/restricted account states. Allow safe local operation without an account, retain the highest known version, and verify before enabling cloud sync. | US-01 | [01](01-unified-access.md) |
| R-03 | Keep compiler selection in host build environments. One resolved policy drives store configuration, transport, and extension access. | US-03 | [01](01-unified-access.md) |
| R-04 | Require share-extension access checking in every environment; production checks remain local and precede opening history. | US-02 | [01](01-unified-access.md) |
| R-05 | Centralize transport setup/error handling and schema constants, rename the observed version to `PersistedDataModelVersion`, and make identity provenance explicit. Preserve account checks around suspension points and wire identifiers. | US-03 | [01](01-unified-access.md) |
| R-06 | A shared App Group reader checks receipt and widget payload provenance; incompatible access yields a blocked widget state. Request widget reload on access withdrawal/recovery. | US-02 | [02](02-widget-access.md) |
| R-07 | Keep one lockout presentation across startup and running states; retain the orchestration gate and immediate history masking. | US-02 | [03](03-presentation-runtime.md) |
| R-08 | The runtime owns foreground refresh/poll/session work, receiving scene lifecycle signals. Preserve headless launch and first visible reveal behavior. Rename startup `release()` to `shutdown()`. | US-03 | [03](03-presentation-runtime.md) |
| R-09 | Extend relevant Swift and PlusCal coverage, maintain module contracts, publish checked commits, and reply individually to all addressed/deferred human threads. | All | All |

## Not required and explicitly avoided

| ID | Exclusion | Reason |
| --- | --- | --- |
| X-01 | No per-data-API compatibility checks, migration engine, or per-entity versioning. | The authorized boundary remains whole-scope admission and retirement. |
| X-02 | No widget SwiftData container or duplicated aggregation. | Widgets keep consuming small published JSON values. |
| X-03 | No authentication-error fallback that erases a known floor or grants unverified cloud access. | Missing accounts and temporary failures have different meanings. |
| X-04 | No session-only `WhereModel` redesign in this PR. | The user approved a separate onboarding/model follow-up. |
| X-05 | No merge, review-thread resolution, or Production schema deployment. | Delivery ends with the existing open PR and review replies. |

## Discovery, research, and evidence

- At `743f8c96a`, `DataCompatibilityCoordinator.init()` creates an allowed state with no backend; Development and many fixtures never exercise verification. The share extension similarly accepts a nil receipt dependency.
- `CloudKitDataCompatibilityTransport.accountID()` calls `userRecordID()`. The coordinator blocks failed lookup, so there is no supported signed-out local mode. [Apple documents](https://developer.apple.com/documentation/cloudkit/ckcontainer/fetchuserrecordid(completionhandler:)) that disabled/restricted/missing accounts can share an authentication error. [Account status](https://developer.apple.com/documentation/cloudkit/ckaccountstatus) distinguishes them.
- The receipt loads before account lookup and preserves a monotonic floor. `accountNotificationBeforeFirstCheckPreservesTheCachedFloor` and `higherCacheCannotSubstituteForSharedPublication` guard important distinctions. A local grant must not become cloud publication evidence.
- `SwiftDataStore.Storage` selects `.automatic` versus `.none` CloudKit configuration when constructing a container. Bootstrap currently captures that storage once. Changing account mode therefore needs explicit retirement and re-admission before another container is opened.
- Widgets read `WidgetSnapshotStore` and `WidgetPresentationStore` independently, without a receipt. Data and presentation have independent publication lifetimes. Preserve that separation behind shared access APIs.
- `RootView` renders the lockout in three places. The outer branch masks every lifecycle phase; the monitor already completes the compatibility gate after admission. LifecycleKitUI requires a registered gate view and owns first-visible splash behavior.
- [Apple scene lifecycle guidance](https://developer.apple.com/documentation/uikit/managing-your-app-s-life-cycle) distinguishes scene activity from process launch. Keep scene input while moving work into the runtime.
- Existing PlusCal publication cases explicitly exclude local-only operation. Account/mode changes need new modeled evidence, not a claim that old passing cases cover them.

## Invariants and existing guards

| Owner | Invariant | Existing guard / required extension |
| --- | --- | --- |
| WhereCore/AGENTS.md | Metadata outside SwiftData; monotonic floor; only eligible recorder publishes remotely | Coordinator/receipt tests, CompatibilityPublication; extend for local/cloud transitions |
| WhereUI/Sources/Launch/AGENTS.md | Gate all opens, mask history before teardown, stop GPS before draining | Compatibility/launch tests and CompatibilityLockout; retain held-work regressions |
| Where/AGENTS.md | Runtime composes one coordinator and installation location owner | Bumper ownership rules; rerun architecture checks |
| WhereShareExtension/AGENTS.md | Local access check before store open; no CloudKit entitlement | Receipt/access tests; replace optional bypass with required implementation |
| WhereWidgets/AGENTS.md | Published values only; no direct history-store access | Snapshot/presentation store tests and widget snapshots; add blocked/provenance coverage |
| Shared/LifecycleKitUI/AGENTS.md | Registered gates, scene-aware first reveal, no headless view tree | Existing lifecycle tests; retain boundaries while simplifying RootView |

## Execution order and planning horizon

| Order | Plan | Deliverable |
| --- | --- | --- |
| 1 | [Unified access](01-unified-access.md) | Explicit local/cloud backend, account transitions, required extension access, transport cleanup, formal coverage |
| 2 | [Widget access](02-widget-access.md) | Receipt-aware widget reads, payload provenance, blocked UI, reload on access changes |
| 3 | [Presentation and runtime](03-presentation-runtime.md) | Single lockout view and runtime-owned activation behavior |

Detail 01 first. Refine 02 against its verified receipt/access API, then 03 against the final coordinator/runtime boundary. The user approved all three deliverables and execution without further confirmation between steps.

## Shared decisions and questions

| ID | Status | Decision / question | Source and integration |
| --- | --- | --- | --- |
| Q-01 | closed | Support safe local operation with no iCloud account; keep unavailable/restricted distinct and verify before sync resumes. | User approval of the review recommendation, 2026-11-17; R-02/X-03. |
| Q-02 | closed | Retain widget JSON and introduce compatibility-aware shared access. | Same approval; R-06/X-02. |
| Q-03 | closed | How does bootstrap obtain the admitted storage mode and retire before a local/cloud transition? | Source inspection: capture domain/epoch admission with store opening and real scope compatibility; resolve storage before construction and reject stale completion. Existing retirement drains the old container. Integrated into 01 design/acceptance and reviewed 2026-11-17. |
| Q-04 | closed | Defer the session/onboarding model split. | User approval; X-04. Tracked in [STU-335](https://linear.app/kve/issue/STU-335); the earlier STU-289 service/session extraction is complete and remains closed. |

## Feedback map

| Topic | Human threads |
| --- | --- |
| Development backend and build/account policy | [4605064573](https://github.com/kyleve/Stuff/pull/495#discussion_r4605064573), [4605082758](https://github.com/kyleve/Stuff/pull/495#discussion_r4605082758), [4605193700](https://github.com/kyleve/Stuff/pull/495#discussion_r4605193700) |
| Transport repetition and constants | [4605143998](https://github.com/kyleve/Stuff/pull/495#discussion_r4605143998), [4605151013](https://github.com/kyleve/Stuff/pull/495#discussion_r4605151013) |
| Widget access | [4605233370](https://github.com/kyleve/Stuff/pull/495#discussion_r4605233370) |
| Version and account identity naming | [4605261869](https://github.com/kyleve/Stuff/pull/495#discussion_r4605261869), [4605292193](https://github.com/kyleve/Stuff/pull/495#discussion_r4605292193) |
| Required share access / compiler boundary | [4605356076](https://github.com/kyleve/Stuff/pull/495#discussion_r4605356076), [4605373149](https://github.com/kyleve/Stuff/pull/495#discussion_r4605373149) |
| Deferred model split | [4605514550](https://github.com/kyleve/Stuff/pull/495#discussion_r4605514550) |
| Startup shutdown naming | [4605586498](https://github.com/kyleve/Stuff/pull/495#discussion_r4605586498) |
| Lockout presentation and runtime | [4605628078](https://github.com/kyleve/Stuff/pull/495#discussion_r4605628078), [4605644072](https://github.com/kyleve/Stuff/pull/495#discussion_r4605644072) |

## Plan review and delivery

Reviewed 2026-11-17 at `743f8c96a`: all requirements have an owner; 01 is ready, 02/03 remain selected outlines. The review added admission checks to held opens and real scope reuse, and kept a registered lifecycle gate to avoid terminal missing-gate failures. No material product question remains. Mermaid diagrams and Swift sketches will describe design, not compilation evidence. Physical CloudKit account transitions, cross-device propagation, and WidgetKit refresh scheduling require device acceptance and cannot be proven by fakes or bounded models.

Publish plans, implementation, and replies on [PR #495](https://github.com/kyleve/Stuff/pull/495). Implementation is authorized and plan 01 is executing. Mermaid syntax was inspected but not rendered; Swift sketches are not compilation evidence.
