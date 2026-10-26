---
name: code-review
description: Review a PR, branch, or local diff for correctness, repository contracts, and validation gaps. Use for requested code reviews and the completed-diff review before publication. Use review-lessons for historical audits.
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
3. Map each material contract to its owning instruction, implementation, and existing guard.
   Keep this map in working notes or the review report.
   Load domain skills only for the affected work, including [building-ui](../building-ui/SKILL.md) for UI review.

If a review is too broad for complete inspection, identify the unreviewed areas explicitly.
Request a smaller coherent slice or report partial coverage. Do not infer correctness from sampling.
Separate mechanical changes from behavior changes when that separation makes the review verifiable.

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

Use only the applicable review questions:

| Changed boundary | Evidence to inspect |
| --- | --- |
| Types, identity, or stored state | Root type/state rules, affected callers, valid state combinations, explicit defaults, and creation of stable identity |
| Persistence or serialized data | Producer and consumer together, supported old data, stable keys, rename behavior, and the owning migration policy |
| Async work or lifecycle | Ownership before and after suspension, stale completion, cancellation, retry, teardown, and re-entry through production callers |
| Filesystem, process, or publication | Validation before mutation, partial failure, competing ownership, rollback, cleanup failure, exit status, and public-command tests |
| Credentials or untrusted input | Trusted source of commands/configuration, input validation, diagnostic redaction, and cleanup after failure |
| UI, navigation, or appearance | Production entry and return paths, shared components, styles, accessibility, changed images, and runtime evidence from building-ui |
| Shared infrastructure or fixtures | Existing implementation and extension seams, consumer coverage, and whether a second path duplicates production behavior |

For cross-language data, inspect the real serialized boundary or a shared wire fixture with both consumers.
For service-backed previews, use typed fixtures through the production service/model path.
Keep raw wire fixtures for tests of serialization and validation.
For async races, hold the dependency at the relevant suspension and inspect superseded completion.
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

When an independent review is requested, give the reviewer the scope, revisions, governing instructions, and raw artifacts.
Let the reviewer form findings before supplying the author's suspected bugs or proposed answers.
Independent review still requires evidence for each finding.

## Report and close the loop

Lead with actionable findings in severity order.
Give each finding a current file/line, trigger, consequence, and the evidence or missing guard.
State any assumptions needed to reproduce it.
Keep optional improvements separate and brief.

Record the reviewed revisions, covered paths, checks, and remaining validation limits.
If no actionable findings remain, say so without implying that untested paths passed.
For implementation handoff, include the material result in the PR's Review focus and Testing sections.
Use github-workflow's description guidance instead of creating another PR template.

After fixes or a material base change, review the complete resulting diff and affected consumers again.
Repeat checks only where changes or unresolved evidence invalidate the earlier result.
File deferred work through [todo-triage](../todo-triage/SKILL.md).
Stop when supported findings are resolved or explicitly reported and the required checks are accounted for.
