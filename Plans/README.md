# Repository plans

Plans in this directory describe how to implement selected work.
Each series contains an overview and one or more numbered Markdown files.
Git preserves the plans, review changes, and execution records across sessions.

```text
Plans/
  YYYY-MM-DD-topic/
    README.md
    01-first-deliverable.md
    02-second-deliverable.md
```

The [planning skill](../.agents/skills/planning/SKILL.md) supports planning, revision, execution, and resumption.
The [directory contract](AGENTS.md) defines structure, ownership, and status.

## Start a plan

Ask the agent to use `$planning` and describe the desired outcome.
For example: "Use $planning to plan the backup migration. Publish the plan for review."

The skill starts with discovery of requirements and current behavior, then researches material unknowns.
It asks focused questions and records evidence, assumptions, and decisions in the overview.
Before marking plans ready, it reviews contradictions, missing requirements, scope additions, and agreement with repository constraints.
Unresolved decisions remain visible with their impact and next action.
The overview records the current operation, scope, planning stage, and next action before numbered plans exist.
Questions have stable IDs and progress through `open`, `answered`, and `closed`, or become explicitly `deferred`.
The agent integrates answers into the plan and reviews consistency before closing questions.
Deferred questions retain a reason, revisit condition, and next action. Blocking questions continue to block their plans.

The skill starts with the [overview template](../.agents/skills/planning/assets/overview.md).
A small change needs only one numbered plan.
Plans inside the current horizon use the [executable template](../.agents/skills/planning/assets/plan.md).
They include acceptance criteria, progress, decisions, and a resume point.
User stories and requirements have stable IDs for review and acceptance checks.
Mermaid diagrams show data flows. Swift pseudocode shows proposed architecture, ownership, and interfaces.
Plans also state unnecessary capabilities and explicitly avoided approaches to constrain implementation scope.
Planning alone does not start implementation.

## Rolling-wave planning

The planning horizon usually covers the next one or two deliverables in detail.
Later selected work uses the [outline template](../.agents/skills/planning/assets/outline.md) in numbered files with status `outline`.
These outlines retain outcomes, known requirements, exclusions, dependencies, assumptions, questions, and a trigger for refinement.
Diagrams and Swift sketches show known boundaries. Unresolved details link to questions instead of speculative interfaces or implementation steps.

After a deliverable completes, the agent uses its actual results to reconsider the next horizon.
It expands selected outlines in place, resolves relevant questions, and reviews them before implementation.
Agreed requirements and exclusions remain in force as the design develops.
GitHub comments can refine either detailed plans or outlines without changing their paths.

The whole series receives a scope and dependency review. Executable detail is required for plans that must be ready now.
A later question blocks earlier work only when its answer affects that work's implementation or acceptance.
Questions awaiting later selected work link to the outline and its refinement trigger. Work outside the series stays in `TODOs.md`.

## Review on GitHub

The plan PR links the overview and numbered files.
Add inline comments in **Files changed**, review summaries, or PR conversation comments.
Then ask: "Use $planning to revise Plans/YYYY-MM-DD-topic from the comments on PR #123."

The agent reads the complete relevant discussions and revises affected plans.
It records comment links and decisions, then pushes changes and replies with the revision commit.
The agent resolves threads only when requested.
Comments do not automatically start an agent run.

## Execute or resume

Ask: "Use $planning to execute Plans/YYYY-MM-DD-topic."
To limit scope, name a numbered plan file.
Ask: "Use $planning to resume Plans/YYYY-MM-DD-topic" to continue existing authorized work.

The agent reconciles recorded progress with the current source before continuing.
Outlines become executable drafts before plan review. Only reviewed, ready plans can start implementation.
Material changes require another review of the affected plan.
Plan files retain verification results, partial work, and the next action.
Completed plans remain available at their original paths.

## Backlog

The owning `TODOs.md` retains backlog items and links to their execution plans.
A direct request can start a plan without creating a duplicate backlog item.
Work deferred outside the series belongs in `TODOs.md`, with a link from the plan.
