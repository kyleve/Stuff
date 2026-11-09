# Automatic instrumentation without required annotations

Date: 2026-10-23.
Status: user requirement recorded. Implementation techniques remain proposals.
Source revision: `d337a97d3a8df4481196eab085a5c635a303d4fd`.
Evidence: repository source inspection and official Swift documentation. No compiler experiment or live capture has run.

Update, 2026-10-23: [007 — Value identity and provenance](007-value-identity-and-provenance.md) extends the propagation model and experiment.
It separates value versions from entity identity and explains why function-boundary probes alone cannot establish complete information flow.

## User requirement and revised direction

Tracing must work without annotations on ordinary application types, functions, or handoffs.
Annotations can resolve ambiguous cases or add detail.
The user wants to avoid the cost of adding and maintaining tracing declarations throughout the application.

This changes the default approach proposed in [005](005-explicit-tracing-and-code-generation.md).
That document assumed explicit stage declarations and started its experiment with manually placed observations.
The revised proposal starts with automatic discovery and generated observations.
The runtime still needs explicit relationships. The tool generates those relationships wherever it can establish them.

Selecting a capture target or scope does not require annotating every stage.
A configuration file that lists every function and edge would preserve the same maintenance problem.
The experiment must measure automatic coverage and required exceptions.
This research does not establish that automatic coverage will include most of Where.

## Separate three technical questions

| Question | Proposed automatic mechanism | Remaining limit |
| --- | --- | --- |
| What can connect? | Parse declarations and expressions. Resolve symbols with compiler information where available. | A candidate connection is not runtime evidence. |
| What ran with this data? | Generate probes for invocations, selected values, branches, and transfers. | Unsupported boundaries and missing events leave gaps. |
| Which inputs produced this output? | Track supported assignments, arguments, returns, and transport occurrences. | Arbitrary mutation, aggregation, and opaque libraries need deeper analysis or adapters. |

The first two questions can produce useful data flow without proving every field's complete provenance.
The third question determines how precisely the tool can explain transformations.
An invocation that receives two inputs and returns one output does not prove that both inputs contributed to that output.
Observed participation, entity correlation, and proven transfer need distinct relationship kinds.

## Proposed generation pipeline

1. Select the application targets and capture scope.
2. Build a source inventory with SwiftSyntax.
3. Supplement that inventory with compiler symbol information where available.
4. Generate instrumented source copies and a metadata manifest in a derived directory.
5. Compile those copies in a dedicated tracing build.
6. Join runtime observations to the manifest through generated identifiers.

