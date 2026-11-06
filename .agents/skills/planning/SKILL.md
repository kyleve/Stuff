---
name: planning
description: Create, revise, execute, and resume durable repository plans in Plans/. Use for requested implementation plans, numbered execution phases, and plan revisions from GitHub comments. Do not use for backlog triage or simple edits that need no plan.
---

# Planning

Read the root [AGENTS.md](../../../AGENTS.md) and [Plans contract](../../../Plans/AGENTS.md).
Use repository files as the durable record for planning and execution.
Treat any in-session task list as a view of those files.

## Select the operation

Use the user's request and existing authorization to select the operation:

| Request | Operation |
| --- | --- |
| Develop a plan | Create or refine plan files, then hand them over for review. |
| Revise a plan or address its comments | Update the plan and affected dependent plans. |
| Execute a plan | Implement the selected plan or series within the authorized scope. |
| Resume a plan | Recover its recorded state, then continue the authorized operation. |

A planning or revision request does not authorize the proposed implementation.
A request to plan and implement authorizes both operations without another confirmation.
If the target is ambiguous, inspect the request, branch, and linked PR first.
If several candidates remain, ask which plan to use.
Do not select an unrelated plan by its date or filename alone.

## Create a plan

1. Read the affected source and its applicable `AGENTS.md` files.
   Identify the existing guards and required skills.
2. Define the user-visible outcome, scope, exclusions, and unresolved decisions.
   Record material assumptions and research evidence in the plan.
   If a decision blocks implementation, mark the affected plan `blocked` and name the missing answer.
3. Create `Plans/YYYY-MM-DD-<topic>/` using the user's local date.
   If that path already exists, inspect it before choosing another unique topic name.
   Copy [assets/overview.md](assets/overview.md) to the series `README.md`.
   Copy [assets/plan.md](assets/plan.md) for each numbered plan.
   Replace placeholders and remove unused template instructions.
4. Start with one plan, such as `01-deliverable.md`.
   Split only at independently verifiable deliverables or useful review boundaries.
   Keep setup and documentation with the deliverable that needs them.
5. List the plans in execution order in the overview.
   Give each plan explicit dependency links, even when filename order also expresses the dependency.
   Prefer sequential execution unless independent work materially benefits from parallel execution.
   Follow the session's delegation rules.
6. Write concrete steps with affected paths, interfaces, and observable acceptance criteria.
   Use repository-relative source paths and working directories for commands.
   Include recovery instructions for steps that can leave partial state.
   Link shared context instead of copying it across every plan.
7. Review the complete series for missing requirements, dependency cycles, conflicting interfaces, and untestable acceptance criteria.
   Verify that a fresh session can continue from the files and their repository references.
   Mark executable plans `ready`.
8. Use [github-workflow](../github-workflow/SKILL.md) to publish the reviewable plan files, unless the user requests local-only work.
   Link the overview and numbered plans in the PR body.
   State that the PR contains a plan and identify the decisions needing review.
   Return the plan path and PR link.

## Revise a plan

For GitHub feedback, read [references/github-review.md](references/github-review.md).
For direct feedback, apply the same plan updates without fetching unrelated GitHub discussions.

1. Read the current plan, shared decisions, execution record, and affected source.
2. Update the relevant requirements, steps, interfaces, and verification together.
   Trace changes into dependent plans and the overview.
3. Record the decision, reason, date, and feedback link in the owning plan.
   Put series-wide decisions in the overview.
   Avoid a transcript of the whole discussion.
4. If changed acceptance criteria invalidate earlier evidence, record that evidence as stale.
   Reset affected completion checkboxes and status to reflect the remaining work.
   Preserve the earlier execution record.
   For completed plans, use the follow-up rule in the Plans contract.
5. Review the revised series and publish through github-workflow.
   Report unresolved decisions and their effect on execution.

## Execute or resume

If resuming planning or revision, recover the recorded state and use that operation's procedure instead of implementing.

1. Read the overview, selected plans, dependency records, and applicable repository instructions.
   Inspect the current branch, working tree, commits, and actual source.
   If a linked PR exists, read its current plan feedback through the GitHub review reference.
   If feedback is unavailable, report the gap rather than assuming the review is clear.
2. Reconcile recorded progress with the checkout before repeating work.
   Distinguish committed implementation, uncommitted work, and steps that never ran.
   If recorded evidence conflicts with the source, investigate and correct the record.
3. Verify that dependencies are complete and their required results exist in the checkout.
   If the selected plan still has an unresolved blocker, stop its implementation and report the missing prerequisite.
   Exclude `superseded` plans from execution.
   If a dependency is superseded, update its consumers to the replacement before continuing.
4. Mark the selected plan `executing` and implement its steps in order.
   Use [running-tests](../running-tests/SKILL.md) for appropriate verification.
   Use [code-review](../code-review/SKILL.md) and github-workflow for review and publication.
5. After each meaningful step, update progress, verification evidence, and the resume point.
   Record the actual command, result, and relevant revision or artifact.
   Keep concise evidence in tracked files rather than relying on ignored logs or chat history.
6. If source findings require a plan change, revise the affected files before continuing dependent work.
   Resolve routine details within scope and record the decision.
   If progress needs an external answer, record `blocked`, the blocker, and the next action.
7. Continue through the authorized plans without asking for confirmation between steps.
   At a stopping point, record partial work and the exact next action.
8. Mark a plan `complete` only after its acceptance criteria pass and required review and publication finish.
   Record the outcome and implementation PR link, or the requested local-only handoff.
   Reconcile linked backlog items under the root TODO rules.
   Report remaining work and validation limits honestly.
