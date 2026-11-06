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
  The overview owns shared context and decisions.
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

## Review

Verify links, dependencies, status, and agreement between steps and acceptance criteria.
When revising plans from GitHub comments, preserve decisions and execution evidence.
