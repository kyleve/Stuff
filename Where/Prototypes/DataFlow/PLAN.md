# Where live data flow prototype

Status: provenance direction and initial observation contract selected. Feasibility work and implementation have not started.
Updated: 2026-10-23.

## Goal

Build a prototype that shows real data flowing through the running Where app.
Develop the design through discussion and small, reviewable PRs.
Keep this file as the current plan and [Research/](Research/README.md) as the supporting record.

The user requested this document workflow on 2026-10-23.
The user selected both a separate Mac window and a view inside Where.
The user requires automatic tracing. Annotations can resolve ambiguity or add detail, but ordinary tracing cannot require them.
The user selected generated provenance handles and a separate graph of immutable value versions and executions.
The initial observation contract tracks whole values and collection elements, with distinct derivation, participation, and branch relationships.
The generation mechanism, identity encoding, transport, presentation reuse, and first-flow selection remain open.

## Current position

The repository already provides typed events, spans, live log streams, and an on-device trace viewer.
Its store change stream carries no causal identity.
Its span tree uses time containment, which does not establish data lineage.
The [repository research](Research/002-repository-map.md) records the evidence and its limits.

The current discussion concerns explicit data tracing before UI and UX.
The motivating example follows one GPS point from its system callback through ingestion and persistence.
We are evaluating automatic system discovery, generated runtime observations, and adapters for asynchronous handoffs.
The [GPS tracing research](Research/005-explicit-tracing-and-code-generation.md) records the current source path and identity constraints.
The [automatic instrumentation discussion](Research/006-automatic-instrumentation.md) replaces its annotation-led proposal and experiment.
The [value provenance research](Research/007-value-identity-and-provenance.md) explores generated identities, shadow metadata, splits, merges, and prior art.
The [initial observation contract](Research/008-observation-contract.md) defines the accepted tracking granularity, relationship meanings, and evidence limits.
The [decision register](Research/003-decisions.md#d007--adopt-the-initial-observation-contract) records the accepted direction and unresolved questions.

## Proposed first result

A developer performs an ordinary action in Where and sees the resulting work update live.
Both a separate Mac window and an in-app view must support this goal.
Selecting one operation reveals its observed stages, outcomes, and links to the affected data.
The viewer distinguishes recorded relationships from incomplete or inferred relationships.

GPS ingestion is the current technical design scenario, including its stream boundary, recording gate, transaction, and retries.
A manual day edit remains a repeatable alternative for the first demonstration.
The first implementation slice remains open. Both candidates use the normal app services.

Proposed acceptance criteria:

- One real action produces an inspectable flow while Where remains usable.
- Ordinary stages appear without tracing annotations or manual observation calls. Optional declarations refine ambiguous relationships or add detail.
- Both surfaces describe the same observed work consistently. Their layouts can differ.
- The viewer identifies the observed input, commit, downstream work, and terminal outcomes.
- Concurrent operations remain distinguishable. Time overlap alone creates no causal edge.
- Inputs without domain IDs remain distinguishable. Copies, transformations, splits, and merges retain their supported provenance relationships.
- Failed, skipped, cancelled, and incomplete work remain visible as distinct outcomes.
- Pausing the display does not pause domain work. Capture behavior during pause is explicit.
- The viewer shows capture gaps, connection loss, and unavailable history honestly.
- Capture and presentation have measured, bounded resource costs.

Exact latency, event-volume, and memory budgets remain undecided.
Fixtures support development and tests. A fixture-only demonstration does not complete the live-flow result.

## Proposed sequence of PRs

These are candidate boundaries. Each implementation slice needs a concrete scope before work starts.
Create the actual stack after the first implementation decisions establish its dependencies.

| Slice | Result | Evidence required to finish |
| --- | --- | --- |
| D0 — Planning documents | This plan, research index, initial source map, and decision register | Links resolve, findings cite source, and proposals remain explicit |
| P1 — Observation contract and feasibility | Specify expected records under the accepted contract and prove automatic propagation before UI work | Unannotated value fixtures establish propagation rules, then GPS sources produce useful runtime evidence. Build integration, coverage, semantics, and cost have measured evidence |
| P2 — First live flow | Minimum instrumentation, capture adapter, and viewer for the chosen flow | An ordinary action in the running app appears live through its selected boundaries |
| P3 — Both surfaces and inspection | The companion surface, selection, filtering, display pause, and bounded recent history | Both viewers explain the same live operation and its recent outcome |
| P4 — Failure and concurrency | Retry, overlap, cancellation, reset, and capture-gap behavior | Controlled scenarios preserve domain results and expose incomplete observation |
| P5 — Broader coverage | Additional flows selected from prototype findings | Each added flow answers an agreed debugging question |

P2 can split into dependent capture, transport, and presentation PRs after the first flow is chosen.
Its completion criterion remains an end-to-end live demonstration.
The order of the two surfaces remains open. The full prototype requires both.
Durable replay, remote-device support, and wider reuse need separate decisions before entering the stack.

## Design boundaries to preserve

These existing contracts constrain the prototype. They do not select its architecture.

| Contract | Owner and existing evidence |
| --- | --- |
| One active app world supplies shared resources through its composition root | [Where scope rules](../../AGENTS.md#scopes-and-the-launch), including reset and demo guard tests |
| Store mutations use `perform`. Values cross the persistence boundary | [WhereCore rules](../../WhereCore/AGENTS.md#shape--invariants) and `SwiftDataStoreTests` |
| Production refresh remains driven by the existing change signal | [Where layering](../../AGENTS.md#layering) and [WhereStore](../../WhereCore/Sources/Persistence/WhereStore.swift) |
| Generic observability cannot depend on Where | [Periscope layering](../../../Shared/Periscope/AGENTS.md#modules--dependencies) |
| Logging fields retain their classification and export controls | [PeriscopeCore rules](../../../Shared/Periscope/PeriscopeCore/AGENTS.md#invariants) |
| Developer tooling must avoid logging refresh loops | [PeriscopeTools rules](../../../Shared/Periscope/PeriscopeTools/AGENTS.md#invariants) |

Observation must not open another domain store or become a required step for committing user data.
Any proposal to change a contract needs its own rationale, tests, and owning documentation.
The first slice must define how capture ends or rebinds across scope replacement.

## Selected technical direction

Use generated provenance handles for tracked values and a separate graph of immutable value versions and operation executions.
Keep domain entity identity separate from value, execution, and delivery identity.
Preserve a value handle through copies and forwarding. Record transformations as new versions with supported input relationships.
Represent splits and merges through explicit relationships. Keep repeated executions and deliveries distinct.
Carry small handles with values and retain ancestry in the graph.
Generate routine propagation without requiring annotations. Optional annotations resolve ambiguity or add detail.
Use runtime records to establish actual data movement and outcomes.
Keep candidate source connections, entity correlation, and observed transfers distinct.
Make missing ancestry and retention explicit.

This direction is accepted in D006. Concrete generation, capture, and storage implementations remain open.
UUIDs and capture-qualified counters remain candidate identity encodings.
The initial observation contract is accepted in D007.
Track whole values and individual collection elements. Keep supported derivation distinct from invocation participation and local branch influence.
Record unknown relationships and unavailable evidence explicitly.
Complete nested-field lineage and implicit influence through arbitrary control flow remain open.

## Next technical checkpoint

Specify worked examples and their expected logical records under the [accepted observation contract](Research/008-observation-contract.md).
Start with equal independent dates, copying, transformation, and conditional persistence.
Extend the examples to collection operations, mutation, retries, repeated delivery, and opaque boundaries.
These examples must distinguish supported relationships from missing or unavailable information before the propagation implementation is selected.

P1 uses those examples for a small automatic propagation experiment and a text capture consumer.
The following checkpoints define the proposed order within that slice:

1. Specify expected value, execution, delivery, and relationship records for the examples, including evidence and unavailable-history states.
2. Generate propagation for unannotated Swift fixtures with equal independent dates, copies, transformations, splits, merges, and captures.
3. Apply the supported rules to the GPS path, including stream delivery, retries, staged writes, and save completion.

The experiment must preserve tested domain results and expose unsupported constructs.
A new forwarding function must appear after regeneration without another tracing declaration or stage configuration entry.
Build integration, coverage, active metadata, event volume, retention, and runtime cost need measured evidence.

Evaluate source transformation that generates metadata and instrumented copies for a dedicated tracing build.
If source transformation cannot preserve the selected semantics, evaluate compiler-assisted instrumentation.
Evaluate reusable adapters that preserve correlation across streams, callbacks, queues, and persistence boundaries.
Evaluate Periscope's existing task-local context and event pipeline as the foundation.
Use generated identifiers within each build and capture. Keep cross-build identity matching a separate choice.

See [the revised experiment](Research/006-automatic-instrumentation.md#revised-feasibility-experiment).
Its [provenance cases](Research/007-value-identity-and-provenance.md#proposed-experiment-additions) include mutation, repeated delivery, control dependence, and gaps.
Those cases define the coverage to assess. Their implementation and successful validation remain pending.

## Validation approach

The initial research is source inspection only. No app run, capture, benchmark, or runtime test has occurred.
The documentation change needs link, diff, and wording checks.

Implementation validation will cover event meaning, causal links, capture lifetime, and bounded retention.
Controlled tests must cover overlapping work, rollback, retries, and slow consumers.
Tests use isolated stores and scripted inputs under the repository rules.
Live acceptance needs an identified build, observation environment, action, and resulting trace.
Measure capture costs with capture disabled and enabled on the same workload.

When selecting implementation checks, use the [running-tests skill](../../../.agents/skills/running-tests/SKILL.md).
UI work also uses the [building-ui skill](../../../.agents/skills/building-ui/SKILL.md).

## Keeping the record current

1. Read this plan and the research index before continuing work.
2. Record substantive research or discussion in a numbered document under `Research/`.
3. Label source observations, proposals, decisions, and open questions separately.
4. After a decision, update this plan and link its rationale from the decision register.
5. Add branch, PR, and validation links to the relevant slice as work becomes concrete.
6. Preserve superseded research with a dated correction and a link to its replacement.

The [Where backlog](../../TODOs.md) holds the exploratory work item.
This requested plan records design and sequencing. Research documents do not create separate task lists.
File unrelated findings in their owning `TODOs.md` and link them from research.

## Progress

- 2026-10-23: Created the planning workspace and initial source research.
- 2026-10-23: Recorded the user's choice to support both Mac and in-app viewing.
- 2026-10-23: Began technical exploration of explicit GPS tracing and macro/parser generation before UI and UX.
- 2026-10-23: Recorded automatic tracing as the default requirement and revised the feasibility proposal around unannotated application source.
- 2026-10-23: Investigated generated value identities, provenance graphs, shadow propagation, and prior art for splits and merges.
- 2026-10-23: User accepted generated provenance handles and a separate graph of value versions and executions as the starting direction.
- 2026-10-23: Proposed the observation contract as the next design decision, with examples that distinguish derivation, participation, and branch influence.
- 2026-10-23: User accepted the initial observation contract. Worked examples and their expected records are the next design checkpoint.
- D0 review: [PR #425](https://github.com/kyleve/Stuff/pull/425), branch `codex/where-data-flow-plan`.
- Documentation validation: 88 local links and anchors resolve. Diff checks passed. Runtime checks do not exercise this documentation change.
- No implementation slice is complete.
