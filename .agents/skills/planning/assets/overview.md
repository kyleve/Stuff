# [Topic]

<!-- Copy to Plans/YYYY-MM-DD-topic/README.md. Replace placeholders and remove instructions. -->

## Planning checkpoint

- Updated: [Date and relevant source revision]
- Operation: [Plan, revise, or execute]
- Requested scope and source: [Selected work and limits, with a dated request summary or link]
- Stage: [Discovery, research, questions, drafting, review, implementation, or handoff]
- Completed: [Last completed activity and link to its findings]
- Pending: [Unfinished investigation, question IDs, feedback links, or numbered-plan resume points]
- Next action: [Exact continuation step, or Waiting for a specified answer or execution request]

<!-- Update at stage changes and stopping points. Record existing intent, not inferred permission to implement. -->

## Outcome and scope

[Explain the user-visible outcome and included work.]

## User stories

<!-- Keep IDs stable across revisions. Replace examples with the actual actors, needs, and outcomes. -->

| ID | Story |
| --- | --- |
| US-01 | As a [user or maintainer], I want [capability], so that [benefit]. |

## Requirements

| ID | Required behavior or constraint | Story | Implementing plan |
| --- | --- | --- | --- |
| R-01 | [Concrete, verifiable requirement] | US-01 | [01-deliverable.md](01-deliverable.md) |

<!-- Include relevant failure behavior and nonfunctional constraints. Explain requirements without a direct user story. -->

## Not required and explicitly avoided

| ID | Category | Exclusion | Reason |
| --- | --- | --- | --- |
| X-01 | Not required | [Capability outside this work] | [Why it is unnecessary for the outcome] |
| X-02 | Explicitly avoided | [Approach or behavior the implementation must not introduce] | [Constraint or trade-off] |

<!-- These are scope boundaries, not promises of future work. Write None if there are no exclusions. -->

## Context

[Describe the current behavior and relevant repository paths.]
[If a source backlog item exists, link it. Otherwise state that this is a direct request.]

## Discovery

[Describe the users, current problem, and success criteria established from the request and source inspection.]
[Record material constraints and link clarification answers from Questions and resolutions.]

## Research and evidence

| Question or assumption | Finding and evidence | Implication for the plan |
| --- | --- | --- |
| [Unknown tied to a requirement or decision] | [Observed, inferred, or unresolved. Source path or URL and relevant revision/version.] | [Design decision, constraint, or remaining gap] |

[If external research is unnecessary, state why and cite the repository evidence used.]
[Record meaningful alternatives and the selected approach in Shared decisions.]

## Design overview

[Link the Mermaid data flows and Swift architecture sketches in the numbered plans.]
[If a flow spans multiple plans, include its shared diagram here and link it from those plans.]

## Execution order

| Order | Plan | Deliverable |
| --- | --- | --- |
| 1 | [01-deliverable.md](01-deliverable.md) | [Observable result] |

<!-- Each numbered plan owns its status, dependencies, progress, and verification evidence. -->

## Shared decisions

| Date | Decision and reason | Source |
| --- | --- | --- |
| [YYYY-MM-DD] | [Decision affecting multiple plans] | [Request or GitHub comment URL] |

## Questions and resolutions

| ID | Status | Question | Affected requirements or plans | Blocking impact | Next action |
| --- | --- | --- | --- | --- | --- |
| [Q-01](#q-01) | open | [Decision or feasibility gap] | [IDs or plan links] | [What cannot proceed, or Nonblocking with reason] | [Who or what can resolve it] |

<!-- Use open, answered, closed, or deferred. Keep closed records and stable IDs. Write None only if no questions were raised. -->

### Q-01

- Answer and source: [Pending, or dated answer with a source path, GitHub comment URL, or summary of the user's response]
- Integration: [Pending, or links to changed requirements, decisions, design sections, steps, and acceptance criteria]
- Resolution history: [Dated closure after consistency review, or reopening with its reason and previous answer retained]
- Deferral: [None, or reason, revisit condition, next action, and backlog link for remaining work]

<!-- An answer alone does not close a question. Deferral alone does not unblock a plan. -->

## Plan review

- Reviewed: [Date, source revision, and plan files reviewed, or Not reviewed]
- Findings and disposition: [Contradictions, unsupported assumptions, coverage gaps, scope additions, and their resolution, or None found]
- Readiness: [Ready plans, blocked plans and reasons, or Still drafting]
- Validation limits: [Unverified claims, diagram rendering limits, or planned feasibility experiments]

<!-- This records review of the plan, not proof that its implementation works. Refresh after material revisions. -->

## Review and delivery

- Plan review: [PR URL, or Not published]
- Implementation: [PR URLs, or Not started]
- Review focus: [Decisions or constraints needing attention]

## Outcome

[Not started. At completion, record the overall result and links to any deferred backlog items.]
