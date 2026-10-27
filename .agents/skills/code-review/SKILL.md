---
name: code-review
description: Review Stuff PRs, branches, or local diffs using module contracts, existing regression tests, and relevant fix history. Use for requested reviews and the completed-diff review before publication. Use review-lessons for historical audits.
---

# Code review

Read the root [AGENTS.md](../../../AGENTS.md) and the instructions for each affected path.
Keep the review proportional to the changed behavior and its consequences.
This skill owns review procedure. [github-workflow](../github-workflow/SKILL.md) owns publication, stacks, and replies.
A review request alone does not authorize product edits, posting, or merging.
For an implementation task, use this procedure to review the completed work and correct supported findings within scope.

## Fix the review scope

1. Record the base and head commit IDs, plus any uncommitted changes under review.
   For a stacked PR, use its parent as the diff base.
   Identify inherited changes separately from this slice's changes.
2. Read the complete diff and surrounding implementation before relying on the PR description or an author's conclusions.
   Inventory changed contracts, callers, stored data, execution paths, and tests.
   Then compare the inventory with the request and description.
3. Build the repository-specific contract map below before evaluating the implementation.
   Include affected consumers outside the changed module.

If a review is too broad for complete inspection, identify the unreviewed areas explicitly.
Request a smaller coherent slice or report partial coverage. Do not infer correctness from sampling.
Separate mechanical changes from behavior changes when that separation makes the review verifiable.

## Find the concrete repository contracts

