# Decision register

Updated: 2026-10-24.
Status: document workflow, viewing surfaces, automatic tracing, provenance direction, and initial observation contract established. Concrete implementation choices open.

## Recorded decisions

### D001 — Keep a durable plan and supporting documents

Date: 2026-10-23.
Basis: explicit user request in the initiating conversation.

The [plan](../PLAN.md) carries the current direction and proposed sequence of PRs.
The adjacent research folder preserves evidence and discussion for later reference.
The folder path is an organizational choice from this initial task.

### D002 — Observe real activity in Where

Date: 2026-10-23.
Basis: explicit user goal in the initiating conversation.

The prototype must show real data flow from the running app.
Synthetic fixtures can support development, but they do not satisfy the live demonstration.
The request does not require publishing raw personal data in repository documents or PRs.

### D003 — Support both viewing surfaces

Date: 2026-10-23.
Basis: explicit user reply to O001.

The prototype needs a separate Mac window and a view inside Where.
This resolves the viewer-location question without selecting implementation order, rendering technology, or transport.
Discussion and implications: [004 — Both viewing surfaces](004-viewing-surfaces.md).

### D004 — Discuss explicit data tracing before UI and UX

Date: 2026-10-23.
Basis: explicit user request in the next planning discussion.

The current technical discussion follows an individual GPS point through the app to persistence.
It evaluates macros and source parsing as ways to generate system metadata and tracing support.
The user has not selected a specific generation technique or instrumentation API.
Research and the proposed experiment: [005 — Explicit tracing and code generation](005-explicit-tracing-and-code-generation.md).

### D005 — Make tracing automatic by default

Date: 2026-10-23.
Basis: explicit user clarification about annotation cost.

Ordinary tracing must not require annotations throughout application code.
Annotations can resolve ambiguous cases or add detail.
Automatic coverage and maintenance cost need evidence before selecting a generation technique.
The user did not select source transformation, a compiler modification, or a particular adapter design.
Research and the revised experiment: [006 — Automatic instrumentation](006-automatic-instrumentation.md).
This supersedes the annotation-led working proposal in 005, not its GPS source findings.

### D006 — Use generated provenance handles and a separate graph

Date: 2026-10-23.
Basis: the user accepted the recommendation after the value identity and provenance discussion.

Use automatically generated provenance handles with a separate graph of immutable value versions and operation executions.
Keep domain entity, value-version, execution, and delivery identities distinct.
Preserve provenance through copies and forwarding. Record supported derivation for transformations, splits, and merges.
Store ancestry relationships in the graph so values carry small handles.
The no-required-annotations decision in D005 continues to apply.

The selected direction comes from [007 — Value identity and provenance](007-value-identity-and-provenance.md).
The next technical checkpoint tests automatic propagation before viewer work.
At this decision, UUIDs versus counters, the generation mechanism, tracking granularity, transport, and the storage engine remained open.
D007 subsequently selects the initial tracking granularity and relationship meanings.
This decision selects the starting architecture. It does not establish feasibility or completed implementation.

### D007 — Adopt the initial observation contract

Date: 2026-10-23.
Basis: the user accepted the recommended contract with “SGTM”.

Track whole values and individual collection elements within the configured capture scope.
Copies preserve provenance. Transformations create new versions with supported input relationships.
Keep invocation participation distinct from established value derivation.
Record supported branch decisions and their local execution relationships separately from value derivation.
Opaque code can expose observed inputs and outputs while their internal relationship remains unknown.
Record relationship evidence, granularity, and unavailable history explicitly. Missing edges do not establish independence.
Ordinary tracing continues to require no annotations under D005.

The accepted contract is [008 — Observation contract](008-observation-contract.md).
Complete nested-field lineage and implicit influence through arbitrary control flow remain open.
Worked examples and their expected logical records are the next design checkpoint, before the propagation implementation.
The decision does not select an instrumentation technique, ID encoding, API, transport, or storage engine.
No compiler experiment or runtime capture has validated the contract yet.

## Open decisions

| ID | Question | Options and trade-offs | Status |
| --- | --- | --- | --- |
| O001 | Where is the viewer? | Both a separate Mac window and an in-app view | Resolved by D003 |
| O002 | What is the first flow? | GPS ingestion is the current technical scenario. A manual edit remains an alternative demonstration. | Implementation slice open |
| O003 | What does the graph explain? | Start with whole values, collection elements, supported derivation, participation, and local branch influence. Complete field and implicit control-flow provenance remain open. | Initial scope resolved by D007. Contract in [008](008-observation-contract.md) |
| O004 | How does capture represent causality? | Generated handles refer to a separate value-version and execution graph. Relationship meaning and evidence remain distinct. Propagation mechanics and measured coverage remain open. | D006 and D007 establish the starting model. [009](009-worked-date-trace.md) proposes concrete logical records |
| O005 | What data appears in detail? | Counts and identities, selected values, or before/after summaries have different volume and disclosure costs. | Open |
| O006 | What history is required? | Recent memory, durable local history, and replay have different lifecycle and storage costs. | Bounded recent history proposed |
| O007 | Which environments are first? | Simulator, physical device, app audience, and background operation affect capture and connectivity. | Open |
| O008 | What resource budget is acceptable? | Measure emission cost, update latency, memory growth, and display work against the chosen workload. | No numerical targets selected |
| O009 | How do both viewers share behavior? | Shared observation semantics can support different layouts. Renderer reuse and implementation order remain choices. | Open |
| O010 | Which technique provides useful automatic coverage? | Compare source transformation, compiler-assisted analysis, and reusable runtime adapters. Annotations provide optional detail. | Requirement resolved by D005. Feasibility open in [006](006-automatic-instrumentation.md) |
| O011 | How are trace identities allocated? | Compare UUIDs and capture-qualified counters within the distinct identity roles selected by D006. | Analysis in [007](007-value-identity-and-provenance.md). Encoding open. |

O002 still determines the first useful demonstration within the initial scope selected by D007.
The remaining parts of O003 through O011 need enough detail to bound its implementation.
They do not require a design for every future flow.

## Working proposals

These proposals are not user decisions:

- Start with one repeatable action and complete its live observation before adding broad coverage.
- Specify expected example records under the accepted observation contract before selecting the propagation implementation.
- Use the [worked date trace](009-worked-date-trace.md) to assess separate value handles, binding occurrences, input origins, and persistence evidence.
- Evaluate existing Periscope interfaces before creating another capture system.
- Define causal relationships explicitly. Label unknown relationships instead of inferring them from timing alone.
- Generate routine instrumentation and evaluate adapters shared across call sites. Measure coverage without per-stage declarations.
- Keep capture read-only with respect to domain behavior.
- Give both surfaces consistent observation semantics. Keep topology, transport, renderer, and module ownership open until the first flow is selected.

## Recording later decisions

For each resolved question, record the date, chosen option, rationale, and supporting discussion or experiment.
Identify whether the user chose it or implementation evidence determined it.
When the plan section and PR exist, link them.
For a changed decision, retain the earlier entry with a supersession link.
