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

Read [references/develop-plan.md](references/develop-plan.md) before developing an initial plan.
Use its discovery, research, question resolution, drafting, and review stages.
Keep findings in the plan files as work proceeds.
Scale the depth to the uncertainty and scope, without requiring a questionnaire for a well-specified request.

Publish the reviewable files through [github-workflow](../github-workflow/SKILL.md), unless the user requests local-only work.
Link the overview and numbered plans in the PR body.
State whether the plan is ready for execution or still has unresolved decisions.
Return the plan path, PR link, and material open questions.

## Revise a plan

For GitHub feedback, read [references/github-review.md](references/github-review.md).
For direct feedback, apply the same plan updates without fetching unrelated GitHub discussions.

1. Read the current plan, shared decisions, execution record, and affected source.
2. Update the relevant stories, requirements, exclusions, diagrams, Swift sketches, steps, and verification together.
   Trace changes into dependent plans and the overview.
   Preserve story and requirement IDs so existing review comments remain traceable.
   If feedback would cross an explicit exclusion, use existing user authorization or request the missing decision before changing it.
3. Record the decision, reason, date, and feedback link in the owning plan.
   Put series-wide decisions in the overview.
   Use [the question loop](references/develop-plan.md#resolve-questions) for new questions or answers to existing questions.
   Avoid a transcript of the whole discussion.
4. If changed acceptance criteria invalidate earlier evidence, record that evidence as stale.
   Reset affected completion checkboxes and status to reflect the remaining work.
   Preserve the earlier execution record.
   For completed plans, use the follow-up rule in the Plans contract.
5. If feedback changes the underlying requirements or evidence, revisit discovery or research.
   Use [the plan review procedure](references/develop-plan.md#review-the-plan) on the affected series.
   Publish through github-workflow.
   Report unresolved decisions and their effect on execution.

## Execute or resume

If resuming planning or revision, recover the recorded state and use that operation's procedure instead of implementing.

1. Read the overview, selected plans, dependency records, and applicable repository instructions.
   Inspect the current branch, working tree, commits, and actual source.
   If a linked PR exists, read its current plan feedback through the GitHub review reference.
   If feedback is unavailable, report the gap rather than assuming the review is clear.
2. Reconcile recorded progress with the checkout before repeating work.
   Resume pending question integration and inspect deferred questions whose revisit conditions now apply.
   Distinguish committed implementation, uncommitted work, and steps that never ran.
   If recorded evidence conflicts with the source, investigate and correct the record.
3. Verify that dependencies are complete and their required results exist in the checkout.
   If the selected plan still has an unresolved blocker, stop its implementation and report the missing prerequisite.
   Exclude `superseded` plans from execution.
   If a dependency is superseded, update its consumers to the replacement before continuing.
4. Mark the selected plan `executing` and implement its steps in order.
   Keep implementation within the requirements and exclusions.
   If additional scope seems necessary, record the reason and request authorization before implementing it.
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
