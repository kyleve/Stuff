---
name: github-workflow
description: Opens and maintains pull requests, handles review feedback, checks CI, and posts as the user via gh or ManagePullRequest. Use when committing for push, opening or updating a PR after plan execution, responding to review comments, or diagnosing CI failures.
---

GitHub workflow for this repo. Read root [`AGENTS.md`](../../../AGENTS.md) first for
always-on commit and test invariants — this skill assumes those.

## Prerequisites

- **Never commit on `main`.** Branch first and keep every commit for one piece
  of work on that one branch.
- Validate in proportion to risk. Pure documentation or comment-only changes
  may skip checks that cannot exercise them; record skipped checks in the PR.
  Never push a known-red tree.

## Tools

| Job | Tool |
|-----|------|
| Read PRs, checks, comments, issues | `gh` |
| Create or update a PR | `ManagePullRequest` when available; otherwise `gh pr create` / `gh pr edit` |
| Reply on a review thread | `ManagePullRequest` `post_comment` with `in_reply_to`, or `gh api` |
| Resolve a review thread | `ManagePullRequest` `resolve_comment` when asked |

Cloud agents: use `ManagePullRequest` for create/update/reply — not `gh pr
create` / `gh pr edit`. Local sessions may use `gh` throughout.

**Unsolicited top-level PR comments** (not review replies) still need an
explicit user request. **Review feedback is different:** when the user asks you
to address comments (`PTAL`, `address review`, `fix the feedback`), that
authorizes replies on the threads you fix, decline, or defer — see
[Review comments](#review-comments).

## Branch, push, and plan handoff

- **Multi-step work lands one commit per step**, so history stays bisectable and
  can land piecewise — including pure-groundwork steps, which say so in the body.
- **Commit completed work eagerly.** Once a coherent change is verified, commit
  it unless the user explicitly asks to keep it uncommitted.
- **Push the branch as commits land** — do not accumulate unpushed work or wait
  for the user to ask.
- **Plan-driven work finishes with a PR.** After executing an approved plan (all
  steps verified), push the branch and **open a ready-for-review PR** before
  handing back — or update the existing PR if one is already open. Never leave
  finished plan work local-only, unpushed, or without a PR the user can review.
- **Any finished task on a feature branch** follows the same push habit; open or
  update the PR when the branch carries reviewable work, not only after formal
  plans.

## Opening a PR

- **Open PRs ready-for-review, not draft.**
- **Default after plan execution:** if the branch has no PR yet, open one before
  handing back; if a PR exists, push and refresh the body when the work outgrew
  it.
- Start from [`.github/PULL_REQUEST_TEMPLATE.md`](../../../.github/PULL_REQUEST_TEMPLATE.md)
  and follow [Writing the PR body](#writing-the-pr-body) below.
- **Flag lines that warrant extra scrutiny** — leave a PR review comment on
  anything a reviewer should look at closely (subtle behavior changes,
  incomplete migrations, assumptions about `main`).

### Writing the PR body

Squash merges on `main` use **PR title → commit subject** and **PR body → commit
body** — the body is what `git show` reads months later. Write for someone
bisecting or reconstructing *why*, not for the conversation that produced the
branch.

- **Title:** prefer `type(scope): imperative description` when it fits — the squash
  commit subject on `main`. Use the same **types** and **scopes** as
  [`TODOs.md`](../../../TODOs.md) (`feat`, `fix`, `refactor`, `docs`, …;
  `WhereUI`, `WhereCore`, `Periscope`, …). Prose titles are fine for
  cross-cutting work that doesn't have one scope (`Add demo mode…`). Branch
  commits stay bisectable narrative; only the PR title needs this shape.
- **End state, not a changelog:** describe what the repo looks like after merge,
  not commit-by-commit or chat-by-chat progress.
- **Explain what the diff doesn't show** — motivation, rejected alternatives,
  trade-offs, follow-ups that aren't obvious from the code alone.

#### Pick a tier

| Tier | When | Keep | Add when warranted |
|------|------|------|--------------------|
| Small | Obvious fix, 1–2 modules, no design choices | Summary, Testing | — |
| Medium | Behavior change, new UI slice, docs/skill extraction | Summary, Why, Review focus, Testing | User-facing / Internal split in Summary when mixed; skip rationale for doc-only work |
| Large | Architecture, multi-module migration, new protocol | Summary or Problem + Changes, Why, Design decisions, Review focus, Testing | Product behavior, Architecture, ⚠️ Breaking changes, Compatibility, Rollout / follow-ups, Stack; situational sections (prototype round, backlog reconciliation) |

#### Section semantics

- **Summary** — end-state bullets (add/keep/preserve/migrate/remove); not a
  commit log. When a PR mixes user-visible and internal work, prefix bullets
  with **User-facing:** or **Internal:** so `git log` readers can scan quickly.
- **Why / Problem** — what was wrong or missing before; link prior PRs when
  building on them.
- **Changes / Architecture / Product behavior** — deep walkthrough for large
  PRs; group by subsystem with bold labels.
- **Design decisions / Trade-offs** — explicit choices and what was rejected.
- **⚠️ Breaking changes** — wire-format, persistence, backup, CloudKit schema,
  or API breaks; what existing data/installs lose or must do. Delete the section
  when there are none.
- **Compatibility** — how old data, backups, or parallel installs behave through
  the change; required upgrade order. Delete when N/A.
- **Review focus** — subtle behavior, incomplete migrations, assumptions about
  `main`; prefer inline review comments for specific lines.
- **Testing** — exact commands with pass counts; for skipped checks, state
  **what** and **why**.

#### Common PR shapes

Use the tier table above. **Do not open merged PRs for examples** unless a
shape below is genuinely unclear.

##### Small fix

- **Summary:** 2–4 end-state bullets.
- **Testing:** commands run + pass counts.
- Drop **Why** and **Review focus** unless something subtle needs calling out.

##### Feature or behavior change

- **Summary**, **Why**, **Review focus**, **Testing**.
- **Summary:** prefix **User-facing:** / **Internal:** when the PR ships both.
- **Why:** user-visible problem or gap; link a prior PR when building on one.
- **Review focus:** edge cases, incomplete migrations, assumptions about `main`.

##### Large feature

- Everything in *Feature or behavior change*, plus **Product behavior** and/or
  **Architecture**.
- **Product behavior:** what the user sees — onboarding, settings, failure
  modes, edge cases.
- **Architecture:** key types, invariants, ownership; group by subsystem with
  bold labels.
- **⚠️ Breaking changes** and **Compatibility** when persistence, backups,
  CloudKit, or wire formats are involved.
- **Rollout / follow-ups** when ship order or a follow-on PR matters.

##### Refactor or migration

- **Problem** (or **Summary**), **Changes**, **Design decisions**, **Review
  focus**, **Testing**.
- **Changes:** deep walkthrough — what moved, what was deleted, what the
  compiler now enforces.
- **Design decisions:** explicit choices and rejected alternatives.
- **⚠️ Breaking changes** / **Compatibility** when stored shapes or backup
  restore behavior changes.
- **Backlog reconciliation** when the branch touched `TODOs.md` or
  `MODULE_AUDIT.md`.

##### Docs, skills, or repo tooling

- **Summary**, **Why** (if non-obvious), **Testing** / **Verification**.
- State skipped checks explicitly (`./test` not run because Markdown-only).
- **Review focus** only when the boundary between moved and retained guidance
  matters.

##### Stacked PR

- **Summary**, **Testing**, **Stack** (position, base-PR link, what this slice
  adds).
- Do not repeat the full feature write-up — point at the stack head for that.

#### Template hygiene

- Populate every section you keep; **delete unused section headers** and stub
  bullets before opening or updating the PR — empty headers pollute the squash
  commit body.
- Refresh the title/body once the branch outgrows them; fold into any human
  edits rather than overwriting them.

## Keeping a PR current

- Push each commit as it lands.

## Maintaining stacked PRs

Treat a stack as one dependency chain even when the requested PR is near its
base: a conflict or failing integration in one slice can block every PR above
it.

- Start by inspecting the whole graph with `gh stack view --short`, then read
  every PR's base, head SHA, mergeability, merge-state status, and checks. Find
  the first broken slice; do not assume the PR the user noticed owns the fault.
- Rebase from that first affected branch through the stack with `gh stack
  rebase --no-trunk --upstack`. This rewrites upstack branches, so obtain user
  authorization before doing it unless their request already explicitly covers
  repairing or updating the full stack.
- Resolve conflicts on the slice that introduced the affected code. Preserve
  both downstack fixes and the slice's intended addition; do not accept one
  side wholesale merely to finish the rebase. Re-record snapshot references
  when both sides contain intentional visual changes.
- After each slice rebases, search it for logical conflicts such as references
  to renamed stylesheet tokens or APIs. Put the compatibility fix and its tests
  on the earliest slice that owns the affected code, commit it there, then
  continue rebasing the remaining upstack branches. Do not bury fixes for a
  lower PR in the stack head.
- Validate focused behavior while repairing individual slices, then run the
  complete affected test and lint set at the stack tip. The tip contains every
  slice and is the final integration proof.
- Push the complete rewritten chain with `gh stack push`, then re-read every PR
  and verify its base branch, remote head SHA, and `mergeable` value. Return the
  checkout to the branch the user was reviewing when practical.

GitHub commonly reports an otherwise mergeable upstack PR as `BLOCKED` while
its parent PR or required checks are pending. Distinguish that expected
downstack dependency from `CONFLICTING` / `DIRTY`, failed checks, or an
unexpected base before reporting the repair complete. Cancelled superseded
workflow runs immediately after a stacked force-push are also expected; assess
the newest run for each head SHA.

## Merging main and other branches

When bringing `main` or another branch into yours — because CI failed, before
a long review, or to pick up a dependency:

- **Resolve git-reported conflicts** — the `<<<<` / `>>>>` markers; don't leave
  conflict markers or half-resolved hunks.
- **Check for logical conflicts too** — changes on both sides can compose cleanly
  in git but still clash in behavior: a renamed symbol your branch still
  references, a relocated test helper, an updated signature your call sites don't
  match, a new invariant your code violates, duplicate registrations. Re-read
  the merged result and run `./test` (at least the affected tier) after merging
  — a clean merge is not proof the branch still makes sense.
- **CI merges `main` into the branch before it runs**, so green-locally /
  red-on-CI usually means `main` moved rather than that you broke something.
  Merge the latest `main` in locally and rebuild before digging further.

## Review comments

Two modes — don't mix them up:

**Exploring (user has not asked you to act):** read open review threads, summarize
what's there, and ask which to take on. Do not change code or post replies yet.

**Addressing (user pointed you at comments — e.g. "PTAL", "address review",
"fix the feedback"):** for each comment you fix in code, **also reply on GitHub**
in that thread. A code change without a reply is an incomplete handoff — the
reviewer cannot tell their note was seen.

When addressing:

- **One commit per review issue** — each distinct piece of feedback gets its
  own commit, unless several items fit together logically or address similar
  issues (then one commit for the group is fine). Either way, fixes stay
  bisectable.
- **Reply on every thread you fixed** — after pushing, reply naming the commit
  that resolved it (short summary of what changed). Use `gh` or
  `ManagePullRequest` `post_comment` with `in_reply_to` for review threads.
- **Reply on threads you declined** — say why, or that it was filed in the
  area's [`TODOs.md`](../../../TODOs.md). Never drop feedback silently.
- Anything deliberately deferred gets filed in `TODOs.md` and the reply links
  to that item.

## CI

- **Don't block the conversation polling CI.** Report what's running and hand
  the turn back; delegate a genuine watch to a background subagent.

## Posting under the user's identity

Anything posted as the user — PR replies, issue comments, review responses —
opens with a line marking it AI-generated, e.g. `> _Posted by an AI agent on
$USER's behalf._`. No exception for short or purely factual comments.
