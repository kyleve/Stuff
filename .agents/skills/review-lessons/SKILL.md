---
name: review-lessons
description: Audit human and agent review findings and follow-up fixes to improve repository guidance and enforcement. Use for the monthly review retrospective or an explicit review of recurring mistakes.
---

Read the root [AGENTS.md](../../../AGENTS.md) and
[github-workflow](../github-workflow/SKILL.md) before changes.
Use this procedure monthly, or after a recurring failure needs investigation.
The weekly [todo-triage](../todo-triage/SKILL.md) pass owns backlog maintenance and module audits.
[code-review](../code-review/SKILL.md) owns review of a current PR or completed branch.

## Establish the review window

1. Inspect the checkout and fetch `origin/main`.
   Unless the user specifies a base or stack, use a clean branch from current `main`.
   Search open PRs for an unfinished review-lessons audit before creating another one.
   If one exists, continue it through the GitHub workflow.
2. Use the requested period, or start from the last complete audit's recorded end time.
   Find that time in its PR body or accessible run summary.
   If no complete record is available, review the previous three months.
   Fix an end time in UTC before collection.
   Record both boundaries and the source revision.
3. Use three months of context to identify recurring patterns, including lessons from the previous audit.
   Treat that context as an overlap, not as new evidence on every run.
   Compare prior audit changes with current source to identify which changes actually landed.

## Collect and verify evidence

- Find PRs updated during the review window, including older, closed, and still-open PRs.
  Read inline threads, submitted reviews, conversation comments, and follow-up fixes.
  Include resolved threads and later corrections to the original feedback.
- Include completed agent-review reports available in the current task or linked to the reviewed PRs.
  Preserve findings fixed before publication when the review report or fix history records them.
  Record inaccessible or unrecorded reviews as a coverage limit. A PR-only collection cannot establish complete agent-review coverage.
- Use scoped `TODOs.md` files, including completed items, and dated `MODULE_AUDIT.md` reports to locate agent-found issues and fixes.
  Verify them against source and history. A backlog entry or stale audit is not proof of a current defect.
- Collect clarification questions about scope, affected callers, validation, and design rationale.
  Compare them with the description and context available at the time of review.
  If the earlier description is unavailable, record that limit.
  Do not infer an earlier omission from the current body.
- Paginate the PR list and every comment, review, and thread collection.
  Split searches that reach an API result cap.
  Filter individual events by the recorded window, allowing overlap at the start boundary.
  Include fixes without review comments from the period's merged PRs and commit history.
- Trace each candidate lesson to the final change and current source.
  Record the comment, fix, affected behavior, existing guidance, and any executable guard.
  Treat unmerged proposals and declined feedback as context, not established repository policy.
- Check recovered opening or pre-review revisions when commits were rewritten.
  A correction may be folded into the final PR's first commit without a separate review comment.
  Record unavailable earlier revisions as a coverage limit.
- Classify by content and outcome, not by author. Apply the same evidence standard to human and agent findings.
  Separate substantive findings and clarification questions from status updates, screenshots, suggested review focus, and replies without a new finding.
  Raw comment volume is not a defect count.
  Inspect later corrections before counting a finding as confirmed.
  Deduplicate reports of the same defect across review sources. Repeated mentions are not independent recurrences.
- Before classifying a missed rule, verify that the rule existed when the offending change was made.
  Use Git history for the relevant instruction and code.
  Distinguish a missing rule from a rule added after the defect.
- Mark missing pages, unavailable sources, and unverified outcomes explicitly.
  An incomplete collection cannot establish that no changes are needed.
  Do not advance the last complete audit's end time from a partial run.

Historical review does not authorize replies or resolution changes on old threads.

## Choose the smallest effective correction

Group evidence by failure mechanism, not by reviewer wording.
Prioritize repeated failures and individual failures with a clear, substantial consequence.
Use the current owner of each rule before adding a new instruction.
For each selected bug or anti-pattern, record its trigger, failure mechanism, final correction, and regression evidence or remaining gap.
Distinguish confirmed defects, accepted design corrections, declined suggestions, and unverified suspicions.
Do not turn a disputed review suggestion into repository policy.

| Finding | Correction |
|---------|------------|
| Missing guidance | Add the invariant to the deepest applicable `AGENTS.md`, or the procedure to its skill. Link its guard or source. |
| Existing guidance missed | Repair its discovery, placement, or relevant workflow step. Consolidate duplicate instructions. |
| Missing or ineffective guard | Prefer compiler constraints, lint, or regression tests for deterministic requirements. Verify that the guard rejects the observed failure. |
| Obsolete or conflicting guidance | Remove or correct it against current source and the final decision. |
| Recurring clarification caused by missing PR context | Add a conditional prompt to the relevant [PR body guidance](../github-workflow/SKILL.md#writing-the-pr-body). |
| No supported gap | Leave the guidance unchanged. Record why the evidence does not justify a change. |

Read the owning module instructions before changing guidance or a guard.
For architecture enforcement, use the existing [Bumper rules](../../../.bumper/RULES.md) and root mutation-test requirements.
For a new guard, cover the actual failing form and a valid neighboring form.
Check the guard's file selection, exclusions, configured severity, and CI invocation.
Retain the production configuration in regression probes so disabling the guard makes them fail.
Avoid broad text matching for rules that require type or runtime context.
If enforcement needs a separate product change, file it through `todo-triage` in the owning `TODOs.md`.
Search existing backlog items before filing another one.
Keep review history in the PR and actionable follow-ups in the backlog.
If a confirmed lesson lacks a useful review check, update [repository checks](../code-review/references/repository-checks.md).
Give the reviewer a recognizable trigger, a discriminating question or failure probe, and the owning rule and guard.
Merge lessons with the same mechanism. Extend the pattern index only when it improves discovery across modules.
Replace stale routes instead of accumulating historical examples. Keep the invariant at its existing owner and the fix history in the audit record.

Do not add instructions to meet a monthly quota.
Remove redundant guidance as part of the same correction.

## Verify and publish

Review whether earlier corrections prevented recurrence in later comparable changes.
Count a recurrence only after the relevant guidance or guard landed.
Separate new violations from defects already present at that time.
Report the number of relevant changes examined and any repeated defects or clarification gaps.
A quiet period without comparable changes does not establish effectiveness.

Validate the changed files through the root rules and applicable skills.
For skill changes, verify frontmatter, discovery descriptions, and local links.
Run `./sync-agents` after instruction changes.
If attribution inputs change, follow the root attribution procedure.
For guard changes, report the failing fixture and the passing corrected case.

If supported changes remain, publish a ready-for-review PR through `github-workflow`.
If no changes are warranted, leave tracked files unchanged and report the result.
Do not create a PR solely to record a completed run.

In the PR body or run summary, record:

- The UTC review window, source revision, and coverage status: complete or partial.
- The PR and comment counts, with any collection limits.
- The human and agent review sources examined, including unavailable private or ephemeral reports.
- Separate collection coverage from source verification. Name the changes examined for each selected lesson.
- Each selected lesson, its evidence links, its owner, and the correction or reason for no change.
- The effect of prior corrections, including limits on that conclusion.
- The checks run and links to deferred backlog items.

Use this record to establish the next review window.
If the user requests a monthly schedule, invoke `$review-lessons` from the task prompt.
Keep the audit procedure in this skill.
