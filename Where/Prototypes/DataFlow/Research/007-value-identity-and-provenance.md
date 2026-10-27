# Value identity, propagation, and provenance

Date: 2026-10-23.
Status: technical discussion and prior-art research. Identity representation and propagation mechanisms remain open.
Source revision: `c3f8e7ce7f43a92e92df0632516b566b59abaa9d`.
Evidence: existing source research and primary external sources. No instrumentation experiment or live capture has run.

Acceptance update, 2026-10-23: the user selected generated provenance handles and a separate value-version and execution graph as the starting direction.
[D006](003-decisions.md#d006--use-generated-provenance-handles-and-a-separate-graph) records the decision.
UUIDs versus counters and concrete propagation, storage, and transport implementations remain open.
The discussion below preserves the proposal and supporting research. Acceptance does not establish experimental validation.

## Discussion focus

The user asks how to trace values without suitable domain identities and follow information through copies, splits, and merges.
They propose a type-qualified counter, such as `OrderedID<Date, Int>`, or UUIDs with a separate provenance store.
These are candidate designs, not selected APIs.
The requirement for [automatic instrumentation](006-automatic-instrumentation.md) still applies.

The proposed direction combines generated value handles with a separate graph of operations and value versions.
Choosing an identifier format does not solve propagation.
Generated code must carry the handle through every supported operation and transfer.

## Prior art

| Source | Relevant mechanism | Limit for this prototype |
| --- | --- | --- |
| [LLVM DataFlowSanitizer design](https://clang.llvm.org/docs/DataFlowSanitizerDesign.html) | Instrumentation propagates labels through runtime operations and shadow memory. Operations can combine input labels. | Its current labels use eight bits and combine with bitwise OR. This is not an unlimited graph of unique inputs. |
| [Galette](https://github.com/neu-se/galette) | Java bytecode instrumentation propagates tags alongside program values. | This establishes prior art for automatic propagation, not Swift compatibility or automatic source selection. |
| [W3C PROV-DM](https://www.w3.org/TR/prov-dm/) | Entities, activities, usage, generation, and derivation describe provenance. | It defines a representation. It does not discover runtime derivation automatically. |
| [Provenance Semirings](https://www.cs.ucdavis.edu/~green/papers/pods07.pdf), Green, Karvounarakis, and Tannen, 2007 | Symbolic expressions record how database input tuples contribute to query results. | Its query algebra does not directly define arbitrary Swift execution semantics. |
| [OpenTelemetry span links](https://opentelemetry.io/docs/specs/otel/overview/#links-between-spans) | Links express relationships across operations, including batch and fork/join work with multiple causes. | Operation relationships alone do not track individual value copies or fields. |

DataFlowSanitizer also needs rules or wrappers for uninstrumented functions.
Its [current documentation](https://clang.llvm.org/docs/DataFlowSanitizer.html) describes development for x86_64 Linux.
It is a design reference here, not a verified tool for Where's Swift and Apple-platform build.

[Phosphor](https://github.com/gmu-swe/phosphor) is earlier JVM prior art.
Its maintainers retired it in June 2025 and identify Galette as its successor.
These systems demonstrate propagation mechanisms. They do not establish coverage or cost for this repository.

The database research also shows why a set of original input IDs can lose useful information.
Two outputs can involve the same inputs through different combinations or repeated uses.
Our proposed graph preserves intermediate operations and input roles rather than storing only a union of ancestor IDs.
This is a design inference from the prior art, not a claim of implementing its formal query semantics.

## What receives an identity

The proposed model distinguishes four concepts:

| Concept | Example | Identity lifetime |
| --- | --- | --- |
| Domain entity | The existing GPS sample UUID | The domain's established lifetime and scope |
| Trace value version | One observed input date or one derived date | An immutable observation within the capture |
| Operation execution | One transformation or persistence attempt | One execution, including separate retries |
| Delivery | One publication or callback delivery | A separate transfer of a new or existing value |

A trace value can refer to a domain entity, but it does not replace that entity's identity.
An observed date needs no domain ID before the tracer creates a trace value for it.
That identifier names the new observation. It does not claim that the date has a persisted identity.

Two independently received dates can have equal contents and different trace identities.
Copying an already tracked date can preserve its trace value handle and record another use.
A transformation produces a new trace value version.
This applies even to results whose contents equal an earlier value.
A domain object can therefore retain its entity identity across several trace value versions.
An in-place mutation needs another version so that later reads do not rewrite the recorded past.

For Where, `recorded(by:)` adds device information and preserves the [LocationSample](../../../WhereCore/Sources/Location/LocationSample.swift) UUID.
The proposed trace records the original and stamped versions under separate value handles, linked to the same sample identity.
The [ingestor](../../../WhereCore/Sources/Location/LocationIngestor.swift) can retry persistence of that value through a different operation and delivery.

## Counter identities and UUIDs

The proposed `Type + InstanceCount` scheme can identify observations within a defined allocation scope.
For value types, the count means observed creations or versions, not discoverable object instances.
The allocator must avoid reuse and allocate safely across concurrent work.

A candidate exported identity is a named record containing a capture ID, producer ID, and sequence number.
The capture and producer identify the allocator namespace.
The sequence distinguishes allocations within that namespace.
Restarted producers need new namespaces. Counter exhaustion must not wrap into existing identities.
Allocation order alone does not establish causal order between operations.

A fresh UUID per trace value is another viable representation.
Its purpose is uniqueness, not encoding ancestry or ordering.
There is no performance evidence yet for choosing between these representations.
Compact local handles can refer to qualified identifiers in the manifest or export format.

The value's type can remain node metadata.
A transformation from `Date` to `String` creates a new node and a derivation edge without changing the original date node.
A typed handle can improve generated Swift APIs, while a common node identifier supports heterogeneous graph edges.
Type names and source locations do not need to become globally stable identity components.

## Splits, merges, and repeated uses

This example is conceptual. It does not describe instrumentation already present in Where.

```text
A = observed Date input
B = observed TimeInterval input
M = execution of date adjustment, using A as date and B as offset
C = Date result generated by M, with derivation from A and B
P = persistence execution using C
R = reminder execution using C
```

The merge produces C with a new identity and links to both contributing values.
The later fan-out records two uses of C.
It does not create two unrelated roots or copy all of C's ancestors into both consumers.
If a split creates genuinely new values, each output gets a new identity and its supported input relationships.
If a collection exposes existing tracked elements, those elements can retain their value identities.

Representing executions separately preserves operand roles and repeated use, such as one value supplied as both arguments.
A flat set of parent IDs would lose that distinction.
A loop can produce successive versions linked to earlier versions, leaving the recorded derivation graph acyclic.
Source topology can still contain cycles.

A participation edge means that an operation received or used a value.
A derivation edge requires evidence that the value contributed to a particular output.
PROV-DM explicitly distinguishes usage plus generation from established derivation.
An opaque function cannot acquire exact derivation edges merely because its arguments and return value were observed.

## Carrying the handle in Swift

A separate graph store records relationships, but active code still needs a way to identify the current value version.
Looking up a date by equality, hash, or a temporary address cannot recover that information reliably.
Those strategies can merge unrelated inputs or lose provenance as a value moves.

The candidate mechanism is generated shadow metadata: parallel handles that follow the ordinary values.
The following notation describes propagation rules, not callable Swift APIs:

```text
source read:       handle(a) = new root observation
copy b = a:       handle(b) = handle(a)
derive c = f(a):  handle(c) = new result linked through this execution of f
store c:          record a use of handle(c) by this persistence attempt
```

Ordinary application declarations remain unannotated.
The generator must propagate metadata through supported assignments, parameters, return values, and closure captures.
It also needs metadata for stored properties, mutable aliases, and collection elements where those values are tracked.
Moving this state into a global dictionary does not remove those propagation obligations.

A simple case can use parallel local variables in generated source.
Calls need a channel for parameter and result handles.
Captured closures and asynchronous transfers need corresponding handle capture or transport.
Generated wrappers or shadow storage are candidates, subject to isolation, ownership, lifetime, and ABI constraints.
No general mechanism for these cases is validated yet.

The generator must distinguish fresh external inputs from copies and outputs of known transformations.
Sources can include system callbacks, clock reads, user actions, and store reads with unavailable earlier provenance.
Source recognition rules belong in reusable adapters.
Missing ancestry must remain unavailable rather than being presented as a proven fresh domain entity.

## Granularity and control dependence

Tracking every bit is different from tracking a sample, a field, or a collection element.
The first proposal tracks selected domain values and supported scalar inputs, with explicit granularity metadata.
Per-element tracking can show which inputs a filter removes or a batch combines.
Tracking only an entire array cannot establish each element's independent lineage.
Required precision remains an open decision.

Control dependence is another separate choice.
For `date > cutoff ? "late" : "early"`, the dates affect which constant is selected.
Copy propagation alone does not explain that influence.
The proposed graph can distinguish value dependencies from branch or selection dependencies.
It must not claim that all observed dependencies are complete, minimal, or counterfactually necessary.

This also narrows the promise of source instrumentation.
Entry and exit probes can establish participation but cannot provide complete propagation through arbitrary function bodies.
The feasibility experiment now needs a supported shadow-propagation path.
If source transformation cannot preserve the selected semantics, compiler-assisted instrumentation remains an option to investigate.

## A separate store and bounded capture

An append-only provenance store can retain value nodes, execution nodes, deliveries, and typed relationships.
Running code carries small handles. It does not carry a growing list of every ancestor.
Ancestry queries traverse stored edges or use derived indexes.
A merge with many inputs still creates proportional relationship data.

UUIDs do not make storage or propagation cost unlimited.
The capture needs bounded buffering and explicit retention rules.
Missing or evicted ancestors need an unavailable-history marker, distinct from an input with no parent.
Trace IDs must not be reused after eviction.
Delayed and reordered event delivery must not create false ancestry.

The Mac process could retain the graph while Where retains active metadata and a bounded event buffer.
An in-app viewer needs access to the same observation semantics.
The exact store location and transport remain open.
Recording must not become a prerequisite for saving domain data or retain arbitrary application objects indefinitely.

Continuity across process restart requires persisted provenance or a durable mapping with suitable version and generation information.
An existing entity UUID alone cannot identify which earlier version produced a recovered value.
Without that continuity, a new capture can identify the entity while marking its earlier lineage unavailable.

## Proposed experiment additions

These cases extend the [automatic instrumentation experiment](006-automatic-instrumentation.md#revised-feasibility-experiment).
They are design criteria, not implementation completed during this discussion.
Small unannotated Swift fixtures can establish propagation rules before applying them to the real GPS path.
Those fixtures do not replace the required live demonstration.

- Two independent inputs contain equal dates but receive distinct root identities.
- A copied date retains its provenance through a parameter, return value, and captured closure.
- A date and interval produce a new date with two operand roles and a separate execution identity.
- One value feeds two consumers. A true split produces separately identified outputs.
- A batch preserves element membership through filtering and merging.
- Mutation creates another value version. Retry creates another execution without inventing a new source input.
- Repeated stream delivery does not conflate delivery identities, including concurrent publication and dropped elements.
- A branch-selected constant distinguishes control dependence from ordinary value propagation.
- Capture eviction, transport gaps, and restart expose missing ancestry.
- Adding a forwarding function or renaming a local variable needs no new tracing declaration.

The evidence must identify the granularity and relationship kinds actually supported.
It must compare domain results and record the cost of active metadata, emitted events, retained graph data, and compilation.
The user has not selected UUIDs, counters, a storage engine, or a propagation implementation.
