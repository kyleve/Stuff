---
name: code-review
description: Review Stuff PRs, branches, or local diffs, including the completed-diff review before publication.
---

# Code review

[github-workflow](../github-workflow/SKILL.md) owns publication and replies.
Review-only requests do not authorize product edits, posting, or merging.
Implementation tasks include correcting supported findings within their scope.

## Scope and evidence

- Record base/head revisions and uncommitted changes. A stack slice uses its parent as the base.
- Review the complete diff and affected callers against the request and applicable module contracts. Report any unreviewed scope.
- For changed contracts, identify the owning rule and actual guard or coverage gap. Use relevant sections of [repository checks](references/repository-checks.md) for known failure mechanisms.
- Inspect fix history when a change touches a guarded regression or the current contract leaves a consequential decision unclear. Current instructions own policy; historical fixes supply counterexamples.
- Use [running-tests](../running-tests/SKILL.md) for changed inputs. For guard changes, verify the actual failing form, diagnostic, valid exception, file selection, and CI invocation. A test name or an installed linter does not establish coverage.
- Keep snapshot, runtime, and physical-device evidence distinct.

## Independent review

For implementation work that changes behavior or contracts, run one fresh subagent review before publication or handoff when available.
Mechanical and documentation-only changes do not require a separate agent by default.
Supply the request, scope, revisions, governing instructions, and raw artifacts before offering the author's conclusions.
For broad work, assign coherent slices and identify who reviews their shared boundaries.
Report unavailable independent review as a validation limit.

## Findings and handoff

Report actionable findings by severity with file/line, trigger, consequence, and supporting evidence.
Distinguish introduced defects, pre-existing issues, design preferences, and missing validation.
After fixes or a material base change, review the resulting diff and affected consumers; rerun only checks whose evidence changed.

Include reviewed revisions, coverage, checks, and limits in the response or PR's Review focus/Testing sections.
Retain confirmed findings fixed during the review. For reusable lessons, record trigger, mechanism, correction/commit, and regression evidence or remaining gap in that existing summary.
During authorized publication, retain those lessons in the PR description or authorized reply for [review-lessons](../review-lessons/SKILL.md).
A review record does not authorize another post or sharing private chat.
File deferred work through [todo-triage](../todo-triage/SKILL.md) and link the issue.
