# Where observable lifetimes

## Planning checkpoint

- Updated 2026-11-27 against main at `c41708712`.
- Operation is revision. Elsewhere retains its shared cache. Data Settings now owns cancellation of its export request.
- Stage is review follow-up for [PR #578](https://github.com/kyleve/Stuff/pull/578). [STU-350](https://linear.app/kve/issue/STU-350/tie-where-presentation-observables-to-their-owning-views) tracks the retained work.
- Test evidence and limits are recorded in [Settings](01-settings-destinations.md#execution-record), [Elsewhere history](02-elsewhere-flow.md#execution-record), and the [follow-ups](03-picker-editor-confirmation.md#execution-record).

## Outcome and scope

Create each selected presentation observable at the smallest stable SwiftUI identity that serves its consumers. Returning to a destination should get fresh presentation state. Navigation within a flow and layout changes should preserve the active draft or shared projection. Data cancels its export on dismissal. The session applies saved notification choices while their presentation is gone.

## User stories

| ID | Story |
| --- | --- |
| US-01 | As a Settings user, I can leave and return to Data or Alerts without inheriting stale export UI or losing a saved notification choice. |
| US-02 | Historical. As an Elsewhere user, I see the same resolved visits in the tab, day list, and map while evidence or the selected year changes. |
| US-03 | As a planner or diagnostics user, I get fresh search, error, and confirmation state on a new presentation, and my current stay draft survives layout changes. |
| US-04 | As a maintainer, I can see who creates each model and use the same presentation entry points for production, Flyover, and test fixtures. |

## Requirements

| ID | Required behavior or constraint | Story | Implementing plan |
| --- | --- | --- | --- |
| R-01 | Data owns its export model and request. Dismissal cancels the request and suppresses late UI. Reopening Data can start a new export. | US-01 | [01 — Settings destinations](01-settings-destinations.md) |
| R-02 | Alerts creates and owns its editing model, re-reads preferences and permission state, and reconciles saved reminder, summary, issue-alert, and badge intent even after dismissal. | US-01 | [01 — Settings destinations](01-settings-destinations.md) |
| R-03 | Withdrawn. The proposed Elsewhere flow would have owned resolution and optional place labels for the list, detail, and map. | US-02 | [02 — Elsewhere flow (superseded)](02-elsewhere-flow.md) |
| R-04 | Home picker search, load state, and selection errors belong to its presentation. The editor retains the tracked-region data its own form needs. Home continues to update the shared planning snapshot by the normal store-change path. | US-03 | [03 — Picker, editor, and confirmation](03-picker-editor-confirmation.md) |
| R-05 | The stay editor sheet creates one draft per presentation. The draft and in-flight save survive a compact or expanded layout transition and a nested picker. | US-03 | [03 — Picker, editor, and confirmation](03-picker-editor-confirmation.md) |
| R-06 | The diagnostics confirmation belongs to the presenting destination. The process still owns effective reporting state, policy application, and disclosure. | US-03 | [03 — Picker, editor, and confirmation](03-picker-editor-confirmation.md) |
| R-07 | Model hosts retain the intended identity across rendering and adaptive layout changes. Flyover, previews, and snapshots use the product boundary with injected deterministic dependencies or prepared fixtures where needed. | US-04 | [01](01-settings-destinations.md), [03](03-picker-editor-confirmation.md) |

## Exclusions

| ID | Boundary | Reason |
| --- | --- | --- |
| X-01 | Keep archive and persistence formats, notification timing and permission policy, and the existing recording and reporting rules. | The request changes ownership and presentation lifetime. |
| X-02 | Keep launch, compatibility, recording, and shared report and forecast ownership at their existing process, session, or scene boundaries. | Those state and work lifetimes serve multiple screens or headless operation. |
| X-03 | Keep map, card, and settings appearance and navigation intact. Use the existing host without requiring a general migration of view-local state, a new observation framework, or a launch performance target. | The audit selected specific ownership changes. |
| X-04 | Keep Elsewhere ownership and refresh behavior at the existing boundaries. Production geocoder cancellation and waiter ownership belongs to [STU-228](https://linear.app/kve/issue/STU-228/make-locationnamer-cancellation-aware). | The tab and gallery benefit from reusing one projection and place-name cache. |

## Context and discovery

The [implementation issue, STU-350](https://linear.app/kve/issue/STU-350/tie-where-presentation-observables-to-their-owning-views), comes from the 2026-11-27 source audit. The audit inventoried 56 observables. The owner initially selected six ownership changes and kept five after reviewing the Elsewhere tradeoff.

- Opening Settings currently initializes Backup and Reminders together. Leaving Data during export can outlive its presenter. Leaving Alerts after an edit must preserve the saved choice and its eventual schedule.
- Elsewhere can appear when a visit is recorded and disappear when its final visit is removed. Navigating from a card to its days and map must use one resolved result. A failed same-year refresh keeps the last good result visible with a retry.
- Opening Home again should start with fresh picker state. Returning from a nested picker or folding the device during an active stay edit must preserve that draft. An unconfirmed diagnostics choice belongs to the screen that requested it.

## Research and evidence

Source observations refer to `c41708712`. The choices in the plans are proposals for implementation. Repository code and existing tests establish the relevant contracts.

| Source observation | Implication |
| --- | --- |
| [ObservableHostingView](../../Where/WhereUI/Sources/Shared/ObservableHostingView.swift) calls its factory after mount and retains the result with view identity. Its initial body is clear. | Build the host at durable navigation boundaries. Preserve root navigation and keep mounted test evidence separate from initializer inspection. |
| [SettingsView](../../Where/WhereUI/Sources/Settings/SettingsView.swift) owns both objects, and [DataSettingsView](../../Where/WhereUI/Sources/Settings/DataSettingsView.swift) owns the share sheet. The [backup coordinator](../../Where/WhereCore/Sources/Backup/BackupCoordinator.swift) awaits a store read and detached archive encoding before recording the archive directory. | Tie the request to the Data view and reclaim an archive produced after cancellation. |
| [RemindersSettingsModel](../../Where/WhereUI/Sources/Settings/RemindersSettingsModel.swift) persists values before starting independent tasks. [WhereSession](../../Where/WhereUI/Sources/Model/WhereSession.swift) applies the same families at launch and foreground entry. | The saved choice is authoritative across presentations. Keep accepted scheduling work independent of the view and verify ordering with a held operation. |
| [YearReportModel](../../Where/WhereUI/Sources/Model/YearReportModel.swift) creates Elsewhere. The tab, detail, and gallery use its shared projection. | Keep the cache shared. The narrower lifetime would trade that reuse for unmeasured allocation savings. |
| [PlannedStaysModel](../../Where/WhereUI/Sources/Forecasting/PlannedStaysModel.swift) loads Home picker data for the planner and stores a model as its sheet item. [PlannedStayEditor](../../Where/WhereUI/Sources/Forecasting/PlannedStayEditor.swift) also reads tracked regions outside its picker. [PrivacyDiagnosticsSettingsView](../../Where/WhereUI/Sources/Settings/PrivacyDiagnosticsSettingsView.swift) binds its confirmation to the process reporting model. | Scope the Home instance separately, retain editor-owned tracked-region data, and separate confirmation UI from process policy. |

## Design and execution order

Each numbered plan contains its ownership flow and Swift architecture sketch.

| Phase | Order | Plan | Deliverable |
| --- | --- | --- | --- |
| 1 | 1 | [Settings destinations](01-settings-destinations.md) | Data owns Backup and Alerts owns Reminders. |
| 1 | 2 | [Elsewhere flow (superseded)](02-elsewhere-flow.md) | Retained as execution history. |
| 2 | 3 | [Picker, editor, and confirmation](03-picker-editor-confirmation.md) | The three smaller follow-ups stay together in a later phase. |

## Planning horizon

Both phases are complete. Phase 1's mounted checks and snapshots established the destination and fixture conventions used in Phase 2.

## Shared decisions

| Date | Decision and reason | Source |
| --- | --- | --- |
| 2026-11-27 | Phase 1 includes all three audit recommendations. Each smaller follow-up belongs to Phase 2. | User request |
| 2026-11-27 | Use the existing host with stable destination or flow identity. Preserve ordinary screen state while mounted, and let scope-owned services finish accepted operations independently. | Audit findings, host contract, and existing service boundaries |
| 2026-11-27 | Keep production model creation separate from prepared fixture construction. Verify settled capture and mounted interaction separately. | WhereUI presentation and snapshot contracts |
| 2026-11-27 | Withdraw the Elsewhere slice from this PR and keep the scene-owned projection and cache shared across the tab, detail, and gallery. | Owner approval after the tradeoff review |

## Questions and resolutions

No open product decisions. The [Phase 2 plan](03-picker-editor-confirmation.md) records the refinement trigger and its execution evidence.

## Plan review

- Reviewed on 2026-11-27 at `c41708712`. Traced the six selected changes through current owners, production and capture entry points, recovery, test suites, and the relevant module contracts.
- The review separated mounted dismissal and remount checks from model tests and settled captures. It also specified serialization across coordinator awaits, shared Elsewhere retry ownership, and fixture identity for artwork preparation.
- Initial review readied Plans 01 and 02 and left Plan 03 as an outline pending Phase 1 acceptance evidence.
- Static checks verified 72 local links, 12 test suite references, seven requirement mappings, and acyclic dependencies. All three Mermaid diagrams passed structural checks. Diagram rendering and app runtime were outside this verification. Swift sketches are pseudocode.
- Refined and reviewed Phase 2 on 2026-11-27 after both Phase 1 deliverables passed their scoped checks at `41de638f0`.

## Review and delivery

- Planning and implementation are recorded in [PR #578](https://github.com/kyleve/Stuff/pull/578), open for review against main.
- The pre-withdrawal simulator run passed 98 tests. The two snapshot runs passed 11 tests with recording disabled. The architecture run passed 30 rule tests and found no violations. Those runs verified the earlier revision.
- After withdrawal, independent review confirmed that all nine Elsewhere source and test files match the baseline. On iPhone 17 with iOS 27.2, 23 focused tests and five snapshot tests passed. Architecture checks passed, and snapshot recording was disabled.
- Review focus is dismissal during export, saved schedule ordering across presentations, and preservation of active editor state.

## Outcome

Five ownership changes remain in the PR. Physical-device sharing and a full interactive Flyover walkthrough were outside the simulator verification. [STU-350](https://linear.app/kve/issue/STU-350/tie-where-presentation-observables-to-their-owning-views) remains open pending merge and acceptance.
