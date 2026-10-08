---
name: review-lessons
description: Audit PR comments and follow-up fixes to improve repository guidance and enforcement. Use for the monthly review retrospective or an explicit review of recurring mistakes.
---

Read the root [AGENTS.md](../../../AGENTS.md) and
[github-workflow](../github-workflow/SKILL.md) before changes.
Use this procedure monthly, or after a recurring failure needs investigation.
The weekly [todo-triage](../todo-triage/SKILL.md) pass owns backlog maintenance and module audits.

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
- Paginate the PR list and every comment, review, and thread collection.
  Split searches that reach an API result cap.
  Filter individual events by the recorded window, allowing overlap at the start boundary.
  Include fixes without review comments from the period's merged PRs and commit history.
- Trace each candidate lesson to the final change and current source.
  Record the comment, fix, affected behavior, existing guidance, and any executable guard.
  Treat unmerged proposals and declined feedback as context, not established repository policy.
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

| Finding | Correction |
|---------|------------|
| Missing guidance | Add the invariant to the deepest applicable `AGENTS.md`, or the procedure to its skill. Link its guard or source. |
| Existing guidance missed | Repair its discovery, placement, or relevant workflow step. Consolidate duplicate instructions. |
| Missing or ineffective guard | Prefer compiler constraints, lint, or regression tests for deterministic requirements. Verify that the guard rejects the observed failure. |
| Obsolete or conflicting guidance | Remove or correct it against current source and the final decision. |
| No supported gap | Leave the guidance unchanged. Record why the evidence does not justify a change. |

Read the owning module instructions before changing guidance or a guard.
For architecture enforcement, use the existing [Bumper rules](../../../.bumper/RULES.md) and root mutation-test requirements.
For a new guard, cover the actual failing form and a valid neighboring form.
Avoid broad text matching for rules that require type or runtime context.
If enforcement needs a separate product change, file it through `todo-triage` in the owning `TODOs.md`.
Search existing backlog items before filing another one.
Keep review history in the PR and actionable follow-ups in the backlog.

Do not add instructions to meet a monthly quota.
Remove redundant guidance as part of the same correction.

## Verify and publish

Review whether earlier corrections prevented recurrence in later comparable changes.
Count a recurrence only after the relevant guidance or guard landed.
Separate new violations from defects already present at that time.
Report the number of relevant changes examined and any repeated failures.
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
- Each selected lesson, its evidence links, its owner, and the correction or reason for no change.
- The effect of prior corrections, including limits on that conclusion.
- The checks run and links to deferred backlog items.

Use this record to establish the next review window.
If the user requests a monthly schedule, invoke `$review-lessons` from the task prompt.
Keep the audit procedure in this skill.
