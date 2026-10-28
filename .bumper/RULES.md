# Where Architecture Rules

`BumperBowling.swift` turns documented module boundaries and classified-event authoring rules into source-level checks. The Where architecture rules scan production sources. The Periscope authoring rules also scan affected test targets.

## Classified Periscope events

Repository scopes use `@LogScope`. Their direct nested event structs use `@LogEvent`, and `@LogField` appears only in those event structs.

The rules reject manual `LogEvent` and `LogScopeDefinition` conformances. They also reject the removed remote-field API names.

Macro expansion strings are ordinary test data, not source declarations. The typed syntax rules inspect declarations and identifiers, so they need no path exceptions for macro tests.

Repair a violation with the macro authoring API. Do not add a file exception. Mutation tests in `PeriscopeAuthoringRulesTests` cover each rule.

## Layer boundaries

| Component | Allowed Where dependencies | Framework capabilities |
| --- | --- | --- |
| `InstallerKit` | none (PeriscopeCore for logs) | Foundation, Observation |
| `InstallerKitUI` | none (InstallerKit for updates) | Foundation, SwiftUI, UIKit |
| `RegionKit` | none | Foundation |
| `WhereCore` | `RegionKit` | Foundation, persistence |
| `WhereUI` | `RegionKit`, `WhereCore` | Foundation, SwiftUI, UIKit |
| `WhereIntents` | `RegionKit`, `WhereCore`, `WhereUI` | Foundation, SwiftUI, UIKit |
| `Where` app | `RegionKit`, `WhereCore`, `WhereUI`, `WhereIntents` | Foundation, SwiftUI, UIKit |
| `WhereWidgets` | `RegionKit`, `WhereCore`, `WhereUI` | Foundation, SwiftUI, UIKit |
| `WhereShareExtension` | `WhereCore`, `WhereUI` | Foundation, SwiftUI, UIKit |
| `RegionViewer` | `RegionKit`, `WhereCore`, `WhereUI` | Foundation, SwiftUI, UIKit |

An import of a declared Where module outside these edges is a
`component_boundary` error. An import of a known framework capability outside
the component's allow-list is a `forbidden_import` error. RegionKit and
WhereIntents also forbid `CoreLocation` explicitly: geometry stays below GPS,
and intents use the injected idle-location service rather than starting GPS.

Repair a violation by moving the behavior to its owning layer and exposing the
smallest required value or intent across the existing dependency edge. Do not
expand the allow-list merely to make a new import pass.

Delete or reshape a boundary only when the corresponding module architecture
changes in its `AGENTS.md`, `Package.swift`, or `Project.swift`; update the
documentation and executable rule in the same change.

## Graph integrity

- `duplicate_ownership` rejects equal or nested source paths owned by two components.
- Configuration validation rejects duplicate module ownership before rule evaluation.
- `declared_dependency_cycle` keeps the Where layer graph acyclic.

`WhereArchitectureTests` mutates the real project configuration and retains its rule settings.
It adds equal/nested RegionKit paths to WhereCore, duplicates RegionKit's module, and adds a RegionKit → WhereCore dependency.
The unchanged graph must pass. Rule violations must have the expected ID and error severity.
Duplicate modules must produce the expected configuration error.

InstallerKit is a shared foundation component. WhereCore, WhereUI, and the app
may depend on it. InstallerKit cannot import Where modules or UI frameworks.
`InstallerKit rejects app and UI dependencies` guards this boundary.
InstallerKitUI renders the shared update screen above InstallerKit. It cannot import Where modules.
WhereUI may depend on InstallerKitUI. The `InstallerKitUI can use the engine but rejects host dependencies` mutation test guards this seam.

The mutation tests in `.bumper/Tests` prove that a valid downward import passes
and that representative upward/framework imports fail with the expected rule.

## Canonical production store opening

`where.production_store_opening` permits `SwiftDataStore.make` only in
`WhereLaunch` (the app process) and `ShareEvidenceModel` (the short-lived share
process). This protects the documented create-once/inject-down rule and prevents
a feature, intent, widget, or view model from independently opening the
production store. Tests and previews use `inMemory()` and are outside the
production scan.

Repair a violation by accepting the existing `WhereStore`/`WhereServices`
through injection. Add another owner only when a genuinely separate process is
introduced and its module documentation names that composition root. Delete the
rule if production store construction becomes compiler-enforced by the API.

## Checked concurrency boundaries

`where.checked_concurrency_boundaries` rejects `@preconcurrency` throughout
production code and confines `nonisolated(unsafe)` to the five existing,
documented task-lifecycle owners. Those owners use the escape hatch only so
nonisolated `deinit` can cancel an otherwise actor-confined observation task.

Repair a violation with checked isolation. If an escape hatch is unavoidable,
first document why its synchronization is sound on the owning declaration;
then update the narrow path set and mutation tests together. Delete the rule if
Swift gains a checked language mechanism for this deinit/task-lifetime pattern.

This rule follows the typed-query pattern proven by TheButtonHeist's
`buttonheist.checked_concurrency` rule. That existing lower-level rule was
audited and retained: Where needs the same check plus explicit exceptions for
its documented observation-task lifecycle.

## Composition ownership

`where.services_composition_ownership` keeps direct `WhereServices`
construction in WhereCore, with one production-source exception for
`PreviewSupport`. All app, intent, widget, share, and presentation code receives
the assembled services through injection.

`where.live_location_source_ownership` permits `CoreLocationSource`
construction only in `WhereLaunch`. This makes the "intents never start GPS"
contract executable and keeps the live location source at the app process
composition root.

