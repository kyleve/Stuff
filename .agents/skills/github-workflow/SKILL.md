---
name: github-workflow
description: Create and maintain PRs and gh stack chains. Handle review feedback and diagnose GitHub Actions or CircleCI failures. Use for publishing changes, responding to reviews, and managing stacks.
---

Read the root [repository contract](../../../AGENTS.md) for branch, commit, push, PR-readiness, and test requirements.
Never push a known-red tree. Record skipped checks in the PR.

## Tools

| Job | Tool |
|-----|------|
| Read PRs, checks, comments, issues | `gh` |
| Download CircleCI failure artifacts | `./circleci-artifacts <job-uuid-or-url>` |
| Create or update a PR | `ManagePullRequest` when available; otherwise `gh pr create` / `gh pr edit` |
| Create, update, sync, or merge a PR stack | `gh stack` |
| Reply on a review thread | `ManagePullRequest` `post_comment` with `in_reply_to`, or `gh api` |
| Resolve a review thread | `ManagePullRequest` `resolve_comment` when asked |

Cloud agents: use `ManagePullRequest` for create/update/reply — not `gh pr
create` / `gh pr edit`. Local sessions can use `gh` throughout.

**Stacked PRs are the exception:** use `gh stack` in every environment for
stack topology and lifecycle. `ManagePullRequest` and `gh pr edit` can refine
an individual PR's title or body after submission. They must not manually wire
base branches or substitute for `gh stack`.

**Unsolicited top-level PR comments** (not review replies) still need an
explicit user request. **Review feedback is different:** when the user asks you
to address comments (`PTAL`, `address review`, `fix the feedback`), that
authorizes replies on the threads you fix, decline, or defer — see
[Review comments](references/review-replies.md#review-comments).

## Required operation references

Before an operation, read its matching reference.

| Operation | Required reference |
| --- | --- |
| Publish an ad hoc installable build | [Installable builds](references/installable-builds.md) |
| Write or update a PR description | [PR writing](references/pr-writing.md) |
| Post screen snapshots | [Screenshots](references/screenshots.md) |
| Create or maintain a PR stack | [Stacks](references/stacks.md) |
| Merge main or another branch | [Merging](references/merging.md) |
| Address review comments | [Review replies](references/review-replies.md) |
| Inspect CI checks or failures | [CI](references/ci.md) |

## Opening a PR

- Before handoff, open or update the PR for a finished feature branch with reviewable work.
  This also applies to work without formal plans.
- If the branch belongs to a stack, or the work needs dependent PRs, follow
  [Creating and maintaining stacked PRs](references/stacks.md#creating-and-maintaining-stacked-prs)
  instead of opening independent PRs.
- Start from [`.github/PULL_REQUEST_TEMPLATE.md`](../../../.github/PULL_REQUEST_TEMPLATE.md)
  and read [PR writing](references/pr-writing.md#writing-the-pr-body).
- For new or changed screens, add [screen snapshot comments](references/screenshots.md#screen-snapshot-comments) before handing over the PR.
- **Flag lines that warrant extra scrutiny.** Leave a PR review comment on
  anything worth a closer read (subtle behavior changes, incomplete migrations,
  assumptions about `main`).

### Review the completed diff

Before pushing reviewable work, review the complete branch diff against its PR base.
Use [code-review](../code-review/SKILL.md) for scope, contract tracing, guard coverage, and findings.
Include the material review result and remaining validation limits in the PR body.
Update owning guidance only for a missing invariant or obsolete instruction.
Keep each rule at its existing owner.

For behavior or contract changes, compare the description with the completed diff before publication and after material revisions.
First inventory the material changes from the diff without relying on the description.
Then check that the description covers each material change.
For each behavior or compatibility claim, locate evidence in the code and relevant validation.
Qualify claims that depend on source inspection or incomplete validation.

## Keeping a PR current

- After material revisions, include a brief update in [authorized review replies](references/review-replies.md#review-comments) or a requested status comment.
  Link the relevant commits or comparison.
  Identify changed decisions, assumptions that need another review, and repeated or pending validation.
  Keep the main body current with the final design and its rationale.

## Linear issue lifecycle

Use [BACKLOG.md](../../../BACKLOG.md) for issue evidence and closure rules.
Link affected STU issues in the PR description. Keep work In Review while its PR is open.
After merge, verify acceptance conditions before marking Done. Keep partial fixes open with the remainder documented.
Do not treat publishing a PR as completing its issue.

## Posting under the user's identity

Anything posted as the user — PR replies, issue comments, review responses —
opens with a line marking it AI-generated, e.g. `> _Posted by an AI agent on
$USER's behalf._`. No exception for short or purely factual comments.
