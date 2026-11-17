---
name: github-workflow
description: Publish and maintain Stuff PRs and stacks, address review feedback, or diagnose CI.
---

# GitHub workflow

The root [repository contract](../../../AGENTS.md) owns branch, commit, push, readiness, and authorization defaults.

## Tools

| Operation | Tool |
| --- | --- |
| Read PRs, checks, comments, issues | `gh` |
| Download CircleCI failure artifacts | `./circleci-artifacts <job-uuid-or-url>` |
| Create/update PRs | `ManagePullRequest` when available; local sessions may use `gh pr create/edit` |
| Stack topology and lifecycle | `gh stack` in every environment |
| Reply in review threads | `ManagePullRequest post_comment` with `in_reply_to`, or `gh api` |
| Resolve review threads | `ManagePullRequest resolve_comment` when asked |

Cloud sessions use ManagePullRequest for create/update/reply.
Individual title/body edits may follow stack submission; do not wire stack bases manually.

## Required operation references

| Operation | Read |
| --- | --- |
| Publish an ad hoc build | [Installable builds](references/installable-builds.md) |
| Write/update a PR body | [PR writing](references/pr-writing.md) |
| Post screen snapshots | [Screenshots](references/screenshots.md) |
| Manage a stack | [Stacks](references/stacks.md) |
| Merge main or another branch | [Merging](references/merging.md) |
| Address review comments | [Review replies](references/review-replies.md) |
| Inspect CI | [CI](references/ci.md) |

## Opening a PR

Review the complete diff against its PR base through [code-review](../code-review/SKILL.md).
Follow the root publication defaults.
Use the [PR template](../../../.github/PULL_REQUEST_TEMPLATE.md) and operation-specific references above.
For changed screens, add screen snapshot comments.
Put material review findings and validation limits in the body; flag subtle lines with review comments.

Compare behavior/compatibility claims with the final diff and evidence before publication and after material revisions.
Preserve human edits while keeping the description current.

## Keeping a PR current

Requests to address feedback authorize replies on the threads fixed, declined, or deferred.
Unsolicited top-level PR comments still need an explicit request.
After material revisions, use authorized replies or a requested status comment to identify commits, changed decisions, and repeated/pending validation.

## Linear issue lifecycle

[BACKLOG.md](../../../BACKLOG.md) owns evidence and closure.
Link affected STU issues; open PRs keep work In Review.
After merge, verify acceptance before marking Done. Keep partial fixes open.

## Posting under the user's identity

Mark posts, including PR descriptions and short replies, with:
`> _Posted by an AI agent on the repository owner's behalf._`
