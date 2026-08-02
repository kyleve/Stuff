---
name: github-workflow
description: Opens and maintains pull requests, handles review feedback, checks CI, and posts as the user via gh. Use when committing for push, opening or updating a PR, responding to review comments, or diagnosing CI failures.
---

GitHub workflow for this repo. Read root [`AGENTS.md`](../../../AGENTS.md) first for
always-on commit and test invariants — this skill assumes those.

## Prerequisites

- Use the `gh` CLI for all GitHub interaction — PRs, issues, checks, releases,
  review comments.
- **`./swiftformat --lint` and `./test` are part of "done".** Never push a red
  tree.
- **Never commit on `main`.** Branch first and keep every commit for one piece
  of work on that one branch.

## Branch and push

- **Multi-step work lands one commit per step**, so history stays bisectable and
  can land piecewise — including pure-groundwork steps, which say so in the body.
- **Commit when asked, or when working through a plan.** If it's unclear whether
  a commit is wanted, make the change and ask rather than committing silently.
- Push each commit as it lands once a PR is open.
- **A branch with no PR waits for the user before pushing.**

## Opening a PR

- **Open PRs ready-for-review, not draft.**
- Check for a PR template (`.github/PULL_REQUEST_TEMPLATE.md` or similar) and
  use it for the body.
- Describe the **end state**, not a changelog of the conversation.

## Keeping a PR current

- Push each commit as it lands.
- Refresh the title/body once the branch outgrows them — fold into any human
  edits rather than overwriting them.

## Review comments

- **Don't act on review comments the user hasn't pointed you at.** Summarize
  what's there and ask which to take on; reading them to write that summary is
  expected.
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

## When a failure isn't yours

**CI merges `main` into the branch before it runs**, so green-locally /
red-on-CI usually means `main` moved rather than that you broke something. Merge
the latest `main` in locally and rebuild before digging further — a renamed
module, a relocated test helper, or a changed shared signature shows up
immediately, and no amount of clearing DerivedData will surface it.
