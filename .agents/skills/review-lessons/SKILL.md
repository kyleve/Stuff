---
name: review-lessons
description: Audit historical human and agent review findings to improve repository guidance and enforcement.
---

# Review lessons

Use [code-review](../code-review/SKILL.md) for a current diff, [todo-triage](../todo-triage/SKILL.md) for backlog/module audits, and [github-workflow](../github-workflow/SKILL.md) for publication.
Historical audits do not authorize replies or resolution changes on old threads.

## Window and sources

- Use the selected base, otherwise a clean branch from current `origin/main`. Continue an unfinished matching audit PR.
- Fix a UTC end time before collection. Start at the last complete audit's recorded end, or three months earlier when no record exists.
- Use three months of overlapping context for recurrence analysis; do not count it again as new evidence.
- Collect PRs updated in the window, including older, closed, and open PRs: inline/resolved threads, submitted reviews, conversation comments, and later corrections.
- Include available agent-review reports and findings fixed before publication. Search Linear history and dated `MODULE_AUDIT.md` reports under [BACKLOG.md](../../../BACKLOG.md). Also inspect merged fixes without review comments.
- Paginate each collection, split capped searches, and filter individual events by the window. Record inaccessible reports and missing pages. Partial runs must not advance the last complete audit boundary.

## Establish lessons

For each candidate, trace the report to its final disposition, fix, current source, owning guidance, and guard.
Recover pre-review revisions when needed after rewrites; report unavailable history.
For clarification gaps, compare the question with the description available at that time, not today's edited body.
Check whether a supposedly missed rule existed when the defect was introduced.

Deduplicate by defect across human and agent reports.
Distinguish confirmed defects, accepted design decisions, declined suggestions, and unverified claims.
Prioritize recurring mechanisms and single failures with substantial consequences.

## Correct the owner

| Evidence | Action |
| --- | --- |
| Missing non-obvious contract | Add it to the deepest applicable instructions or workflow skill, with its guard/source. |
| Existing rule missed | Repair discovery or consolidate duplicate owners. |
| Missing or ineffective deterministic guard | Prefer compiler/lint/test enforcement. Follow code-review's guard checks and the [Bumper catalog](../../../.bumper/RULES.md) where applicable. |
| Obsolete or generic guidance | Correct or remove it; do not preserve wording that adds no decision value. |
| Repeated PR-context gap | Refine the relevant [PR-writing guidance](../github-workflow/references/pr-writing.md). |
| No supported gap | Leave guidance unchanged. |

Use the current owner's instructions before editing.
For a confirmed mechanism that lacks a useful review probe, update [repository checks](../code-review/references/repository-checks.md) with a trigger, discriminating probe, and owner/guard links.
Keep fix history in the audit record. Replace stale examples instead of accumulating them.
File separate product work through todo-triage, with duplicate/history checks.

## Verify and publish

Assess prior corrections only against comparable changes after they landed; a quiet period alone does not prove effectiveness.
Report comparable-change counts and any recurrences.

Run guidance synchronization/checks, validate changed skills, and exercise changed executable guards.
Publish supported corrections through github-workflow; leave the PR open.
No-change runs need no commit or PR. Do not add instructions to fill an audit quota.

Keep this record in the PR or response:

- UTC window, source revision, and complete/partial coverage.
- Collection counts, human/agent sources, and inaccessible evidence.
- Verified changes and each selected lesson's trigger, mechanism, outcome, owner, and correction or reason for no change.
- Prior corrections' observed effects and limits.
- Checks and deferred issue links.

Schedules invoke `$review-lessons`; cadence belongs in the scheduler.
