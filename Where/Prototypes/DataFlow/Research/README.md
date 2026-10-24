# Data flow research and discussions

The [plan](../PLAN.md) records the current direction and proposed sequence of PRs.
This folder preserves the evidence, alternatives, and reasoning behind that plan.

## Index

| Document | Date | Status | Contents |
| --- | --- | --- | --- |
| [001 — Initial brief](001-initial-brief.md) | 2026-10-23 | User intent recorded. Scope open | Goal, document workflow, and candidate debugging questions |
| [002 — Repository map](002-repository-map.md) | 2026-10-23 | Source inspection | Existing flow boundaries, observability, and limits |
| [003 — Decisions](003-decisions.md) | 2026-10-23 | Core direction and initial observation contract selected. Implementation questions open | Current choices, proposals, and decision history |
| [004 — Both viewing surfaces](004-viewing-surfaces.md) | 2026-10-23 | User decision recorded | Separate Mac window and view inside Where |
| [005 — Explicit tracing and code generation](005-explicit-tracing-and-code-generation.md) | 2026-10-23 | Annotation approach superseded by 006 | GPS identity, stage metadata, macro limits, and asynchronous handoffs |
| [006 — Automatic instrumentation](006-automatic-instrumentation.md) | 2026-10-23 | User requirement recorded. Feasibility open | Automatic discovery, source transformation, reusable adapters, optional annotations, and revised experiment |
| [007 — Value identity and provenance](007-value-identity-and-provenance.md) | 2026-10-23 | Direction accepted by D006. Feasibility open | Counters and UUIDs, value versions, shadow propagation, split/merge relationships, and bounded storage |
| [008 — Observation contract](008-observation-contract.md) | 2026-10-23 | Initial contract accepted by D007. Worked examples pending | Value granularity, relationship meaning, branch influence, evidence limits, and proposed example cases |

## Adding a document

Use the next number and a descriptive name, such as `009-propagation-experiment.md`.
Record the date, question, status, and source revision or external sources near the start.
Separate observed facts from proposed interpretations.
For experiments, record the environment, procedure, result, and limits of the evidence.
For discussions, record the alternatives, user decisions, and unresolved points.
Add the document to this index and link consequential decisions from the plan.

Research records can become stale as the code changes.
Before using an old finding, read its cited source at the current revision.
Preserve old reasoning with a correction or supersession note instead of silently replacing it.

Keep raw personal captures outside Git.
Committed examples use synthetic data or explicitly prepared, sanitized extracts.
