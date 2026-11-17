# Snapshot completion hooks

## Planning checkpoint

- Updated: 2026-11-17, source `445375f86`, following PR #517.
- Operation: Investigate the user's proposed completion hooks for settling and measurement; retain a bounded improvement if evidence supports it.
- Scope: Explicit application readiness, measurement completion, and public UIKit update hooks. Preserve image correctness and cancellation.
- Stage: Complete; published in [PR #518](https://github.com/kyleve/Stuff/pull/518).
- Completed: Public update-callback probe; Calendar mount/readiness implementation; four unit tests and 63 reference captures; forced-retry regression; independent source and raw-evidence review.
- Pending: Remote CI results, tracked separately from local acceptance.
- Next action: Review remote results when available; broader settling opportunities remain in STU-121.

## Outcome and constraints

US-01: As a maintainer, I want captures to await meaningful completion instead of paying avoidable timing delays.
R-01: Identify which work a hook actually completes, including later async work that remains possible.
R-02: Preserve references, dimensions, tolerances, pixel-stability guards, cancellation, and cleanup.
R-03: Measure matched diagnostic modes and keep supported negative results.
X-01: No global floor removal, runtime introspection of private native state, run-loop pumping, or disabled native effects. The user has enabled auto-merge on #517; avoid changing that PR while investigating this next slice.

## Evidence and questions

The existing hooks are `prepareForCapture`, `onReadyToMeasure`, and `onReadyToSnapshot`. Pixel settling uses a fixed anchor and a 120ms quiet proof; its generic floor is 250ms. Native chrome has measured per-case floors. A prior run-loop/layout/animation-key quiescence probe declared eight loaded states ready too early.

Q-01 (closed, R-01, plan 01): Public UI update callbacks do not replace general settling. The 124-capture probe observed 221 phases: all 188 detached phases received zero callbacks. The 33 scene-backed phases received their first callback after a median 6.47ms, but settled after 570.15ms. Apple's API completes one update, not future async work. This is incorporated in the experiment and module guidance.

Q-02 (closed, R-01–R-02, plan 01): Calendar already publishes its year from the mounted month task's reconciliation. The capture hook awaits that specific mounted presentation through Swift Observation, then measures without a pixel settle. Final capture settling remains unchanged. Independent review found a builder-time retry bug in the first prototype; the corrected wrapper creates and stores content once per host mount, and a forced retry verifies the boundary.

Q-03 (closed, R-03, plan 01): Retain the Calendar change and the negative UIKit result. The uninstrumented control confirms 75.626s → 53.601s across the same 63 captures: 22.025s (29.1%) saved. Measurement plus its hook falls 32.230s → 10.345s (67.9%). Identities, dimensions, tile counts, and substantive pixel diagnostics match. This result is integrated into [the execution evidence](01-readiness-experiment.md#validation-and-outcome) and independently reviewed.

[STU-121](https://linear.app/kve/issue/STU-121) owns this continuation. Existing completed plans remain unchanged. Branch `perf/snapshot-completion-hooks` is published above #517 in [stack #519](https://github.com/kyleve/Stuff/stack/519), continuing the earlier stack #513 series.

## Execution order and review

The current horizon is [01 — Observe completion boundaries](01-readiness-experiment.md), including the retained Calendar improvement. Its review records the source, method, correction, acceptance evidence, and limitations.

## Research and review evidence

The pinned Xcode 27.2 headers and Apple's [UI update phase documentation](https://developer.apple.com/documentation/uikit/uiupdateactionphase/afterupdatecomplete) define completion of one update. [Observations](https://developer.apple.com/documentation/observation/observations) tracks transactions on observable state. Neither source claims that all future work or all native rendering has completed.

The completed-diff review covers the full change against `445375f86`. Its confirmed finding was stale readiness on retry: `captureConfiguredSnapshot` builds a view value once and rehosts that value in fresh controllers. The initial prototype created its presentation before mounting. The corrected wrapper starts with empty `@State`, creates concrete content once per mounted host, and consumes each mount registration once. The regression test builds the root once, forces a retry after reconciliation, and verifies two distinct presentations and a full-height result. Cancellation before and after mounting also permits a subsequent wait. The independent reviewer verified the corrected source and final/control raw logs, with no remaining findings. Implementation `cde3fb37c` is published in PR #518.
