---
name: todo-triage
description: Runs this repo's backlog pipeline — drain INBOX.md into the right TODOs.md, verify and expand entries against current source, archive completed items, and refresh MODULE_AUDIT.md as a derived report. Use when triaging the inbox, filing findings, running the weekly module audit, or asked to tidy the TODOs.
---

The backlog lives in `TODOs.md` files, one per area. This skill is the procedure
for putting things into them and keeping them honest.

Read the root [`TODOs.md`](../../../TODOs.md) first — it owns the item format and
the placement rule, and this skill assumes both. It is the contract; this file is
only the process.

**Never invent structure.** If a job here seems to need a new field, section, or
file, change the root `TODOs.md` and say so — don't improvise it into one area's
file.

## The weekly pass

The weekly automation runs the whole job in one go. The order matters: the
backlog is the source of truth, and the report is written from it, so the report
comes last.

1. **Drain `INBOX.md`** — see below.
2. **Re-verify the open backlog**, area file by area file. Close what shipped,
   correct line numbers that have moved, drop claims that are no longer true.
   This is the bulk of the work.
3. **Review the week's new surface** — the commits and merged PRs landed since
   the last audit's header date — and file what you find, tagged
   `(audit <date>)`.
4. **Rewrite `MODULE_AUDIT.md`** from what the backlog now says — see below.
5. **Update the docs the week invalidated**: a module's `README.md` /
   `AGENTS.md` when its architecture, public API, or a documented behavior
   changed; the root `AGENTS.md` when a global rule, a target, or the build/test
   flow did. Run `./sync-agents` afterwards if any `AGENTS.md` changed.
6. **Open a PR** ready-for-review — follow the
   [`github-workflow`](../github-workflow/SKILL.md) skill, describing the end
   state: what moved in the backlog, what the audit now says, and what you
   verified rather than assumed.

An ad-hoc run — someone asking you to triage the inbox or file a finding — is
just the relevant section below, not the whole pass.

## Draining the inbox

`INBOX.md` holds raw human notes: terse, uncited, unverified, sometimes already
fixed. Take each entry under `# Open` in turn.

1. **Understand what's being claimed.** An entry like "Raw data browser (similar
   to SD browser)" is a feature ask; "why do we delete all the DB entries on
   logout?" is a question that may or may not hide a bug. Resolve which before
   going further.
2. **Verify it against current source.** Find the code. Confirm the behavior is
   really what the note says, and that it hasn't already been fixed or already
   been filed. This is the step that earns the promotion — an entry that reaches
   a `TODOs.md` unverified is worse than one still sitting in the inbox, because
   it now reads as established.
3. **Expand it.** Write the body the root format asks for: the `File.swift:123`
   sites, why it matters (user-visible consequence, not just tidiness), and a
   concrete suggested fix. Preserve the human's intent — if the note asks a
   question you now know the answer to, answer it in the body rather than
   restating the question.
4. **Route it** by the placement rule: the lowest `TODOs.md` spanning every area
   it touches. Create that area's file if it doesn't exist yet (copy the header
   shape from a sibling; link to the root format, don't restate it).
5. **Bucket and tag it.** `PX`/`P0`/`P1`/`P2`, plus `quick-win` or
   `needs-design`. Tag the origin `(human <date the note was written>)` — keep
   the human's date, not today's; the point is to show where the item came from.
   A **new** item takes the bucket its severity implies (high → `P0`, medium →
   `P1`, low → `P2`); an item **already in the file keeps the bucket it has**.
   Priority is a decision someone made, and a severity opinion from a later pass
   doesn't get to silently overrule it — argue for the move in the body instead.
6. **Remove it from `INBOX.md`.** The origin tag is the trail; don't leave a
   copy behind.

An entry you don't file goes under `# Triaged` with a one-line verdict —
"already fixed by `abc1234`", "already filed as the `ReportLoadGate` P1 in
`Where/TODOs.md`", "declined: the store is intentionally reset on logout". Never
delete one silently. If a note is too vague to verify, leave it in `# Open` and
say what you'd need to know; guessing at intent is worse than waiting.

Agents **never add** to `INBOX.md`. Work you find yourself goes straight into the
right `TODOs.md`, fully formed.

## Filing a finding you found yourself

Same expansion and routing, tagged with where it came from — `(audit
2026-07-26)`, `(pr#107 review)`. Before filing, search every `TODOs.md` for the
symbol or file involved: the most common defect in this backlog is the same issue
filed twice in two files with different wording. If it exists, sharpen the
existing entry instead of adding a second one.

Deferred PR feedback is filed the same way, and the reply to that comment links
to where it landed.

## Closing an item

Move it to `# Completed issues` in the same file with a note on how it closed —
the PR or commit, and what actually shipped if it differs from what the item
proposed. Never delete it. A completed item whose fix was partial stays open with
the remainder described, rather than being closed optimistically.

## Refreshing MODULE_AUDIT.md

`MODULE_AUDIT.md` is **derived and carries no actionable items**. Every finding
belongs in a `TODOs.md`; the audit reports on shape and drift. Regenerating it:

1. **Re-verify the open backlog** against current source, area file by area file.
   Close what has shipped, correct line numbers that have moved, and delete
   claims that are no longer true. This is the bulk of the work, and it happens
   in the `TODOs.md` files, not in the audit.
2. **File the new findings** from this pass, per the section above.
3. **Then write the report**, from what the backlog now says:
   - the source/test file inventory per module, and whether each has its
     `README.md` and `AGENTS.md`
   - **Verified OK** per module — what you checked that was clean. This is the
     audit's unique value: negative space has no home in a backlog.
   - cross-cutting themes — the synthesis across items that no single item shows
   - the top findings, as **pointers** into the `TODOs.md` files (title and where
     it's filed), never restated bodies
   - what changed since the previous audit, and the limitations of this pass
4. **Stamp the header date** and keep the prior date for the diff. The audit is
   true as of its header, not as of `HEAD`, and it says so.

If you catch yourself writing a findings table with a suggested fix in it, that
content belongs in a `TODOs.md`.

## Environment

The weekly automation runs on Linux, where Tuist and the simulator are
unavailable, so the audit pass is static analysis only — say so in its
Limitations section rather than implying the suite was run. `./swiftformat
--lint` and `./sync-agents` do work there.
