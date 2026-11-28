# Repository review checks

Use only sections matching the changed behavior or a plausible failure mechanism.
The linked owner defines policy and exceptions; tests identify concrete regression evidence.
Keep history in the audit PR.

## Failure-pattern index

| Pattern | Probe |
| --- | --- |
| Copies of a data struct share mutable state | [Copy isolation](#domain-types-and-state) |
| Old/cancelled work publishes after a newer request | [Completion ordering](#domain-types-and-state) |
| A consumer creates another resource or retains an old session | [Launch and reset](#composition-and-transactions) |
| A write leaves sibling readers stale | [Transaction and reconciliation](#composition-and-transactions) |
| Display values become persisted identities | [Days and wire formats](#dates-and-persisted-data) |
| A fixture bypasses the production path | [Capture and fixtures](#rendering-and-fixtures) |
| Recovery overwrites another owner's files | [Publication boundaries](#tools-and-publication) |
| An isolated green test misses a linking failure | [Full-scheme linkage](#target-graph-and-guards) |

## Domain types and state

[Swift conventions](../../../../.agents/references/swift-conventions.md) own value semantics, domain identities, coupled state, parameter defaults, and error propagation.
When a data struct gains reference-backed state, trace a write through one copy and verify the original still reads its previous value. See `copyIndependence` in [BTraitsTests](../../../../Shared/Broadway/BroadwayCore/Tests/BTraitsTests.swift).
When two presentations or requests for the same entity can overlap, finish the older one and verify the newer one still has its state.

For completion ordering, release superseded work after the newer request finishes.
For failure state, fail a refresh after a successful result.
[UpdateModelTests](../../../../Shared/InstallerKit/Tests/UpdateModelTests.swift) guards both through `foregroundReentrySupersedesCancelledCheck` and `failedManualCheckKeepsLastResultAndOriginalError`.

## Composition and transactions

Use [launch ownership](../../../../Where/Guidance/launch.md#scopes-and-the-launch), [WhereCore](../../../../Where/WhereCore/AGENTS.md#shape--invariants), and [WhereIntents](../../../../Where/WhereIntents/AGENTS.md#invariants).
Probe pre-install intent access and reset/relaunch: [IntentServicesTests](../../../../Where/WhereIntents/Tests/IntentServicesTests.swift) and [WhereResetTests](../../../../Where/WhereUI/Tests/WhereResetTests.swift), including `loggingOutReleasesTheScopeBeforeTheNextLoginOpensOne`.

For store changes, probe a commit between snapshot acquisition and notification; see `readSnapshotRejectsCommitBeforeNotification` in [SwiftDataStoreTests](../../../../Where/WhereCore/Tests/SwiftDataStoreTests.swift).
Trace post-write reconciliation to widgets, reminders, reports, and intents.
[Data-resolution instructions](../../../../Where/WhereCore/Sources/DataResolution/AGENTS.md) own attribution and scan publication.
Constructor/transaction lint does not establish lifetime or reconciliation coverage.

## Inference and thresholds

Use the [flight inference contract](../../../../Where/WhereCore/Sources/DataResolution/Flights/AGENTS.md).
Challenge an absolute cutoff with a shorter/sparser event retaining independent corroboration, plus a contradictory observation that must keep the result unknown.
See [FlightDisplacementInferenceTests](../../../../Where/WhereCore/Tests/FlightDisplacementInferenceTests.swift) and `shortSparseFlightUsesCalculatedSpeedAndPreservesGroundPoints` in [FlightTrajectoryAnalyzerTests](../../../../Where/WhereCore/Tests/FlightTrajectoryAnalyzerTests.swift).

## Dates and persisted data

Use [Where dates](../../../../Where/Guidance/dates.md#dates), [storage contracts](../../../../Where/WhereCore/AGENTS.md#shape--invariants), and [wire-format conventions](../../../../.agents/references/swift-conventions.md#persistence-and-wire-formats).
Probe timezone changes and non-Gregorian calendars against [CalendarDayTests](../../../../Where/WhereCore/Tests/CalendarDayTests.swift).
Check implicit `.current` arguments as well as `Calendar.current`; the [calendar lint gap](../../../../.bumper/RULES.md#gregorian-calendar) is explicit.
Where's backup transformation and Periscope's historical raw records have different migration contracts.

## UI structure and Broadway

Use [building-ui](../../building-ui/SKILL.md) and the [Where stylesheet owner](../../../../Where/WhereUI/Sources/Shared/AGENTS.md#design-system--wherestylesheet).
[WhereStylesheetTests](../../../../Where/WhereUI/Tests/WhereStylesheetTests.swift) guards trait derivation and root propagation.
For large wrapped rows/Forms, a computed `some View` property does not bound the enclosing generic value like a nominal child view.
[FeatureGuidePageTests](../../../../Where/WhereUI/Tests/FeatureGuidePageTests.swift) and [LocationsViewTests](../../../../Where/WhereUI/Tests/LocationsViewTests.swift) carry local size guards, not universal budgets.

## Target graph and guards

Use [Package.swift](../../../../Package.swift), [Project.swift](../../../../Project.swift), and the [Bumper catalog](../../../../.bumper/RULES.md).
For package links, preserve the [WhereUI double-link exceptions](../../../../.agents/references/targets.md#never-double-link-a-product-whereui-already-carries).
An isolated bundle pass misses the full-scheme duplicate-copy failure guarded by `resolvesTraitAwareTokensFromTheBroadwayRoot` in [WhereStylesheetTests](../../../../Where/WhereUI/Tests/WhereStylesheetTests.swift).
Architecture guards live in [WhereArchitectureTests](../../../../.bumper/Tests/WhereArchitectureTests.swift) and [WhereProjectRulesTests](../../../../.bumper/Tests/WhereProjectRulesTests.swift).

## Rendering and fixtures

Use [SnapshotKitTesting](../../../../Shared/SnapshotKitTesting/AGENTS.md) for capture changes.
[assertHTMLSnapshots](../../../../Shared/SnapshotKitTesting/Sources/AssertHTMLSnapshots.swift) is an existing hosted pipeline integration; [its tests](../../../../Shared/SnapshotKitTesting/Tests/AssertHTMLSnapshotsTests.swift) cover constraints and cancellation.
For service-backed preview data, [InstallerPreview](../../../../Shared/InstallerKitUI/Sources/InstallerPreview.swift) demonstrates typed production-path fixtures.
Raw wire fixtures remain appropriate for serialization tests.
[SnapshotKit](../../../../Shared/SnapshotKit/AGENTS.md) owns lazy descriptor construction and readiness.

## Classified logging

Use [PeriscopeCore](../../../../Shared/Periscope/PeriscopeCore/AGENTS.md#invariants) and [macro authoring rules](../../../../.bumper/RULES.md#classified-periscope-events).
Macro lint cannot establish content safety or filtered-sink use.
Check independent grants and restrictive composition against `allRequiredControlsMustBeEnabled` and `personalDataIsNotAWildcard` in [LogExportPolicyTests](../../../../Shared/Periscope/PeriscopeCore/Tests/LogExportPolicyTests.swift).
[LogExportableTests](../../../../Shared/Periscope/PeriscopeCore/Tests/LogExportableTests.swift) and [LogErrorTests](../../../../Shared/Periscope/PeriscopeCore/Tests/LogErrorTests.swift) cover nested policies and structured errors.

## Tools and publication

Use [Tools](../../../../Tools/AGENTS.md) for root commands and [InstallerKit](../../../../Tools/InstallerKit/AGENTS.md) for signing/publication.

- Probe pre-commit, rollback, post-commit cleanup, and competing destinations. Guards: [FileTransaction](../../../../Tools/Tests/file_transaction_test.rb), [Flyover publication](../../../../Tools/Tests/test_flyover_publication.py), and the affected public-command tests.
- For Pages jobs that reuse a completed build, retry deployment and retention after a newer run on the same main SHA. The old attempt must neither publish nor displace newer queued work. Probe the current-run exception and failed identity lookup too; see `test_retry_reuses_only_the_latest_main_build` and `test_retry_preserves_the_newer_publication_waiting_behind_an_active_run` in [retention tests](../../../../Tools/Tests/test_flyover_retention.py), the [Pages workflow](../../../../.github/workflows/installer-pages.yml), and [publication ownership](../../../../Tools/AGENTS.md#flyover-publication).
- For skill-copy migration followed by external updates, fail the second fetch after the first skill changes, then retry. Matching copies must remain usable through the partial update; see `test_partial_update_can_retry_after_matching_copies_are_migrated` in [sync tests](../../../../Tools/Tests/sync_agents_test.rb) and the [migration ordering contract](../../../../.agents/references/agent-maintenance.md#shared-instructions-and-skills).
- For ownership-based deletion, probe inaccessible owners, retargeted checkout symlinks, and parent traversal before normalization. [Worktree cleanup tests](../../../../Tools/Tests/test_worktree_cleanup.py) cover these; preflight does not establish atomicity.
- For shared transport policy, inject failure below the default adapter, not only through an injected mock. Guards: [installer commands](../../../../Tools/Tests/test_circleci_distribution.py) and [shared client/poller](../../../../Tools/Tests/test_circleci_pipeline.py), including discarded-response cleanup.
- For setup/continuation, fail setup before the requested publication workflow exists; the poller must terminate without waiting for the publication deadline.
- For signing/controllers, trace trusted code and executable caches separately from selected PR source. Use a synthetic token in transport/argument failures and inspect child diagnostics too. [Signing state tests](../../../../Tools/Tests/signing_state_test.rb) guard redaction and retryable cleanup.
