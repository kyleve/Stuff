# 03 — Evaluate controlled settling improvements

- Status: outline
- Depends on: [02](02-classify-costs.md).
- Shared context: [Overview](README.md).

## Intended outcome

Resolve Q-04 for R-03. Select bounded experiments from measured causes: redundant measurement/hosting, known completion signals, detector cost, or case-specific minimum durations.
Preserve R-04 and X-02–X-04. A supported negative result can close a selected experiment.

## Known boundaries and provisional design

Earlier completion decisions initially run alongside the existing verdict and cannot control capture.
Promising decisions need focused early/normal/later image checkpoints, expected-content and geometry assertions, and delayed-work adversaries.
Extra rendering can perturb timing; keep passive decision collection separate from additional capture experiments.
Exact candidate APIs, sample schedules, fixture families, and acceptance thresholds are deliberately unresolved until Q-03 and Q-05 are answered.
No universal idle detector, stale readiness across mounts, or weakened pixel tolerance is authorized.

## Refinement trigger

After plan 02 provides current local/CI costs and overhead bounds, select the highest-value bounded experiments.
Write concrete interfaces, diagrams/pseudocode where architecture changes, negative guards, repetition schedule, and cleanup/retention rules before readiness.
Keep rejected experiments and their evidence; remove temporary probes that do not become useful diagnostics.

## Resume point

Implementation has not started. Refine this file after plan 02; do not infer recoverable savings from gross phase duration.
