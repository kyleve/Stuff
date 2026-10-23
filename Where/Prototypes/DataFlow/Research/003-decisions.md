# Decision register

Updated: 2026-10-23.
Status: document workflow, both viewing surfaces, and automatic tracing requirement established. Implementation choices open.

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

## Open decisions

| ID | Question | Options and trade-offs | Status |
| --- | --- | --- | --- |
| O001 | Where is the viewer? | Both a separate Mac window and an in-app view | Resolved by D003 |
| O002 | What is the first flow? | GPS ingestion is the current technical scenario. A manual edit remains an alternative demonstration. | Implementation slice open |
| O003 | What does the graph explain? | Individual data movement is the current focus. The depth of derived-input lineage remains open. | Direction clarified by D004 |
| O004 | How does capture represent causality? | Compare typed relationships, task-local context, and generated handoff envelopes or correlation tables. | Research in [005](005-explicit-tracing-and-code-generation.md) and [006](006-automatic-instrumentation.md) |
| O005 | What data appears in detail? | Counts and identities, selected values, or before/after summaries have different volume and disclosure costs. | Open |
| O006 | What history is required? | Recent memory, durable local history, and replay have different lifecycle and storage costs. | Bounded recent history proposed |
| O007 | Which environments are first? | Simulator, physical device, app audience, and background operation affect capture and connectivity. | Open |
| O008 | What resource budget is acceptable? | Measure emission cost, update latency, memory growth, and display work against the chosen workload. | No numerical targets selected |
| O009 | How do both viewers share behavior? | Shared observation semantics can support different layouts. Renderer reuse and implementation order remain choices. | Open |
| O010 | Which technique provides useful automatic coverage? | Compare source transformation, compiler-assisted analysis, and reusable runtime adapters. Annotations provide optional detail. | Requirement resolved by D005. Feasibility open in [006](006-automatic-instrumentation.md) |

O002 and O003 determine the first useful demonstration after the choice of both viewing surfaces.
O004 through O010 need enough detail to bound its implementation.
They do not require a design for every future flow.

## Working proposals

These proposals are not user decisions:

- Start with one repeatable action and complete its live observation before adding broad coverage.
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
