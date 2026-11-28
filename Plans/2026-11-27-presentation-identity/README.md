# Presentation identity and repeatable events

## Checkpoint

The user requested an inventory and implementation on November 27. Discovery starts from main after #578 merged. Inspect the open PR changes and existing consumers, review the numbered plan, then implement and publish it.

## Stories and requirements

- S-01. A reviewer can recognize where an editor or animation begins and which completion belongs to it.
- S-02. A reviewer can recognize a repeatable UI action even when its input stays the same.
- R-01. Store a fresh PresentationID<Owner> for each opening or animation run. Preserve it across phases and check it at delayed completion.
- R-02. Fire an EventTrigger for an observable repeatable event. Preserve when consumers receive feedback or restart work.
- R-03. Inventory production Swift on main and additions in open PRs. Record matches, classification boundaries, and verification.
- X-01. Preserve domain identities, ordered revisions, ordinary counts, and asynchronous request cancellation contracts.

## Questions

Q-01 (closed). The user approved separate owner-typed presentation IDs and value-based event triggers. Both stories and R-01 through R-03 incorporate that decision.

## Inventory

Main at fd274c719 includes the [planner discussion](https://github.com/kyleve/Stuff/pull/578#discussion_r4724858956). The inventory follows fresh UUIDs, counter advances, task keys, item presentation, animation, feedback and completion consumers in production Swift.

| Contract | Producers and consumers |
| --- | --- |
| One presentation | PlannedStaysModel.EditorRoute, CalendarZoomTransitionState.Source and Plan, LocationCardsPresentationModel.OvertakeMovement and OvertakeEvent, DeveloperToastCenter.Toast, PeriscopeViewer.NDJSONExport |
| One failure displayed | DevicesSettingsModel.Failure and DeviceSettingsRowModel.OperationFailure |
| Repeatable effects | LocationCardsPresentationModel.feedbackTrigger, CalendarPresentationState.rejectionCount, AppIconView.appearanceToggles |
| Explicit retry or refresh | ElsewhereView and RegionDaysView retrySequence, YearReportModel.manualScanToken, WhereSession.notificationConfigurationRevision, InspectorSwiftDataModel.mutationGeneration, FlyoverFrameState.generation |
| Data or operation identity (X-01) | RegionCardLocations.ID and YearReportModel.evidenceRevision identify snapshots. Diagnostic reporting, scanner, artwork, export preparation, location forecasts, Elsewhere and Flyover loaders guard asynchronous reads. BScrollPosition.userRevision guards restoration. FlyoverPreviewReadiness.expectationGeneration counts changed expectations for tests. Recording, compatibility, storage, tracing and installer revisions have separate domain contracts. |

All 24 then-open PRs were scanned using the merge base with each PR's own base and its head. #585 at 897ff79ef adds CalendarSelection.ID, #579 at 39d7751e6 adds PhotoStayReviewView.EditSelection.id, and #462 at 4b7bcd4b2 moves an existing app-icon trigger consumer into AppIconPreviewPanel (also inherited by #464). #579's photo scan attempt, #306's backup request and invalidation tokens, #312's camera RunID, and #293/#295's polling, frame and worker generations guard asynchronous operations. The other inspected PRs were #47, #185, #353, #418, #424, #425, #454, #458, #460, #461, #484, #547, #570, #573, #575 and #577.

## Execution order and review

[01 — Migrate presentation lifetimes and triggers](01-migrate.md) implements R-01 through R-03. [STU-351](https://linear.app/kve/issue/STU-351) tracks delivery. The November 27 plan review traced both stories to allocation, consumption, cancellation, and tests. BroadwayCore already supplies value types to WhereUI, PeriscopeTools and Flyover. Inspector needs an explicit dependency to share the same event type. The diagram describes ownership and has been checked as text. Independent code review and runtime verification follow implementation.
