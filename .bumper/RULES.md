# Application Architecture Rules

`BumperBowling.swift` turns the module boundaries documented in the Where and
Throw `AGENTS.md` files into source-level checks. It scans production sources
only. Tests and generated files are outside the architecture graph.

## Layer boundaries

| Component | Allowed Where dependencies | Framework capabilities |
| --- | --- | --- |
| `RegionKit` | none | Foundation |
| `WhereCore` | `RegionKit` | Foundation, persistence |
| `WhereUI` | `RegionKit`, `WhereCore` | Foundation, SwiftUI, UIKit |
| `WhereIntents` | `RegionKit`, `WhereCore`, `WhereUI` | Foundation, SwiftUI, UIKit |
| `Where` app | `RegionKit`, `WhereCore`, `WhereUI`, `WhereIntents` | Foundation, SwiftUI, UIKit |
| `WhereWidgets` | `RegionKit`, `WhereCore`, `WhereUI` | Foundation, SwiftUI, UIKit |
| `WhereShareExtension` | `WhereCore`, `WhereUI` | Foundation, SwiftUI, UIKit |
| `RegionViewer` | `RegionKit`, `WhereCore`, `WhereUI` | Foundation, SwiftUI, UIKit |

| Throw component | Allowed Throw dependencies | Framework capabilities |
| --- | --- | --- |
| `ThrowCore` | none | Foundation |
| `ThrowUI` | `ThrowCore` | Foundation, SwiftUI, UIKit |
| `Throw` app | `ThrowUI` | Foundation, SwiftUI, UIKit |

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

ThrowCore and ThrowUI also forbid LifecycleKit. Throw is a retryable runtime,
not a terminal launch sequence. The Throw app cannot import ThrowCore directly.

## Graph integrity

- `duplicate_ownership` keeps every source path and module in one component.
- `declared_dependency_cycle` keeps each application layer graph acyclic.

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

Throw has four matching ownership guards:

- `throw.session_composition_ownership` permits `ThrowSession` construction only in `ThrowSession+Composition.swift`.
- `throw.live_dependency_composition_ownership` keeps live stores, durable logging, sources, and polling dependencies in that same file.
- `throw.runtime_composition_ownership` permits `ThrowRuntime` construction only in `ThrowRuntime.swift`.
- `throw.layer_frame_erasure_ownership` permits raw `LayerFrame` construction only at the typed Core erasure boundary.

Repair a violation by injecting the existing object or by using a typed layer
frame. Change an owner only when the matching Throw module contract changes.

## Gregorian calendar

`where.gregorian_calendar` rejects `Calendar.current` throughout Where's
production sources. Day and year math uses an injected Gregorian calendar or,
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

The checked methods are `add`, `write`, `setManualDay`, `clearManualDay`,
`clear`, `clearAll`, `setIssueDismissed`, `restoreDismissedIssue`,
`setTrackedRegion`, and `setPrimaryRegions`.

## App Shortcuts provider ownership

`where.app_shortcuts_provider_ownership` allows `AppShortcutsProvider`
conformance only in the Where app component.

## Logging facade

`where.logging_facade` rejects direct `OSLog` imports and `print(...)` calls in
Where production sources. Production logging uses the typed `WhereLog` or
`RegionLog` Periscope facades.

`throw.logging_facade` rejects direct system-log imports and raw diagnostic
output calls in Throw production sources. Production logging uses typed
`ThrowLog` events.

This complements `repository.logging_type_ownership`, which controls where the
typed event declarations live.

## Preview coverage

`where.preview_coverage` requires every WhereUI or WhereWidgets source file
that declares a `View`, `Widget`, or `WidgetBundle` struct to contain at least
one `#Preview`.

## Transitive Broadway ownership

WhereIntents and WhereWidgets explicitly forbid direct `BroadwayCore` and
`BroadwayUI` imports through the built-in `forbidden_import` rule.

## Logging vocabulary ownership

`repository.logging_type_ownership` keeps every nominal type ending in `Log`
under a Where or Throw module's `Sources/Logging` directory. This keeps typed
Periscope event vocabulary separate from collaborators.

Repair a violation by moving the logging type into the owning module's Logging
directory. Delete or reshape the rule if the repository deliberately adopts a
different logging vocabulary layout. Bumper's standard
`singleNominalSpelling` shaper expresses the invariant; no custom syntax rule
is needed.

## Throw concrete view boundaries

`throw.no_any_view` rejects `AnyView` in Throw production sources. Controller
and projection scenes compose concrete ThrowUI roots. Runtime handoff exposes
the shared session instead of erasing the view type.

## Throw provider boundary

`throw.provider_implementation_boundary` rejects concrete aircraft provider
sources and decoders in ThrowUI. Source setup and provider capabilities go
through `AircraftSourceOperationServing`, whose production implementation is
owned by ThrowCore.

## Throw checked concurrency boundaries

`throw.checked_concurrency_boundaries` rejects `@preconcurrency` and
`nonisolated(unsafe)` in all Throw production sources. Repair a violation with
checked isolation. Do not add an exception without first documenting and
testing the synchronization boundary.

## Throw controller-scene lifecycle

`throw.controller_scene_lifecycle` rejects app-delegate background and
foreground callbacks in the Throw app. Controller roots deliver their exact
scene identities and lifecycle transitions to the process runtime instead.
