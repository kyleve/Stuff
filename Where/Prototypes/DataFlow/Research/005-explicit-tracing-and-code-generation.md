# Explicit tracing and code generation

Date: 2026-10-23.
Status: technical exploration. The architecture and APIs remain proposals.
Source revision: `6369a3b157798d8a1834d3979d567f4c6876c0b4`.
Evidence: source inspection and official Swift documentation. No compiler experiment or live capture has run.

Update, 2026-10-23: [006 — Automatic instrumentation](006-automatic-instrumentation.md) supersedes this document's default annotation approach and proposed experiment.
The user requires automatic tracing, with optional annotations for ambiguity or detail.
The revised proposal also uses generated identifiers within each build, replacing the proposed requirement for manually stable identifiers across renames.
The GPS source findings and distinctions between entity identity, execution, and handoff remain relevant.

## Discussion focus

The user wants to follow an individual datum through the system, with a GPS point as the concrete example.
The Plinko analogy suggests visible stages and a distinct item moving through them.
The current discussion concerns technical feasibility before UI and UX.
The user proposed Swift macros or a SwiftSyntax parser as ways to generate a representation of the system.

## Proposed model: system description plus execution evidence

A generated system description can identify components, stages, ports, source locations, and declared connections.
Runtime evidence identifies which data reached those stages, what happened, and which outputs followed.
Both descriptions reference the same stable stage identifiers.

The system description answers which paths exist or are declared.
The execution evidence answers which paths this particular item took.
An observed path can also reveal connections absent from the static description.
Declared, inferred, and observed connections must retain their different meanings.

## What generation can establish

| Technique | Useful output | Limit |
| --- | --- | --- |
| SwiftSyntax scanner | Declaration inventory, annotations, source locations, and candidate calls | Syntax alone does not resolve every overload, protocol target, or runtime value |
| Attached macros | Stage descriptors, typed adapters, diagnostics, and generated observation calls | Expansion sees supplied syntax and context, not a whole-program semantic graph |
| Compiler index / SourceKit | Resolved symbols and source relationships where index information exists | A symbol reference does not establish which datum traversed it at runtime |
| Runtime instrumentation | Actual stage visits, handoffs, branches, outcomes, and durations | Coverage depends on the observed boundaries and retained events |

