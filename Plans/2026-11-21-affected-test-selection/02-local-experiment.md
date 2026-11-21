# 02 — Representative local PR experiment

- Status: ready
- Depends on: [01](01-selection.md)
- Shared context: [Overview](README.md)

## Deliverable and bounds

Satisfy R-04 under X-01 through X-04. Answer Q-02 with four to six recent merged feature PRs across distinct repository areas.
Replay their complete landed diffs through the current graph, without changing the worktree to historical app revisions.
Retain exact commit pairs, commands, selected and skipped bundle lists, and reasons.
Run a focused local smoke check to verify that a normal execution consumes selection correctly.
Do not equate bundle counts with test-case counts or elapsed-time savings.

## Method and acceptance

The stable interface is `./test --dry-run --json --base MERGE_COMMIT^ --head MERGE_COMMIT`.
Use the six PRs below, selected by area from the 55 most recently merged PRs returned by `gh pr list`.
Include feature fixes because recent main history contains many test-only optimizations.

| PR | Area and reason |
| --- | --- |
| #506 | Screen-width feature with many UI and snapshot changes. |
| #496 | Device layout feature spanning a shared library and WhereUI. |
| #494 | Flyover pan/zoom fix with downstream UI consumers. |
| #537 | Focused persistence fix in WhereCore. |
| #495 | Broad data-compatibility feature with app, extension, and specification inputs. |
| #503 | Prototype tooling feature as an unknown-input control. |

Pin each merge commit and its first parent. Confirm they resolve locally and that the merge base is that parent.
Replay complete diffs, including documentation and configuration; do not trim paths to improve the result.
Save selected/skipped lists and identities in `selections.json` and describe results in `RESULTS.md`.
Verify each report partitions all 28 logical iOS bundles and retains independent checks.
Use the public command contract regression to check that normal execution applies previewed filters.
Also run `./test CreditKitTests` as a real simulator smoke check of the modified runner.

The result must show whether the tool saves execution scope and where conservative fallback removes the benefit.
A supported negative result can complete this experiment. An inconclusive timing result is allowed because this experiment measures selection.
Keep a concise report and machine-readable selections; remove temporary logs from the tracked deliverable.

## Progress and resume

Reviewed 2026-11-21: the bounded sample, exact command, current-graph limitation, and negative-result criteria satisfy R-04 without changing CI.
Discovery replayed the six cases against the working implementation. Final acceptance waits for 01's publication and a replay pinned to that implementation revision.
The real smoke check and independent review passed as recorded in 01.
Resume: after 01 completes, retain the final six reports and report their interpretation. No comparative timing experiment is planned.
