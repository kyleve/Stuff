# Decision register

Updated: 2026-10-23.
Status: document workflow and both viewing surfaces established. Implementation choices open.

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

## Open decisions

| ID | Question | Options and trade-offs | Status |
| --- | --- | --- | --- |
| O001 | Where is the viewer? | Both a separate Mac window and an in-app view | Resolved by D003 |
| O002 | What is the first flow? | A manual edit is repeatable. GPS ingestion exposes acquisition, persistence, and retry behavior. | Manual edit proposed |
| O003 | What does the graph explain? | Component activity, one operation, or input-to-output lineage need different evidence. | Open |
| O004 | How does capture represent causality? | Compare classified Periscope events, additional correlation metadata, and a dedicated observation contract integrated with existing diagnostics. | Source evidence in [002](002-repository-map.md) |
| O005 | What data appears in detail? | Counts and identities, selected values, or before/after summaries have different volume and disclosure costs. | Open |
| O006 | What history is required? | Recent memory, durable local history, and replay have different lifecycle and storage costs. | Bounded recent history proposed |
| O007 | Which environments are first? | Simulator, physical device, app audience, and background operation affect capture and connectivity. | Open |
| O008 | What resource budget is acceptable? | Measure emission cost, update latency, memory growth, and display work against the chosen workload. | No numerical targets selected |
| O009 | How do both viewers share behavior? | Shared observation semantics can support different layouts. Renderer reuse and implementation order remain choices. | Open |

O002 and O003 determine the first useful demonstration after the choice of both viewing surfaces.
O004 through O009 need enough detail to bound its implementation.
They do not require a design for every future flow.

## Working proposals

These proposals are not user decisions:

- Start with one repeatable action and complete its live observation before adding broad coverage.
- Evaluate existing Periscope interfaces before creating another capture system.
- Define causal relationships explicitly. Label unknown relationships instead of inferring them from timing alone.
- Keep capture read-only with respect to domain behavior.
- Give both surfaces consistent observation semantics. Keep topology, transport, renderer, and module ownership open until the first flow is selected.

## Recording later decisions

For each resolved question, record the date, chosen option, rationale, and supporting discussion or experiment.
Identify whether the user chose it or implementation evidence determined it.
When the plan section and PR exist, link them.
For a changed decision, retain the earlier entry with a supersession link.
