# Repository review checks

Use the sections selected by the changed behavior and its consumers.
Each section connects a concrete failure mechanism to its current owner and regression evidence.
Read the linked source and tests at the reviewed revision. The owning instructions define the rule and its exceptions.
Keep fix history in the audit PR. Update these routes when their owner or guard moves.

## Domain types and state

Read the root [type rules](../../../../AGENTS.md#types-state-and-api-design), [state rules](../../../../AGENTS.md#modeling-state), and [error rules](../../../../AGENTS.md#errors-and-failure).

Inspect changed property and parameter types for raw identity strings/UUIDs, multi-field tuples, and domain values unwrapped before a wire or storage boundary.
For coupled booleans/optionals, enumerate the combinations callers can construct. Compare with the owning model's enum or value type.
Check whether a new Core parameter default suppresses evidence or changes existing callers' behavior.
Trace a caught error into observable failure state and logging. Look for success-shaped empty results or strings replacing the original error.

Concrete starting points: [YearReportModel.LoadState](../../../../Where/WhereUI/Sources/Model/YearReportModel.swift) for coupled state and [SampleAttributionRevision.ID](../../../../Where/WhereCore/Sources/DataResolution/SampleAttributionRevision.swift) for domain identity.
These examples do not make every model use the same states. Check the changed model's own callers and matching tests.

## Composition and transactions

Read [Where scopes and launch](../../../../Where/AGENTS.md#scopes-and-the-launch), [WhereCore](../../../../Where/WhereCore/AGENTS.md#shape--invariants), and [WhereIntents](../../../../Where/WhereIntents/AGENTS.md#invariants).

Trace launch ownership through [WhereScope](../../../../Where/WhereUI/Sources/Model/WhereScope.swift), `WhereServices.forIntents(sharingStoreOf:)`, and `IntentServices.install/current`.
Probe an intent before installation and a reset followed by relaunch. Look for a second store factory or a consumer retaining the first session.
Compare [IntentServicesTests](../../../../Where/WhereIntents/Tests/IntentServicesTests.swift) and [WhereResetTests](../../../../Where/WhereUI/Tests/WhereResetTests.swift).
The latter's `loggingOutReleasesTheScopeBeforeTheNextLoginOpensOne` exercises the ownership boundary.

For store changes, follow reads through `readSnapshot`, writes through `perform`, and post-write work through the existing `DayJournal` reconciliation seams.
Check the expected generation after suspension and before commit. Inspect sibling consumers such as widgets, reminders, and intents.
Open [SwiftDataStoreTests.readSnapshotRejectsCommitBeforeNotification](../../../../Where/WhereCore/Tests/SwiftDataStoreTests.swift) for the durable-history race.
Use the scoped [data-resolution instructions](../../../../Where/WhereCore/Sources/DataResolution/AGENTS.md) for attribution and scan changes.
Constructor and transaction lint cannot establish the entire lifetime or reconciliation contract.

## Dates and persisted data

Read [Where dates](../../../../Where/AGENTS.md#dates), [WhereCore's storage contracts](../../../../Where/WhereCore/AGENTS.md#shape--invariants), and the root [wire-format rules](../../../../AGENTS.md#persistence-and-wire-formats).

Trace logical days as `CalendarDay`, textual keys as `iso8601`, and genuine instants as `Date`.
Probe a time-zone change and a non-Gregorian device calendar. Preserve the documented distinction between asserted days and GPS bucketing.
Inspect [CalendarDay](../../../../Where/WhereCore/Sources/Days/CalendarDay.swift) and its [tests](../../../../Where/WhereCore/Tests/CalendarDayTests.swift).
Check implicit `.current` arguments as well as `Calendar.current`: the [calendar lint gap](../../../../.bumper/RULES.md#gregorian-calendar) remains explicit.

For persisted shape changes, inspect both encode and decode paths, stable identity, and backup handling.
Use the module's current migration policy before suggesting compatibility defaults or a typed legacy fallback.
Where's backup transformation path and Periscope's historical raw records have different contracts.

## UI structure and Broadway

Read [building-ui](../../building-ui/SKILL.md) and the affected module's instructions.
For Where, start with its [layering](../../../../Where/AGENTS.md#layering) and [stylesheet owner](../../../../Where/WhereUI/AGENTS.md#design-system--wherestylesheet).

Locate behavior added to a view and its existing model or service owner. Follow derived bindings back to that model.
Check authored trait-dependent layout and motion at stylesheet slicing. Inspect direct trait reads and their documented runtime-input exceptions.
Use [WhereStylesheetTests](../../../../Where/WhereUI/Tests/WhereStylesheetTests.swift) for concrete trait expectations, then inspect the affected render.

For a large wrapped row or Form, inspect the concrete child-view boundary.
Extracting a computed `some View` property does not bound the enclosing generic value like a nominal child view does.
Use [FeatureGuidePageTests](../../../../Where/WhereUI/Tests/FeatureGuidePageTests.swift) and [LocationsViewTests](../../../../Where/WhereUI/Tests/LocationsViewTests.swift) as local size guards.
Their budgets are not universal limits. Follow building-ui for navigation, motion, accessibility, and theme-specific validation.

## Target graph and guards

Read the authoritative [Package.swift](../../../../Package.swift), [Project.swift](../../../../Project.swift), and [Bumper catalog](../../../../.bumper/RULES.md) for the affected targets.

For `extraPackageProducts`, apply the root [WhereUI double-link rule and exceptions](../../../../AGENTS.md#never-double-link-a-product-whereui-already-carries).
Inspect `WhereStylesheetTests.resolvesTraitAwareTokensFromTheBroadwayRoot` in [its source](../../../../Where/WhereUI/Tests/WhereStylesheetTests.swift).
An isolated bundle pass does not exercise the documented full-scheme duplicate-copy failure.
For a new import, locate the behavior's owning layer before considering an allow-list change.

Match the changed assertion to [WhereArchitectureTests](../../../../.bumper/Tests/WhereArchitectureTests.swift) or [WhereProjectRulesTests](../../../../.bumper/Tests/WhereProjectRulesTests.swift).
Check the actual configured rule, failing syntax, diagnostic, and valid case. Keep the rule catalog's enforcement limits visible.
For other linters, inspect configuration and CI at this revision. Do not infer coverage from a package being installed.

## Rendering and fixtures

Read the owning [SnapshotKitTesting contracts](../../../../Shared/SnapshotKitTesting/AGENTS.md) or [InstallerKitUI contracts](../../../../Shared/InstallerKitUI/AGENTS.md).

For a new capture path, compare it with [assertHTMLSnapshots](../../../../Shared/SnapshotKitTesting/Sources/AssertHTMLSnapshots.swift).
It supplies web content to the existing hosted view pipeline and uses its pre-measure readiness hook.
Check for duplicated host setup, traits, capture locks, rendering, or readiness logic.
Inspect [AssertHTMLSnapshotsTests](../../../../Shared/SnapshotKitTesting/Tests/AssertHTMLSnapshotsTests.swift) before accepting a parallel implementation.
Those tests cover capture constraints and cancellation. Source inspection establishes pipeline reuse.

For service-backed preview data, compare [InstallerPreview](../../../../Shared/InstallerKitUI/Sources/InstallerPreview.swift) and [InstallerBrowserPreview](../../../../Shared/InstallerKitUI/Sources/InstallerBrowserPreview.swift).
They use typed Testing SPI fixtures through the production service/model path.
Check whether JSON/dictionaries are bypassing that seam. Raw wire fixtures remain appropriate for serialization and validation tests.

## Classified logging

Read [PeriscopeCore](../../../../Shared/Periscope/PeriscopeCore/AGENTS.md#invariants) and the [macro authoring rules](../../../../.bumper/RULES.md#classified-periscope-events).

Trace changed fields from `@LogField` classification through emission input to export projection and the consuming sink.
Check original-error preservation, restricted `LogError` capture, nested export permissions, and independent grants.
Macro authoring lint does not prove that a field's content is safe to share or that a sink uses the filtered projection.
Inspect [LogExportPolicyTests](../../../../Shared/Periscope/PeriscopeCore/Tests/LogExportPolicyTests.swift), especially `allRequiredControlsMustBeEnabled` and `personalDataIsNotAWildcard`.
Use [LogExportableTests](../../../../Shared/Periscope/PeriscopeCore/Tests/LogExportableTests.swift) for nested policy and [LogErrorTests](../../../../Shared/Periscope/PeriscopeCore/Tests/LogErrorTests.swift) for structured errors.

## Tools and publication

Read [Tools ownership, mutations, and validation](../../../../Tools/AGENTS.md). Root wrappers also fall under these instructions.
For signing or installer publication, also read [Tools/InstallerKit](../../../../Tools/InstallerKit/AGENTS.md).

Trace the public wrapper into the importable policy module. Compare checkout discovery with `Repository.root` or `repository_root`.
Probe failure before replacement, between replacements, during rollback, and after commit.
Check which files remain owned and recoverable when another process creates a competing destination.
Compare the relevant owner and guards: [file transactions](../../../../Tools/Tests/file_transaction_test.rb) or [Flyover publication](../../../../Tools/Tests/test_flyover_publication.py).
Do not treat helper return values as proof of public exit status, output, or filesystem behavior.

For secret-bearing commands, inspect captured child output as well as constructed arguments.
The [signing state tests](../../../../Tools/Tests/signing_state_test.rb) cover diagnostic redaction and cleanup that can fail and be retried.
Trace trusted controller state separately from selected PR source when publication credentials are involved.
