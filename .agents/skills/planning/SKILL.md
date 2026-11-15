---
name: planning
description: Create, revise, execute, and resume durable repository plans in Plans/. Use for requested implementation plans, numbered execution phases, and plan revisions from GitHub comments. Do not use for backlog triage or simple edits that need no plan.
---

# Planning

Read the root [AGENTS.md](../../../AGENTS.md) and [Plans contract](../../../Plans/AGENTS.md).
The contract owns file structure, statuses, questions, planning horizons, and readiness requirements.
Use [BACKLOG.md](../../../BACKLOG.md) for Linear ownership and closure. Repository plan files are the durable record; an in-session task list is a view of them.

## Select the operation

Use the request and existing authorization to select creation, revision, execution, or resumption.
Planning or revision alone does not authorize implementation. A request to plan and implement authorizes both without another confirmation.
If the target is ambiguous, inspect the request, branch, and linked PR before asking. Do not select an unrelated plan by date or filename.

## Maintain the checkpoint

Maintain the overview's [checkpoint](../../../Plans/AGENTS.md#planning-checkpoint) throughout the operation.
On resume, reconcile it with the current request, prior instructions, and checkout before choosing the next action.
Ask if implementation scope remains unclear. After planning, record whether execution is already requested or awaits a new request.

## Create a plan

Use [Develop an initial plan](references/develop-plan.md).
For open-ended product planning, establish the intended experience before prescribing architecture or executable deliverables.
Use [scenario discovery and the question loop](references/develop-plan.md#discover-the-requirements) to resolve material product choices and keep dependent decisions provisional while answers are pending.
Reuse existing answers and honor explicit delegation. Scale discovery to unresolved decisions, without a fixed question quota or repeating discovery for a well-specified request.
Publish through [github-workflow](../github-workflow/SKILL.md), unless the user requests local-only work.
Link the overview and numbered plans in the PR. Identify ready plans, later outlines, and unresolved decisions affecting the current horizon.
Return the plan path, PR link, and material open questions.

## Revise a plan

For GitHub feedback, first [read the feedback](references/github-review.md#read-the-feedback).
For direct feedback, use the supplied changes without fetching unrelated discussions.
For executable refinement of an outline, [advance the planning horizon](references/develop-plan.md#advance-the-planning-horizon); ordinary outline edits need no promotion.

1. Route questions and answers through [the question loop](references/develop-plan.md#resolve-questions).
   For changes without a question, use [Apply a revision](references/revise-plan.md) directly.
2. Resolve returned questions within scope or record their execution impact and next action for handoff.
3. Publish through github-workflow. For GitHub feedback, then [close the loop](references/github-review.md#close-the-loop).

## Execute or resume

Resume the recorded operation. Resuming planning or revision does not mean starting implementation.

1. Read the overview, selected plans, dependency records, and applicable repository instructions.
   Inspect the branch, working tree, commits, and actual source. For a linked PR, [read current plan feedback](references/github-review.md#read-the-feedback) and revise relevant changes within existing authorization.
   Report unavailable feedback as a gap.
2. Reconcile progress and evidence with the checkout before repeating work.
   Distinguish committed work, uncommitted work, and steps that never ran. Resume pending answer integration and revisit due deferrals.
3. Establish readiness:
   - Skip valid `complete` and `superseded` plans. Investigate evidence that disagrees with the source.
   - Refine selected outlines through [Advance the planning horizon](references/develop-plan.md#advance-the-planning-horizon).
   - Finish drafts, resolve blockers, and [review the plan](references/develop-plan.md#review-the-plan) when review is missing or invalidated by material changes.
   - Verify dependencies are complete and their results exist. Revise consumers of a superseded dependency to its replacement.
   Continue only independent, ready work if another plan remains blocked.
4. Mark the selected plan `executing` and implement its steps within the authorized requirements and exclusions.
   Request authorization for additional scope. Use [running-tests](../running-tests/SKILL.md), [code-review](../code-review/SKILL.md), and github-workflow for verification and publication.
5. After meaningful steps, record progress, actual commands/results, relevant revisions or artifacts, and the resume point.
   Keep concise evidence in tracked files rather than relying on ignored logs or chat.
6. Revise plans affected by source findings before dependent work continues.
   Integrate experiment results through the question loop. Resolve routine details within scope; record externally blocked work with its next action.
7. Complete plans under the [completion rules](../../../Plans/AGENTS.md#status), recording the outcome and implementation PR or requested local-only handoff.
   Reconcile linked issues through [Linear issue lifecycle](../github-workflow/SKILL.md#linear-issue-lifecycle).
8. Advance the horizon before selecting the next plan. Continue authorized work without confirmation between steps.
   At handoff, report remaining work and validation limits.

## Delegated execution handoff

When plan execution is delegated within the user's authorization, record the owning agent, plan, branch/worktree, and reporting responsibility in the overview checkpoint.
Give the worker the required return information: artifact or PR link, tested and published revision, checks, remaining work, and any blocker.
When the worker returns, reconcile its result with the plan and publication state, then report completion or the blocker to the user without waiting for a status request.
Distinguish an implemented and checked artifact from a published handoff and from experiment acceptance that still needs user evaluation.
If background delivery cannot be observed in the current environment, say so before promising a later notice and arrange an available handoff.
