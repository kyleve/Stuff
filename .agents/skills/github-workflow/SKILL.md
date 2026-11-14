---
name: github-workflow
description: Create and maintain PRs and gh stack chains. Handle review feedback and diagnose GitHub Actions or CircleCI failures. Use for publishing changes, responding to reviews, and managing stacks.
---

GitHub workflow for this repo. Read root [`AGENTS.md`](../../../AGENTS.md) first for
always-on commit and test invariants. This skill assumes those.

## Prerequisites

- **Never commit on `main`.** Branch first and keep every commit for one piece
  of work on that one branch.
- Run checks in proportion to risk. Pure documentation or comment-only changes
  can skip checks that cannot exercise them. Record skipped checks in the PR.
  Never push a known-red tree.

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

## Branch, push, and plan handoff

- **Multi-step work lands one commit per step**, so history stays bisectable and
  can land piecewise — including pure-groundwork steps, which say so in the body.
- **Commit completed work eagerly.** Once a coherent change is verified, commit
  it unless the user explicitly asks to keep it uncommitted.
- **Push the branch as commits land.** Do not accumulate unpushed work or wait
  for the user to ask.
- **Plan-driven work finishes with a PR.** After executing an approved plan (all
  steps verified), push the branch and **open a ready-for-review PR** before
  handing back — or update the existing PR if one is already open. Never leave
  finished plan work local-only, unpushed, or without a PR the user can review.
- **Any finished task on a feature branch** follows the same push habit. Open or
  update the PR when the branch carries reviewable work, not only after formal
  plans.

## Ad hoc installable builds

For this operation, read [the installable builds procedure](references/installable-builds.md).

## Opening a PR

- **Open PRs ready-for-review, not draft.**
- If the branch belongs to a stack, or the work needs dependent PRs, follow
  [Creating and maintaining stacked PRs](references/stacks.md#creating-and-maintaining-stacked-prs)
  instead of opening independent PRs.
- **Default after plan execution:** if the branch has no PR yet, open one before
  handing back. If a PR exists, push and refresh the body when the work outgrew
  it.
- Start from [`.github/PULL_REQUEST_TEMPLATE.md`](../../../.github/PULL_REQUEST_TEMPLATE.md)
  and follow [Writing the PR body](references/pr-writing.md#writing-the-pr-body) below.
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

### Writing the PR body

Before writing or updating a PR description, read [PR writing](references/pr-writing.md).

## Keeping a PR current

- Push each commit as it lands.
- After material revisions, include a brief update in [authorized review replies](references/review-replies.md#review-comments) or a requested status comment.
  Link the relevant commits or comparison.
  Identify changed decisions, assumptions that need another review, and repeated or pending validation.
  Keep the main body current with the final design and its rationale.

## Screen snapshot comments

For this operation, read [the screenshots procedure](references/screenshots.md).

## Creating and maintaining stacked PRs

For this operation, read [the stacks procedure](references/stacks.md).

## Merging main and other branches

For this operation, read [the merging procedure](references/merging.md).

## Review comments

For this operation, read [the review replies procedure](references/review-replies.md).

## Linear issue lifecycle

Use [BACKLOG.md](../../../BACKLOG.md) for issue evidence and closure rules.
Link affected STU issues in the PR description. Keep work In Review while its PR is open.
After merge, verify acceptance conditions before marking Done. Keep partial fixes open with the remainder documented.
Do not treat publishing a PR as completing its issue.

## CI

For this operation, read [the ci procedure](references/ci.md).

## Posting under the user's identity

Anything posted as the user — PR replies, issue comments, review responses —
opens with a line marking it AI-generated, e.g. `> _Posted by an AI agent on
$USER's behalf._`. No exception for short or purely factual comments.