Repair either violation by accepting the existing dependency through an
initializer or the established launch hook. Change the allowed scope only when
the corresponding composition design changes in `Where/AGENTS.md`. Delete the
rules if constructors become inaccessible outside their owner at compile time.

These use Bumper's standard `constructionOwnership` shaper. TheButtonHeist's
`buttonheist.semantic_observation_commit_ownership` boundary rule was audited
as the analogous lower-level ownership check and retained; the standard shaper
fully expresses Where's constructor facts.

## Gregorian calendar

`where.gregorian_calendar` rejects explicitly spelled `Calendar.current` in
Where's production sources. It does not catch an implicit `.current` whose
contextual type is `Calendar`. The enforcement gap and missing mutation test
are tracked in the root [`TODOs.md`](../TODOs.md).
Day and year math still requires an injected Gregorian calendar or,
inside WhereIntents, `Calendar.whereIntents`.

The architecture DSL and standard shapers cannot distinguish two static
members of the same Foundation type, so this uses a typed
`MemberAccessExprSyntax` query. TheButtonHeist's
`buttonheist.demo_accessibility_identifier` member-reference rule was audited
and retained as the closest lower-level pattern.

## Store transaction boundary

`where.store_transaction_boundary` requires calls to the mutating `WhereStore`
surface through `store` or `self.store` to be lexically contained by
`store.perform { ... }` or `store.performInCurrentGeneration { ... }`.
Attribution revisions use this same boundary; their coordinator also requires
the reviewed data generation and reassesses before writing.
Guard: `sample attribution revisions require a guarded transaction`.

The checked method inventory lives in `Sources/WhereProjectRules.swift`.
Recovery exclusions and imported compatibility requirements use this boundary.
Guard: `recoveryMetadataRequiresTransaction`.

## App Shortcuts provider ownership

`where.app_shortcuts_provider_ownership` allows `AppShortcutsProvider`
conformance only in the Where app component.

## Logging facade

`where.logging_facade` rejects direct `OSLog` imports and `print(...)` calls in
Where production sources. Production logging uses the typed `WhereLog` or
`RegionLog` Periscope facades.

This complements `where.logging_type_ownership`, which controls where the
typed event declarations live.

## Preview coverage

`where.preview_coverage` requires every WhereUI or WhereWidgets source file
that declares a `View`, `Widget`, or `WidgetBundle` struct to contain at least
one `#Preview`.

## Transitive Broadway ownership

WhereIntents and WhereWidgets explicitly forbid direct `BroadwayCore` and
`BroadwayUI` imports through the built-in `forbidden_import` rule.

## Logging vocabulary ownership

`where.logging_type_ownership` keeps every nominal type ending in `Log` under a
module's `Sources/Logging` directory. This preserves the existing convention
that collaborators and their typed Periscope event vocabulary do not accrete in
the same files.

Repair a violation by moving the logging type into the owning module's Logging
directory. Delete or reshape the rule if the repository deliberately adopts a
different logging vocabulary layout. Bumper's standard
`singleNominalSpelling` shaper expresses the invariant; no custom syntax rule
is needed.

- `where.recording_cloud_authority_ownership`: construct direct CloudKit containers only in the dedicated recording-authority transport. The existing SwiftData mirror remains separate. Guard: `WhereProjectRulesTests.direct CloudKit authority has one adapter`.

- `where.recording_coordination_composition`: construct the production authority coordinator once in `WhereLaunch`, then inject it into onboarding and services. Isolated test fixtures may construct their own. Mutation guard: `recording coordination is composed once at bootstrap`.

## Compatibility access

`where.compatibility_store_boundary` requires `validateTransaction(in: peer)`
immediately before the persistence save. The check validates the scope permit
and the compatibility requirement for transactions that contain domain writes.
Mutation guard: `transactionSaveRequiresCompatibilityCheck`.
The rule recognizes the current `peer.save()` syntax. Unit tests cover the
mutation-context marker and rollback behavior.

`where.compatibility_scope_ownership` permits production scoped-store construction
only in `DataCompatibilityCoordinator`. Isolated test fixtures may construct their
own. Guard: `compatibilityPermitsComeFromTheCoordinator`.

### `where.compatibility_coordination_composition`

Construct the production app's `DataCompatibilityCoordinator` only in `WhereLaunch.swift` over the existing bootstrap store. Isolated test fixtures may construct their own. Mutation coverage: `compatibilityCoordinatorIsComposedAtBootstrap`.

### `where.onboarding_gate_lifetime`

`OnboardingFlowModel` starts operations through `LifecycleGateHandle.perform`.
The rule rejects explicit `Task` construction and `Task.detached`, including generic
and explicit initializer spellings. Mutation guard: `onboardingWorkBelongsToTheGate`.
Aliases and contextually inferred `.init` calls are outside this syntax check.
Cancellation checkpoints and draining are behavior guards in `LifecycleGateHandleTests`,
`LifecycleRunnerResetTests`, and `WhereCompatibilityLifecycleTests`.

## Account trust lifetime

`where.recording_account_access_composition` confines `RecordingAccountAccess`
construction to `RecordingAuthorityCoordinator` in production. Inject the existing
coordinator instead of creating independent account trust. Fixtures are excluded.
The mutation test `account trust shares the authority coordinator lifetime` checks
the constructor spelling used in production. This syntax rule does not prove
invalidation timing or storage atomicity; Swift regressions and `AccountVerification`
cover those behaviors within their documented bounds.
