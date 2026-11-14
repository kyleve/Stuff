---
name: todo-triage
description: Maintain the Stuff backlog in Linear. Verify Triage submissions, file and refine findings, close verified work, and refresh the repository module audit. Use for backlog maintenance, intake triage, or the weekly module audit.
---

# Backlog triage

Read [BACKLOG.md](../../../BACKLOG.md) for the destination, access commands, labels, evidence requirements, and closure rules.
Linear’s Stuff team (`STU`) is the sole live backlog.
Keep the existing skill name so scheduled and ad-hoc callers continue to work.

## Establish access and scope

1. Verify access to the `STU` team through the pinned CLI.
2. Retrieve every issue needed for the pass, across all assignees and pages.
3. Include completed and archived issues when searching history or checking duplicates.
4. If access fails or a response is incomplete, report the blocker. Do not infer an empty backlog.

An ad-hoc request uses only the relevant procedure below.
An authorized triage or review request permits evidence-backed Linear edits directly.
Summarize those edits with issue links. Repository changes still use PRs.

## Process Triage

1. Read the full issue, comments, and original human request.
2. Verify the claim against current source. Separate bugs, feature requests, questions, and already completed work.
3. Search existing issues by symbols, paths, and behavior before creating another issue.
4. Expand an accepted request with evidence, consequences, a suggested fix, and acceptance conditions.
5. Apply the area, module, type, effort, and origin labels. Preserve human priority decisions and the original attribution date.
6. Move verified work to Backlog. Keep ambiguous requests in Triage with a concise clarification comment.
7. For declined or duplicate requests, record the reason and link the canonical issue before changing the state.

Do not fabricate verification to empty the queue.
Human requests remain identifiable after an agent rewrites their description.

## File or refine an agent finding

Verify the finding before filing it directly in Backlog.
Search open, completed, and archived work first.
Update a matching issue when the evidence refines the same problem.
Do not reopen a completed issue merely because a similar symbol appears in a new failure.
Explain the regression or remaining acceptance condition first.

Preserve human descriptions, decisions, and corrections when updating an issue.
Read the current issue immediately before a write and change only the intended fields.
After an uncertain create or update, inspect the result before retrying.
Do not create a second issue to recover from an unavailable response.

Deferred PR feedback follows [github-workflow](../github-workflow/SKILL.md).
Link the resulting Linear issue in the review reply.

## Close work

Verify the original acceptance conditions against current source and relevant evidence.
An unmerged PR stays In Review. A partial fix keeps an open remainder.
Record the merged PR or commit, merge date, actual result, and verification limits.
Distinguish a shipped fix from deletion or a superseded proposal.

Inspect rendered output for visual defects and runtime behavior for navigation or scroll reachability.
A green snapshot comparison or an LFS pointer does not establish visual correctness.
Keep unverified requirements open during static-only passes.

## Weekly pass

1. Continue an unfinished matching audit PR, or use an isolated worktree from current `origin/main`.
2. Process Linear Triage using the procedure above.
3. Re-verify the open backlog by area. Correct stale evidence and close only work with sufficient proof.
4. Review commits and merged PRs since the previous audit’s header date. File supported new findings with audit provenance.
5. Refresh `MODULE_AUDIT.md` from the verified result. Preserve the prior date in the diff.
6. Update module documentation invalidated by the work. Run `./sync-agents` after instruction or skill changes.
7. Run applicable checks and publish repository changes through [github-workflow](../github-workflow/SKILL.md). Leave the PR open for review.
8. Report created, materially changed, and closed Linear issues, the audit PR, checks, and blockers.

The report contains the module inventory, verified-clean areas, cross-cutting themes, and links to findings in Linear.
It carries no independent actionable items or copied issue bodies.
Its date describes verification coverage, not the latest repository commit or migration date.

Use checks available in the actual execution environment.
The current scheduled job runs locally; a future Linux run has different verification limits.
State those limits rather than implying unavailable simulator or runtime checks passed.
