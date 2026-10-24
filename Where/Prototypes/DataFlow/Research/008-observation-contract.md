# Initial observation contract

Date: 2026-10-23.
Status: initial contract accepted in D007. Worked examples and implementation evidence remain pending.
Source revision: `f151996c8618afaf553164b0afb5fc690c023cb6`.
Evidence: synthesis of the accepted direction and prior research. The example below is illustrative and has not been instrumented.

Acceptance note, 2026-10-23: the user accepted this starting contract after its proposal as the next design decision.
[D007](003-decisions.md#d007--adopt-the-initial-observation-contract) records the decision and remaining precision choices.

## What the contract defines

Define what a value node represents and what each relationship promises.
This contract gives the automatic propagation experiment an expected result independent of its implementation technique.
It also determines which questions the eventual viewer can answer accurately.

[D006](003-decisions.md#d006--use-generated-provenance-handles-and-a-separate-graph) selects generated handles and a separate graph.
It left tracking granularity and the precise meaning of observed influence open. D007 selects the initial scope below.
Those choices affect the generator's obligations more directly than UUIDs versus counters or the storage engine.

## Accepted starting granularity

Track whole values and individual collection elements within the configured capture scope.
Apply automatic rules across supported code in that scope, without declarations for each stage or datum.

| Subject | Initial meaning |
| --- | --- |
| Whole value | One tracked scalar or application value version, such as a date or GPS sample. |
| Collection element | An element retains its provenance through supported selection, ordering, copying, and delivery. |
| Collection structure | Membership and position belong to the collection version. Reordering alone does not invent new input identities. |
| Field projection | A supported field read can identify its source value and field path. This does not establish complete per-field lineage. |

Complete nested-field or byte-level provenance remains a separate precision choice.
The first experiment must state the granularity it supports.
An aggregate-level dependency must not appear to prove which individual fields changed or contributed.

## Relationship meanings

| Observation | What the graph can claim | What it cannot infer from that observation alone |
| --- | --- | --- |
| Invocation input | This execution received this value in this argument role. | The function read the argument or used it to derive its return value. |
| Copy or forwarding | The same value provenance reached another use or return. | A new independent input entered the system. |
| Supported derivation | A new version derives from specified inputs under the recorded propagation rule. | Every field depends on every input, or every input was counterfactually necessary. |
| Branch decision | A condition evaluated to this result. Supported control links identify the execution it gated. | A condition's inputs contributed to the contents of every later value. |
| Delivery | A particular publication or callback transfer connects to an identified consumption. | Entity identity or timestamp proximity alone identifies that transfer. |
| Persistence boundary | The observed adapter distinguishes staging, save completion, and operation outcome. | A method's name or successful return proves an unobserved durable write or cloud upload. |

The [PROV data model](https://www.w3.org/TR/prov-dm/#term-Derivation) also distinguishes participation in an activity from established derivation.
This contract uses that distinction without selecting PROV as the wire format.

Copies can retain a value handle while generating new execution and delivery records.
Mutation creates a new version. A retry creates another execution of work with its applicable input versions.
New split outputs receive identities and supported input relationships. A broadcast can deliver the same version more than once.
These rules elaborate the selected direction without choosing an ID encoding.

## An example that exposes the distinction

This Swift fragment illustrates the contract. `persist` represents an unspecified persistence operation.

```swift
let shifted = inputDate.addingTimeInterval(offset)
if shifted > cutoff {
    persist(shifted)
}
```

For supported execution, the expected observations are:

- The supported date-adjustment rule links the new `shifted` version to `inputDate` and `offset`.
- The comparison records its input versions and Boolean result.
- On the taken branch, the persistence invocation receives `shifted` and has a distinct execution identity.
- The branch decision explains whether that invocation occurs.
- The comparison does not add `cutoff` as a value contributor to `shifted`.
- On the untaken branch, the trace records the decision without inventing a persistence execution.
- A persistence adapter must supply any stronger claim about staging or saving.

For the initial experiment, capture supported branch decisions and their local execution relationships.
Complete propagation of implicit influence through arbitrary control flow remains open.
The capture must state its control-flow coverage rather than claim complete causal coverage.

## Evidence and missing information

A relationship needs its meaning, observation method, and granularity.
Runtime participation, adapter-derived dependencies, optional declared semantics, and static candidate connections remain distinguishable.
An optional annotation can supply a declared relationship without making that relationship runtime-proven.

Opaque code can still have observed inputs and outputs.
Unless a supported rule establishes derivation, their internal relationship remains unknown.
The tool must not connect every input to every output as an exact claim.

An unknown relationship is different from an observed source input with no earlier parent in scope.
Unsupported code, uninstrumented boundaries, lost events, evicted history, and pre-capture ancestry need distinct explanations.
Missing edges do not establish independence.
Diagnostics and coverage metadata describe these limits without requiring application annotations.

## Next design checkpoint

Specify a small set of worked examples with expected records under the accepted contract.
Keep the logical records independent of their eventual Swift API, identifier encoding, or transport format.

| Example | Required distinction |
| --- | --- |
| Equal independent dates, then copying one date | Independent roots versus repeated uses of one version. |
| Date adjustment and conditional persistence | Value derivation versus branch influence and persistence outcome. |
| Batch filtering, reordering, and merging | Element identity, membership, rejected inputs, and contributing inputs. |
| Mutation and retry | New value version versus another execution. |
| Repeated asynchronous delivery | Same value versus separate transfer occurrences. |
| Opaque function or capture gap | Observed participation versus unsupported or unavailable derivation. |

These examples become the oracle for the [propagation experiment](007-value-identity-and-provenance.md#proposed-experiment-additions).
Expected records can be authored in tests. Application tracing still needs automatic generation.
The next implementation experiment evaluates whether source transformation can preserve this contract on the selected cases.
D007 resolves the initial scope of O003. It does not select a general solution for all Swift constructs.