[SwiftSyntax](https://github.com/swiftlang/swift-syntax) supports parsing, inspecting, generating, and transforming source trees.
This makes source transformation a candidate for inserting probes without editing checked-in application code.
[SourceKit-LSP](https://github.com/swiftlang/sourcekit-lsp) provides compiler-backed language information and an index.
Its useful cross-module information depends on the project's build information and available index.
An index alone is not a complete graph of value dependencies.
The pipeline must detect missing or stale semantic information instead of treating guesses as resolved calls.

Generated node identities can combine the build identity, symbol identity, and local observation site.
The manifest records original source locations for inspection.
Identifiers need consistency within a capture and its matching manifest.
Automatic cross-build matching is a separate concern, particularly after renames.
Optional semantic aliases can support longer-lived comparisons without making aliases mandatory for basic tracing.

The tracing build must compile each declaration once.
[SwiftPM build tool plugins](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0303-swiftpm-extensible-build-tools.md) can produce derived sources and have read-only access to target sources.
The documented generation mechanism does not itself replace the target's original Swift inputs.
Adding transformed copies beside the originals would duplicate declarations.
Selecting generated inputs through the repository's Tuist and local-package build setup needs a separate feasibility check.
Build integration is part of the experiment, not an assumed capability of a small plugin.

## The role of macros and compiler analysis

Ordinary attached macros operate on their application sites.
They do not automatically discover and instrument every unannotated function in a project.
[Function-body macros](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0415-function-body-macros.md) can generate tracing bodies, but their original input bodies do not receive type checking first.
A generator could insert macro applications into derived copies.
That would remove manual annotation work, but it would still require discovery, source transformation, and build integration.
Direct source transformation is the first candidate to evaluate.
Macros remain possible implementation helpers and optional detail mechanisms.

Swift's [SIL representation](https://github.com/swiftlang/swift/blob/main/docs/SIL/SIL.md) contains typed operations and explicit value relationships after type checking.
This makes compiler analysis a stronger candidate for deeper value provenance.
Static SIL still does not identify which particular runtime event followed a branch.
A compiler-based approach would also need runtime observations and treatment of unavailable library bodies.
No SIL instrumentation integration is selected or validated here.
A custom compiler would introduce a toolchain maintenance obligation, so that option needs evidence of a necessary benefit.

## Automatic observations and reusable adapters

The generator can target ordinary language constructs without requiring custom declarations at every site.
Candidate observations include function entry and exit, arguments, returns, construction, selected assignments, and branch outcomes.
Coverage starts with supported constructs and expands through measured examples.
Function timing alone does not satisfy data tracing.

Reusable adapters provide knowledge of common boundaries:

| Boundary | Adapter responsibility |
| --- | --- |
| Task creation and callbacks | Link scheduling to execution where the generated hooks preserve that relationship. |
| `AsyncStream` | Observe publication and consumption, preserve transfer identity, and account for buffering and termination. |
| Collections and retry queues | Distinguish insertion, removal, repeated attempts, and newly derived values. |
| Persistence | Distinguish staged mutation, save completion, operation failure, and later notification. |
| Existing entity identity | Recognize supported identity contracts and qualify identity by type and relevant domain scope. |

Each adapter serves a pattern or API across call sites.
Adapter selection needs resolved types or validated rules. Matching names such as `save` or `yield` is insufficient.
Some application semantics can require a Where-specific adapter.
That cost must remain visible and must not become a hidden declaration for every stage.

`Identifiable` can provide an entity correlation key, subject to its actual lifetime and scope.
It does not provide a distinct identity for each delivery or retry.
For values without domain identity, generated observation tokens can identify occurrences within the capture.
Those tokens describe observations. They do not invent persisted entity identities.
Equal values, equal hashes, and temporary struct addresses do not establish shared identity.

Automatic value inspection must avoid invoking arbitrary getters or changing object lifetimes merely to summarize data.
The first experiment can use the known stored identity on `LocationSample` and a bounded set of supported value shapes.
It must report unsupported identity extraction instead of silently serializing arbitrary values.

## Applying this to the existing GPS path

[LocationSample](../../../WhereCore/Sources/Location/LocationSample.swift) already conforms to `Identifiable` and preserves its UUID in `recorded(by:)`.
[CoreLocationSource](../../../WhereCore/Sources/Location/CoreLocationSource.swift) constructs samples and publishes them through `AsyncStream`.
[LocationIngestor](../../../WhereCore/Sources/Location/LocationIngestor.swift) consumes that stream in a task created earlier.
This provides a concrete case for automatic identity extraction and generated handoff observations.
No tracing annotation needs to define the existing sample identity.

A sample ID can connect observations of the same entity across those stages.
Exact publication-to-consumption edges need more information, particularly for repeated publication of the same sample.
Concurrent producers and dropped elements can invalidate a side table that assumes probe order equals stream order.
The adapter must prove its matching rule or retain an ambiguous relationship.
An automatically generated envelope is another candidate, but it must preserve the affected API contracts and buffering behavior.
Task-local propagation alone cannot attach a producer's context to an existing consumer task.
The [earlier research](005-explicit-tracing-and-code-generation.md#carrying-context-across-asynchronous-boundaries) records the concurrency evidence.

[SwiftDataStore](../../../WhereCore/Sources/Persistence/SwiftDataStore.swift) stages rows in `add(sample:)` and saves within `perform`.
The generator can discover the calls, while an adapter supplies their validated persistence meaning.
An observed save return can establish save completion at that API boundary.
It cannot expose uninstrumented framework internals or prove a later CloudKit upload.
The trace must preserve the existing case where generation validation fails after save.

## Optional annotations

Annotations can provide a meaningful stage label, a custom identity rule, a grouping, or an opaque operation's declared relationship.
An annotation can state that one aggregate represents several input samples.
Without that declaration or equivalent evidence, the tool can show the observed inputs and output with a limited relationship.
The ordinary flow remains visible.
The goal is useful automatic tracing with precise evidence and few maintained exceptions.

## Revised feasibility experiment

This proposal replaces the manual-observation-first experiment in [005](005-explicit-tracing-and-code-generation.md#recommended-technical-experiment).
It does not authorize prototype implementation during the current design discussion.

Use the existing GPS path without adding tracing annotations or manual observation calls to application source.
Generate its metadata and observations through source transformation and reusable adapters.
Use a text event consumer before either viewer.

The proposed acceptance evidence includes:

- Automatic observations cover receipt, publication, consumption, admission, row staging, and save completion.
- The report distinguishes exact transfers, entity correlation, inferred relationships, and unavailable evidence.
- Distinct samples with equal values remain distinct. Repeated delivery and retry preserve separate execution identities.
- Rejection, concurrent work, dropped capture events, rollback, and failure after save retain accurate outcomes.
- A new forwarding function appears after regeneration without another tracing declaration or stage configuration entry.
- Generated code preserves evaluation count and order, return values, errors, isolation, cancellation, ownership, and cleanup.
- Unsupported constructs produce diagnostics and an explicit coverage report. They do not silently claim full coverage.
- Normal and instrumented runs preserve the tested domain results. Build time and capture cost have measured baselines.

The experiment must inspect wrapper effects on `inout`, generics, noncopyable values, and actor isolation where the selected path uses them.
Generated probes must not introduce tasks or suspension solely to record events.
Recording can still perturb execution timing. Measurements must state that limitation.

Success means automatic coverage of this path with an understood maintenance cost.
It does not establish automatic provenance for arbitrary Swift programs.
If a required boundary remains unsupported, record that limit before expanding the prototype or adopting another generation technique.
