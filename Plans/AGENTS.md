# Plans

This directory holds durable execution plans. See [README.md](README.md) for usage and the root [AGENTS.md](../AGENTS.md) for repository rules.
Use the [planning skill](../.agents/skills/planning/SKILL.md) to create, revise, execute, or resume plans.

## Structure and ownership

- Keep each series in `YYYY-MM-DD-<topic>/`, with one `README.md` overview and numbered `NN-<deliverable>.md` plans.
- Keep each reviewed filename and plan number stable.
  For inserted work, use an ordered suffix such as `01a-prerequisite.md` and update the overview.
- Keep execution order in the overview and explicit dependency links in each plan.
  Dependencies must exist and form an acyclic graph.
- Each numbered plan owns its status, progress, evidence, and resume point.
  The overview owns shared context, decisions, and the operation checkpoint.
- Track plans and concise execution records in Git.
  Keep completed plans at their original paths.
- When scope changes, preserve completed history.
  Add a linked follow-up plan for new work after completion.
  If a completion claim was incorrect, reopen the plan and record why.
- Keep deferred work in the owning `TODOs.md` and link it from the plan.
  Plans describe execution of selected work, not a second backlog.

## Status

Use `draft`, `ready`, `executing`, `blocked`, `complete`, or `superseded`.
`ready` means that the plan is executable, not that the user authorized implementation.
`blocked` requires a recorded blocker and next action.
`complete` requires acceptance evidence and the required review and publication.
`superseded` requires a replacement link or a recorded cancellation reason.
Implementation requires a current plan review and status `ready` or `executing`.

## Planning checkpoint

Keep a checkpoint in the overview before substantial discovery or research, even when numbered plans do not exist yet.
Record the operation, requested scope and its source, current stage, completed work, pending work, and next action.
Update it at stage changes and stopping points.
Link question records and numbered-plan resume points instead of duplicating them.
The checkpoint records existing user intent, not additional authorization.

## Questions

Keep a question register in the overview with stable `Q-NN` IDs and these statuses:

| Status | Meaning |
| --- | --- |
| `open` | Needs investigation or an answer. |
| `answered` | Answer recorded, but integration into the plan remains incomplete. |
| `closed` | Resolution incorporated into affected plan sections and reviewed for consistency. |
| `deferred` | Deliberately postponed with a reason, revisit condition, and next action. |

Record each question's affected requirements or plans, blocking impact, answer source, and resolution history.
Link deferred work to its owning `TODOs.md` item.
Keep closed questions and their IDs. If new evidence invalidates a resolution, reopen the same question and preserve its history.
Deferral does not remove a blocker. An `answered` blocking question remains blocking until its resolution is integrated.
Question closure does not authorize resolution of its GitHub review thread.

## Reviewable design

- Give user stories, requirements, and exclusions stable IDs within each series.
  Keep shared definitions in the overview and link them from each implementing plan.
  Map requirements to deliverables and acceptance criteria.
- Include Mermaid data flows and high-level Swift pseudocode for proposed architecture.
  Label existing components, proposed components, and omitted details.
  If a diagram or sketch does not apply, record the reason instead of inventing architecture.
- State what is not required and what implementation approaches are explicitly avoided.
  Keep these exclusions consistent across requirements, diagrams, sketches, and steps.
  An exclusion remains in force until the user authorizes its revision.

## Review

Keep discovery findings, research evidence, unresolved questions, and the plan review record in the overview.
Distinguish observed facts, inferences, and user decisions.
Do not mark a plan ready while an unresolved question blocks its implementation or acceptance, including answered or deferred questions.
Verify links, dependencies, status, and agreement between requirements, design, steps, exclusions, and acceptance criteria.
When revising plans from GitHub comments, preserve decisions and execution evidence.