Select the applicable routes from [repository checks](references/repository-checks.md).
Scan its [failure-pattern index](references/repository-checks.md#failure-pattern-index) for mechanisms that can recur across modules.
Read those sections and their owning instructions, including source-directory `AGENTS.md` files.
These routes point to known failure mechanisms and current guards. They are not an exhaustive rule catalog.

| Changed code | Review route |
| --- | --- |
| Swift signatures, stored state, or preferences | [Domain types and state](references/repository-checks.md#domain-types-and-state) |
| Launch, reset, services, intents, or store writes | [Composition and transactions](references/repository-checks.md#composition-and-transactions) |
| Heuristics, sensor evidence, or correction eligibility | [Inference and thresholds](references/repository-checks.md#inference-and-thresholds) |
| Day keys, calendars, historical reads, or backups | [Dates and persisted data](references/repository-checks.md#dates-and-persisted-data) |
| Views, models, layout, or styling | [UI structure and Broadway](references/repository-checks.md#ui-structure-and-broadway), plus [building-ui](../building-ui/SKILL.md) |
| Package products, targets, imports, or architecture rules | [Target graph and guards](references/repository-checks.md#target-graph-and-guards) |
| Snapshots, previews, or capture infrastructure | [Rendering and fixtures](references/repository-checks.md#rendering-and-fixtures) |
| Events, errors, reporting, or export | [Classified logging](references/repository-checks.md#classified-logging) |
| Root commands, files, processes, signing, or publication | [Tools and publication](references/repository-checks.md#tools-and-publication) |

For each material changed contract, record the owning rule, affected implementation/caller, and relevant regression test or enforcement gap.
Open the cited test and check what it asserts. A matching test name is not evidence of coverage.
Use the owning module's instructions and README for areas outside these routes.

For behavior changes, inspect relevant fix history for the affected implementation and guard with `git log --oneline -- <paths>` and `git show <commit>`.
Follow a linked PR through github-workflow when the reason or final decision remains unclear.
Check the original failure trigger against the new diff, including alternate callers.
Treat the current owner as authoritative. An old fix is a counterexample to consider, not a rule to copy into every module.

## Establish what the checks cover

Use [running-tests](../running-tests/SKILL.md) to select checks for the actual changed inputs.
Read both CI configurations when the change affects build or test behavior.
Locate lint commands and configuration in the reviewed revision before claiming coverage.
An unmerged guard on another branch does not protect this revision.

- Check file selection, exclusions, parser/type information, suppressions, and CI invocation for each relevant lint rule.
  A passing rule outside the affected files provides no evidence about those files.
- For a new or changed guard, exercise the observed failing form and a valid neighboring form.
  Assert the intended diagnostic, not merely a nonzero exit.
  Preserve the real configuration so disabling the rule makes its regression fail.
  Check documented exceptions with passing fixtures.
- For test changes, identify the behavior each retained test can distinguish.
  Check that the assertion fails for the defect, not only that the corrected code passes.
  Prefer focused boundary tests over large harnesses that mirror implementation details.
- Match results to the tested revision, toolchain, selected suites, and executed counts.
  A build, empty selection, skipped check, or formatter pass does not establish behavior coverage.
  Keep snapshot rendering, runtime interaction, and device verification as separate claims.

Do not add brittle text rules for contracts that need type or runtime knowledge.
Keep known gaps visible in the owning rule catalog or backlog.

## Trace behavior across boundaries

Start with the highest-consequence changed path. Follow its input through the final state and observable side effects.
Inspect callers and sibling implementations outside the diff when they depend on that contract.
For each important path, identify a concrete scenario that can falsify the claimed behavior.

For cross-language data, inspect the real serialized boundary or a shared wire fixture with both consumers.
For async work, trace ownership across suspension, cancellation, retry, and teardown through production callers.
For race tests, hold the dependency at the relevant suspension and inspect superseded completion.
For heuristics, inspect plausible counterexamples and threshold boundaries, not only the examples that motivated the change.

Compare a new abstraction with the existing owner before accepting another pipeline, registry, parser, or state machine.
Identify the concrete requirement that prevents reuse. Prefer extending an existing seam when it preserves that contract.
Do not remove a requirement merely to simplify its implementation.

## Verify findings

- State the trigger, affected behavior, and consequence for each finding.
  Support it with a reproduction, focused test, or an explicit source path through the failure.
- Check later comments, caller guarantees, and intentional compatibility decisions before reporting a suspected defect.
  Distinguish introduced regressions from pre-existing problems and optional improvements.
- Review the proposed fix at sibling callers and the public boundary.
  Confirm that its test uses the failing production form and preserves the valid case.
- Keep correctness findings separate from design preferences and missing validation.
  Do not invent findings or request speculative refactors to fill a review quota.

For implementation work that changes behavior or contracts, run one fresh subagent review before publication or human handoff when subagents are available.
Keep purely mechanical and documentation changes proportional; they do not require a separate agent by default.
Give the reviewer the request, scope, revisions, governing instructions, and raw artifacts.
Let the reviewer form findings before supplying the author's suspected bugs or proposed answers.
For broad changes, assign coherent behavior slices and name the reviewer responsible for their shared boundaries.
Independent review still requires evidence for each finding.
Record unavailable independent review as a validation limit. Do not treat a zero-finding result as proof that the change is correct.

## Report and close the loop

Lead with actionable findings in severity order.
Give each finding a current file/line, trigger, consequence, and the evidence or missing guard.
State any assumptions needed to reproduce it.
Keep optional improvements separate and brief.

Record the reviewed revisions, covered paths, checks, and remaining validation limits.
If no actionable findings remain, say so without implying that untested paths passed.
For implementation handoff, include the material result in the PR's Review focus and Testing sections.
Use github-workflow's description guidance instead of creating another PR template.

Retain confirmed findings even when they were fixed during the review.
For a reusable lesson, record the trigger, failure mechanism, correction/commit, and regression evidence or remaining gap in the existing review summary.
Link the owning rule or review check when one exists. Deduplicate human and agent reports of the same defect.
During authorized publication, carry the concise technical lesson into the existing PR description or authorized reply so review-lessons can recover it.
For review-only work, keep it in the run summary. Recording a lesson does not authorize a new post or sharing a private chat.

After fixes or a material base change, review the complete resulting diff and affected consumers again.
Repeat checks only where changes or unresolved evidence invalidate the earlier result.
File deferred work through [todo-triage](../todo-triage/SKILL.md).
Stop when supported findings are resolved or explicitly reported and the required checks are accounted for.
