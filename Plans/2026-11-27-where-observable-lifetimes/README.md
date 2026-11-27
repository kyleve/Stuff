# Where observable lifetimes

## Planning checkpoint

- Updated 2026-11-27 against main at `c41708712`.
- Operation is planning. The 2026-11-27 request selects Backup, Reminders, and Elsewhere from the ownership audit, followed by Home region selection, planned-stay editor presentation, and diagnostics confirmation in a separate phase.
- Stage is review handoff. The Phase 1 plans are ready and Phase 2 has a reviewed outline. [STU-350](https://linear.app/kve/issue/STU-350/tie-where-presentation-observables-to-their-owning-views) tracks implementation.
- Next action is plan review on GitHub. Implementation awaits a separate request.

## Outcome and scope

Create each selected presentation observable at the smallest stable SwiftUI identity that serves its consumers. Returning to a destination should get fresh presentation state. Navigation within a flow and layout changes should preserve the active draft or shared projection. Accepted work can finish through the service that owns it, with progress, errors, and prompts confined to their active presentation.

## User stories

| ID | Story |
| --- | --- |
| US-01 | As a Settings user, I can leave and return to Data or Alerts without inheriting stale export UI or losing a saved notification choice. |
| US-02 | As an Elsewhere user, I see the same resolved visits in the tab, day list, and map while evidence or the selected year changes. |
| US-03 | As a planner or diagnostics user, I get fresh search, error, and confirmation state on a new presentation, and my current stay draft survives layout changes. |
| US-04 | As a maintainer, I can see who creates each model and use the same presentation entry points for production, Flyover, and test fixtures. |

## Requirements

| ID | Required behavior or constraint | Story | Implementing plan |
| --- | --- | --- | --- |
| R-01 | Data creates and owns its export presentation model. Dismissal suppresses late UI, and a new Data presentation can export successfully while earlier work drains. | US-01 | [01 — Settings destinations](01-settings-destinations.md) |
| R-02 | Alerts creates and owns its editing model, re-reads preferences and permission state, and reconciles saved reminder, summary, issue-alert, and badge intent even after dismissal. | US-01 | [01 — Settings destinations](01-settings-destinations.md) |
| R-03 | One Elsewhere flow owns resolution and optional place labels shared by the list, day detail, and map. Preserve optional-tab selection, same-year retry, and stale-result protection. | US-02 | [02 — Elsewhere flow](02-elsewhere-flow.md) |
| R-04 | Home picker search, load state, and selection errors belong to its presentation. The editor retains the tracked-region data its own form needs. Home continues to update the shared planning snapshot by the normal store-change path. | US-03 | [03 — Picker, editor, and confirmation](03-picker-editor-confirmation.md) |
| R-05 | The stay editor sheet creates one draft per presentation. The draft and in-flight save survive a compact or expanded layout transition and a nested picker. | US-03 | [03 — Picker, editor, and confirmation](03-picker-editor-confirmation.md) |
| R-06 | The diagnostics confirmation belongs to the presenting destination. The process still owns effective reporting state, policy application, and disclosure. | US-03 | [03 — Picker, editor, and confirmation](03-picker-editor-confirmation.md) |
| R-07 | Model hosts retain the intended identity across rendering and adaptive layout changes. Flyover, previews, and snapshots use the product boundary with injected deterministic dependencies or prepared fixtures where needed. | US-04 | [01](01-settings-destinations.md), [02](02-elsewhere-flow.md), [03](03-picker-editor-confirmation.md) |

## Exclusions

| ID | Boundary | Reason |
| --- | --- | --- |
| X-01 | Keep archive and persistence formats, notification timing and permission policy, and the existing recording and reporting rules. | The request changes ownership and presentation lifetime. |
| X-02 | Keep launch, compatibility, recording, and shared report and forecast ownership at their existing process, session, or scene boundaries. | Those state and work lifetimes serve multiple screens or headless operation. |
| X-03 | Keep map, card, and settings appearance and navigation intact. Use the existing host without requiring a general migration of view-local state, a new observation framework, or a launch performance target. | The ownership audit selected six changes. |
| X-04 | Leave production geocoder cancellation and waiter ownership to [STU-228](https://linear.app/kve/issue/STU-228/make-locationnamer-cancellation-aware). | Elsewhere must reject late publication. Cancellation of shared underlying geocoder work is a separate contract. |

## Context and discovery

The [implementation issue, STU-350](https://linear.app/kve/issue/STU-350/tie-where-presentation-observables-to-their-owning-views), comes from the 2026-11-27 source audit and the user's selection of its three recommendations plus the three smaller follow-ups. The prior audit inventoried 56 observables. This series covers the six selected ownership changes.

- Opening Settings currently initializes Backup and Reminders together. Leaving Data during export can outlive its presenter. Leaving Alerts after an edit must preserve the saved choice and its eventual schedule.
- Elsewhere can appear when a visit is recorded and disappear when its final visit is removed. Navigating from a card to its days and map must use one resolved result. A failed same-year refresh keeps the last good result visible with a retry.
- Opening Home again should start with fresh picker state. Returning from a nested picker or folding the device during an active stay edit must preserve that draft. An unconfirmed diagnostics choice belongs to the screen that requested it.

## Research and evidence

Source observations refer to `c41708712`. The choices in the plans are proposals for implementation. Repository code and existing tests establish the relevant contracts.

| Source observation | Implication |
| --- | --- |
| [ObservableHostingView](../../Where/WhereUI/Sources/Shared/ObservableHostingView.swift) calls its factory after mount and retains the result with view identity. Its initial body is clear. | Build the host at durable navigation boundaries. Preserve root navigation and keep mounted test evidence separate from initializer inspection. |
| [SettingsView](../../Where/WhereUI/Sources/Settings/SettingsView.swift) owns both objects, and [DataSettingsView](../../Where/WhereUI/Sources/Settings/DataSettingsView.swift) owns the share sheet. The [backup coordinator](../../Where/WhereCore/Sources/Backup/BackupCoordinator.swift) awaits a store read and detached archive encoding before recording the archive directory. | The destination owns export UI. Overlapping submissions must account for coordinator reentrancy and archive ownership after dismissal. |
| [RemindersSettingsModel](../../Where/WhereUI/Sources/Settings/RemindersSettingsModel.swift) persists values before starting independent tasks. [WhereSession](../../Where/WhereUI/Sources/Model/WhereSession.swift) applies the same families at launch and foreground entry. | The saved choice is authoritative across presentations. Keep accepted scheduling work independent of the view and verify ordering with a held operation. |
| [YearReportModel](../../Where/WhereUI/Sources/Model/YearReportModel.swift) creates Elsewhere, but tab visibility derives from report input. [ElsewhereView](../../Where/WhereUI/Sources/Elsewhere/ElsewhereView.swift) passes its model to [RegionDaysView](../../Where/WhereUI/Sources/Elsewhere/RegionDaysView.swift). | The Elsewhere flow can own one model, while the report still determines the tab and supplies the full refresh input. |
| [PlannedStaysModel](../../Where/WhereUI/Sources/Forecasting/PlannedStaysModel.swift) loads Home picker data for the planner and stores a model as its sheet item. [PlannedStayEditor](../../Where/WhereUI/Sources/Forecasting/PlannedStayEditor.swift) also reads tracked regions outside its picker. [PrivacyDiagnosticsSettingsView](../../Where/WhereUI/Sources/Settings/PrivacyDiagnosticsSettingsView.swift) binds its confirmation to the process reporting model. | Scope the Home instance separately, retain editor-owned tracked-region data, and separate confirmation UI from process policy. |

## Design and execution order

Each numbered plan contains its ownership flow and Swift architecture sketch.

| Phase | Order | Plan | Deliverable |
| --- | --- | --- | --- |
| 1 | 1 | [Settings destinations](01-settings-destinations.md) | Data owns Backup and Alerts owns Reminders. |
| 1 | 2 | [Elsewhere flow](02-elsewhere-flow.md) | Elsewhere owns the model shared by its tab and detail. |
| 2 | 3 | [Picker, editor, and confirmation](03-picker-editor-confirmation.md) | The three smaller follow-ups stay together in a later phase. |

## Planning horizon

Detail both Phase 1 deliverables now. Settings provides the smallest proving ground for destination lifetime and operation ownership. Elsewhere has a distinct shared navigation boundary and can be verified independently. After both Phase 1 deliverables meet acceptance, refine Phase 2 in place using the mounted navigation and fixture evidence from Phase 1.

## Shared decisions

| Date | Decision and reason | Source |
| --- | --- | --- |
| 2026-11-27 | Phase 1 includes all three audit recommendations. Each smaller follow-up belongs to Phase 2. | User request |
| 2026-11-27 | Use the existing host with stable destination or flow identity. Preserve ordinary screen state while mounted, and let scope-owned services finish accepted operations independently. | Audit findings, host contract, and existing service boundaries |
| 2026-11-27 | Keep production model creation separate from prepared fixture construction. Verify settled capture and mounted interaction separately. | WhereUI presentation and snapshot contracts |

## Questions and resolutions

No open product decisions. Phase 2 records its refinement trigger and evidence needs in its numbered outline.

## Plan review

- Reviewed on 2026-11-27 at `c41708712`. Traced the six selected changes through current owners, production and capture entry points, recovery, test suites, and the relevant module contracts.
- The review separated mounted dismissal and remount checks from model tests and settled captures. It also specified serialization across coordinator awaits, shared Elsewhere retry ownership, and fixture identity for artwork preparation.
- Plans 01 and 02 are ready. Plan 03 remains an outline until Phase 1 acceptance evidence is available.
- Static checks verified 72 local links, 12 test suite references, seven requirement mappings, and acyclic dependencies. All three Mermaid diagrams passed structural checks. Diagram rendering and app runtime were outside this verification. Swift sketches are pseudocode.

## Review and delivery

- Plan review PR pending.
- Implementation awaits a separate request.
- Review focus is dismissal during export, saved schedule ordering across presentations, Elsewhere refresh identity, and preservation of active editor state.

## Outcome

Implementation has not started.
