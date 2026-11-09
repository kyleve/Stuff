# Initial repository map

Date: 2026-10-23.
Status: source inspection only.
Inspected revision: `ebb314a35339e0e0b580bb98fa9b64238df7f695`.
Scope: selected Where write paths and Periscope observation interfaces.
No live app behavior, performance, transport, or complete instrumentation coverage was measured.

## Where data crosses useful boundaries

| Boundary | Source | Observation |
| --- | --- | --- |
| Service composition | [WhereServices](../../../WhereCore/Sources/WhereServices.swift), `init` and `dataChangeUpdates` | The service container wires collaborators and exposes the store change stream |
| Live GPS persistence | [LocationIngestor](../../../WhereCore/Sources/Location/LocationIngestor.swift), `processIngestedSample` | The ingestor drains retries, writes through `perform`, then awaits `onPersisted` |
| Manual day mutation | [DayJournal](../../../WhereCore/Sources/Journal/DayJournal.swift), `addManualDay` and `overrideDay` | A transaction precedes awaited reconciliation and widget publication |
| Change notification | [WhereStore](../../../WhereCore/Sources/Persistence/WhereStore.swift), `changes` | `AsyncStream<Void>` signals a change without carrying its source or affected entities |
| Commit notification | [SwiftDataStore](../../../WhereCore/Sources/Persistence/SwiftDataStore.swift), private `perform` | After saving and validating the generation, the transaction emits its local change signal before returning |
| Derived outputs | [WhereServices](../../../WhereCore/Sources/WhereServices.swift), `onPersisted` and `DerivedDataReconciler` | Live ingestion and remote/import paths use different reconciliation policies |

The selected manual-write path has this ordering:

1. `DayJournal` begins a store transaction.
2. `SwiftDataStore` saves, validates the generation, and emits the change signal.
3. The transaction returns to `DayJournal`.
4. `DayJournal` awaits issue reconciliation and widget publication.

Subscribers can react to the change signal before the later reconciliation finishes.
The signal proves neither completion of downstream work nor its causal connection to a specific refresh.
The viewer therefore needs separate commit and downstream-completion observations.

The live GPS path goes directly from `LocationIngestor` to the store.
It does not route its writes through `DayJournal`.
Failed persistence enters the retry queue and location outbox.
A generation change closes recording authority instead of treating the sample as an ordinary retry.

These paths do not form one uniform pipeline today.
The [Where backlog](../../../TODOs.md) already records reconciliation gaps and an exploratory write-pipeline proposal.
Visualizing the current flow does not require adopting that separate refactor.

## Existing observability

| Capability | Source | Relevance and limit |
| --- | --- | --- |
| Typed records | [LogRecord](../../../../Shared/Periscope/PeriscopeCore/Sources/Pipeline/LogRecord.swift) | Records carry event identity, time, scopes, tags, attachments, call site, ambient state, and optional external identity |
| Live stream | [Periscope](../../../../Shared/Periscope/PeriscopeCore/Sources/Pipeline/Periscope.swift), `liveRecords` | Bounded delivery retains the newest pending records and preserves emission order |
| Recent history | [Periscope](../../../../Shared/Periscope/PeriscopeCore/Sources/Pipeline/Periscope.swift), `recentRecords` | A separate bounded snapshot returns recent records. It is not an atomic history-plus-subscription operation |
| Sink extension | [LogSink](../../../../Shared/Periscope/PeriscopeCore/Sources/Pipeline/LogSink.swift) | Sinks receive ordered asynchronous batches, with scope definitions before their records |
| Event tracing | [LogTraceModel](../../../../Shared/Periscope/PeriscopeTools/Sources/Tracer/LogTraceModel.swift), `load` | The tracer gathers earlier scope-related records and span records. It does not establish input-to-output lineage |
| Span tree | [SpanTreeModel](../../../../Shared/Periscope/PeriscopeTools/Sources/Spans/SpanTreeModel.swift), `buildTree` | Parentage comes from time containment, including still-open intervals |
| Stored exploration | [PeriscopeTools API](../../../../Shared/Periscope/PeriscopeTools/README.md#public-api) | Existing views cover logs, scopes, spans, timing history, and event detail |

`LogRecord` has no store sequence or explicit operation-parent field.
The durable store sequence is a separate ordering mechanism.
Neither emission order nor storage order proves causality.
Existing external identities can support object lookup, but they do not describe all inputs to a derived result.

When a consumer falls behind, `liveRecords` discards older pending records through its `bufferingNewest` policy.
The inspected observer-yield loop does not expose a per-subscriber loss marker.
A viewer cannot assume complete history merely because it receives the newest event.
The capture design needs an explicit gap policy and a history/subscription handoff.

## Implications to evaluate

These are research conclusions, not selected implementation decisions.

- Periscope is a plausible capture foundation. Its existing records need a flow-specific meaning before they can drive a causal graph.
- Static component relationships and observed causal edges need different presentation.
- Operation identity, data identity, and attempt identity answer different questions.
- A refresh can consume several writes. One parent identifier might not describe that relationship.
- A store commit, reconciliation completion, and UI publication are separate milestones.
- Capture must identify its session and app world across reset, demo transitions, and reconnection.
- A slow viewer must not hold a domain transaction open.

## Existing tools and constraints

[Inspector](../../../../Shared/Inspector/README.md) uses a separate boot runtime for persisted-state inspection.
The [Where runtime contract](../../../AGENTS.md#modules) prevents that runtime from constructing normal app services.
It is not an established attachment point for observing the normal app while it runs.

PeriscopeCore cannot import app code.
PeriscopeTools receives app-specific configuration from its host.
The [package manifest](../../../../Package.swift) owns the current dependency graph.
No new module or transport choice follows from this source survey.

Classified fields and export policy already exist in Periscope.
A future Mac transport needs an explicit policy for the records and payloads that leave the app.
The current viewer's unfiltered file export is not evidence that a new live transport has an appropriate policy.
See [file export modes](../../../../Shared/Periscope/PeriscopeTools/README.md#file-export-modes).

## Related existing backlog

The [Periscope backlog](../../../../Shared/Periscope/TODOs.md) already records these concerns:

- Events before store attachment lack durable history.
- Time containment can nest independent open spans.
- Some live models rebuild accumulated history after each change.
- Object inspection currently operates at scope granularity.

Those entries remain their owners. This prototype does not duplicate or silently absorb them.
Their source locations and status need fresh inspection before any dependent implementation.