[SwiftSyntax](https://github.com/swiftlang/swift-syntax) supplies a source-accurate syntax tree and underlies Swift macros.
Swift distinguishes syntactic transformation from semantic analysis in its [macro design document](https://github.com/swiftlang/swift-evolution/blob/main/visions/macros.md).
[SourceKit-LSP](https://github.com/swiftlang/sourcekit-lsp) offers a compiler-backed index whose cross-module usefulness depends on available build information.
These capabilities support generating a partial system map.
They do not establish complete data provenance through arbitrary Swift code.

A scanner can recognize `store.add(sample: sample)`.
It cannot conclude from that expression alone that the sample reached durable storage.
It also cannot determine which runtime store implementation received the call from syntax alone.

## Where a GPS point goes today

This table describes the inspected source, not proposed instrumentation already present.

| Stage | Current source | Meaning for tracing |
| --- | --- | --- |
| Receive a location | [CoreLocationSource](../../../WhereCore/Sources/Location/CoreLocationSource.swift), delegate callbacks | Invalid accuracy can reject input before a domain sample exists |
| Create a sample | [LocationSample](../../../WhereCore/Sources/Location/LocationSample.swift), initializer | A UUID identifies the new observation |
| Publish and consume | [CoreLocationSource](../../../WhereCore/Sources/Location/CoreLocationSource.swift), `sampleContinuation.yield`; [LocationIngestor](../../../WhereCore/Sources/Location/LocationIngestor.swift), `installIngestTaskIfNeeded` | The value crosses an `AsyncStream` into a long-lived consumer task |
| Admit and stamp | [LocationIngestor](../../../WhereCore/Sources/Location/LocationIngestor.swift), `accepts` and `processIngestedSample` | Recording authority gates admission. `recorded(by:)` preserves the sample UUID |
| Stage the row | [SwiftDataStore](../../../WhereCore/Sources/Persistence/SwiftDataStore.swift), `add(sample:)` | The method inserts or updates a transaction-local record |
| Save the transaction | [SwiftDataStore](../../../WhereCore/Sources/Persistence/SwiftDataStore.swift), private `perform` | `peer.save()` precedes generation validation and the change signal |
| Reconcile outputs | [WhereServices](../../../WhereCore/Sources/WhereServices.swift), `onPersisted` | The ingestor awaits the selected reminder and widget work |

The sample UUID already survives device stamping and row lookup.
It provides a useful correlation key across value copies.
Object addresses cannot identify these Swift struct copies reliably.
The tracing API can wrap the existing identity in a domain-specific type without replacing the persisted identity.

Returning from `add(sample:)` means the row was staged, not committed.
A failed transaction before save has no successful commit.
A generation change after save can reject an operation whose physical write already occurred.
Trace outcomes must preserve that distinction instead of labeling every thrown operation as a rollback.

The retry queue retains the sample identity, but a later persistence attempt is a different execution.
The outbox can survive process restart. Reconstructing the entire causal chain across restart needs an explicit durability decision.
Without that support, a recovered sample can link by data identity while its earlier execution remains unknown.

## Identity and relationships

The proposed representation separates these identities:

| Identity | Purpose |
| --- | --- |
| Stage | Stable semantic location, such as location ingestion or transaction save |
| Data | The sample or resulting entity, qualified by its kind and relevant app world |
| Execution | One visit or attempt at a stage, including distinct retries of the same sample |
| Handoff | One transfer through a stream, queue, callback, or other asynchronous boundary |
| Session and generation | The capture lifetime and domain world in which the observation occurred |

Stage names, source locations, and function names are useful metadata.
Persisted stage identity must survive a function rename or source-line shift.
Current Periscope macros already require explicit stable event and scope identifiers.
See [PeriscopeMacros](../../../../Shared/Periscope/PeriscopeMacros/README.md).

An execution can consume several inputs and produce several outputs.
The representation therefore needs explicit relationships, including multiple causes for aggregation or coalesced work.
A shared sample ID establishes object correlation. A handoff or consumed-input relationship establishes a more specific causal connection.
Timestamp proximity establishes neither relationship.

For a rejected raw callback, an observation can have its own event identity without inventing a persisted sample identity.
For a transformed result, the trace records an input-to-output relationship instead of pretending the output is the original value.

## Macros as instrumentation helpers

An annotation could name a stage and select a parameter whose identity the runtime understands.
The following declaration illustrates a possible API. It is not implemented or compiler-validated:

```swift
@FlowStage("where.location.ingest", tracks: "sample")
private func processIngestedSample(_ sample: LocationSample) async
```

The macro could generate a stage descriptor and code around the existing body.
A typed adapter would provide the sample identity and an approved summary.
The macro would validate the parameter name and supported declaration shape.
It would not serialize arbitrary parameters automatically.

Swift's [function-body macro proposal](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0415-function-body-macros.md) includes tracing as a use case.
It permits body replacement and lists `BodyMacros` as a feature flag.
The proposal allows one body macro per declaration and expands before the original body receives type checking.
The exact project toolchain needs a feasibility check before this becomes the selected mechanism.
The [package manifest](../../../../Package.swift) owns the pinned SwiftSyntax version.

A fallback is explicit runtime helpers with macros generating descriptors and typed adapters.
That keeps the observation contract independent of function-body macro support.
A separate build tool can assemble descriptors into a manifest for both viewing surfaces.
Individual macro expansions do not need to coordinate writes to a shared manifest file.

Generated tracing must preserve actor isolation, return values, thrown errors, cancellation behavior, and cleanup.
It must not introduce another task or suspension merely to record an event.
Unsupported declaration forms need diagnostics rather than an expansion that silently changes behavior.
A function return can report control-flow completion. Domain-specific outcomes still need explicit observation points.

## Carrying context across asynchronous boundaries

Task-local context can carry the current execution through nested async calls.
Structured children and ordinary `Task` creation inherit task-local values according to Swift's [context inheritance rules](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md#context-inheritance).
Detached tasks need explicit propagation. See [task-local values](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0311-task-locals.md).

Sending a value through `AsyncStream` does not transfer the producer's task-local bindings into an existing consumer task.
Where creates its ingest task once, so each delivered sample needs explicit correlation at that boundary.
A callback, persisted retry, or change broadcaster creates the same design question.

Two options deserve comparison:

- A trace envelope carries the value, observation identity, and parent handoff explicitly.
- A bounded side table links existing sample identities to observations without changing every value signature.

An envelope makes transfer explicit but changes stream and queue interfaces.
A side table reduces interface changes but must handle repeated delivery, eviction, scope changes, and concurrent attempts.
Neither approach makes data identity interchangeable with execution identity.

Periscope already provides [AmbientLogContext and `Log.withContext`](../../../../Shared/Periscope/PeriscopeCore/Sources/Context/AmbientLogContext.swift).
This is a candidate foundation for nested execution context.
Its current payload contains scopes, tags, and a recorder, without dedicated data-flow execution or handoff fields.
`Log.current` reads that context. Existing static loggers do not automatically read it at emission.
Adding an outer context alone would therefore leave some current events uncorrelated.

## Recommended technical experiment

This is a proposed next step, not an implemented prototype or approved API.

Define a small observation contract and follow GPS ingestion through six explicit boundaries.
Use source receipt, stream publication, stream consumption, admission, row staging, and transaction completion.
Start with explicit observations so their meaning is inspectable.
Then replace repetitive stage instrumentation with one macro and compare the resulting event relationships.
Use a command-line consumer or tests before designing either viewer.

The evidence must cover these cases:

- Two samples have identical values but distinct identities.
- One sample fails, enters the outbox, and succeeds on a later attempt.
- Admission rejects a sample without a persistence event.
- Two operations overlap without acquiring a false parent relationship.
- A staged write rolls back, and a separate case rejects authority after physical save.
- A missing capture event produces an incomplete trace instead of an invented connection.

This experiment determines the annotation burden, required handoff adapters, and function-body macro viability.
It also tests whether Periscope can carry the contract with bounded cost.
Broader static inference and complete value provenance remain separate research directions.
