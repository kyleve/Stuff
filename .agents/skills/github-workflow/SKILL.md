---
name: github-workflow
description: Opens and maintains pull requests, handles review feedback, checks CI, and posts as the user via gh. Use when committing for push, opening or updating a PR, responding to review comments, or diagnosing CI failures.
---

GitHub workflow for this repo. Read root [`AGENTS.md`](../../../AGENTS.md) first for
always-on commit and test invariants — this skill assumes those.

## Prerequisites

- Use the `gh` CLI for all GitHub interaction — PRs, issues, checks, releases,
  review comments.
- Validate in proportion to risk. Pure documentation or comment-only changes
  may skip checks that cannot exercise them; record skipped checks in the PR.
  Never push a known-red tree.
- **Never commit on `main`.** Branch first and keep every commit for one piece
  of work on that one branch.

## Branch and push

- **Multi-step work lands one commit per step**, so history stays bisectable and
  can land piecewise — including pure-groundwork steps, which say so in the body.
- **Commit completed work eagerly.** Once a coherent change is verified, commit
  it unless the user explicitly asks to keep it uncommitted.
- Push each commit as it lands once a PR is open.
- **When working through a plan, open a PR once the plan is complete** — push
  the branch and open it ready-for-review rather than leaving finished work
  local-only.

## Opening a PR

- **Open PRs ready-for-review, not draft.**
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

- **Title:** imperative, describes the merged end state (reads well as
  `Title (#NNN)` on `main`).
- **End state, not a changelog:** describe what the repo looks like after merge,
  not commit-by-commit or chat-by-chat progress.
- **Explain what the diff doesn't show** — motivation, rejected alternatives,
  trade-offs, follow-ups that aren't obvious from the code alone.

#### Pick a tier

| Tier | When | Keep | Add when warranted |
|------|------|------|--------------------|
| Small | Obvious fix, 1–2 modules, no design choices | Summary, Testing | — |
| Medium | Behavior change, new UI slice, docs/skill extraction | Summary, Why, Review focus, Testing | Skip rationale for doc-only work |
| Large | Architecture, multi-module migration, new protocol | Summary or Problem + Changes, Why, Design decisions, Review focus, Testing | Product behavior, Architecture, Rollout / follow-ups, Stack; situational sections (prototype round, backlog reconciliation) |

#### Section semantics

- **Summary** — end-state bullets (add/keep/preserve/migrate/remove); not a
  commit log.
- **Why / Problem** — what was wrong or missing before; link prior PRs when
  building on them.
- **Changes / Architecture / Product behavior** — deep walkthrough for large
  PRs; group by subsystem with bold labels.
- **Design decisions / Trade-offs** — explicit choices and what was rejected.
- **Review focus** — subtle behavior, incomplete migrations, assumptions about
  `main`; prefer inline review comments for specific lines.
- **Testing** — exact commands with pass counts; for skipped checks, state
  **what** and **why**.

#### Exemplars

Read merged PRs for shape, not to copy wholesale:

- Large refactor: #116, #150
- Large feature: #160
- Medium with review notes: #196, #206
- Docs-only with skip rationale: #167, #145

#### Template hygiene

- Populate every section you keep; **delete unused section headers** and stub
  bullets before opening or updating the PR — empty headers pollute the squash
  commit body.
- Refresh the title/body once the branch outgrows them; fold into any human
  edits rather than overwriting them.

## Keeping a PR current

- Push each commit as it lands.

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

- **Don't act on review comments the user hasn't pointed you at.** Summarize
  what's there and ask which to take on; reading them to write that summary is
  expected.
- **One commit per review issue** — each distinct piece of feedback gets its
  own commit, unless several items fit together logically or address similar
  issues (then one commit for the group is fine). Either way, fixes stay
  bisectable and the reply can name the commit that resolved it.
- When a commit resolves one, reply to it naming the commit.
- Anything deliberately not addressed gets filed in the area's
  [`TODOs.md`](../../../TODOs.md) — never dropped.

## CI

- **Don't block the conversation polling CI.** Report what's running and hand
  the turn back; delegate a genuine watch to a background subagent.

## Posting under the user's identity

Anything posted as the user — PR replies, issue comments, review responses —
opens with a line marking it AI-generated, e.g. `> _Posted by an AI agent on
$USER's behalf._`. No exception for short or purely factual comments.
