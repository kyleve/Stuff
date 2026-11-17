# Adaptive snapshot performance

## Planning checkpoint

- Updated: 2026-11-17 UTC; parent PR #512 at `bbbff2a430edbe8b1786f4748202016d0d1cabfe`.
- Operation: Execute the user's requested next performance improvement.
- Scope: MainTabs adaptive settling and fixture preparation, above PR #512.
- Stage: Local validation and independent review complete; preparing publication.
- Completed: Parent stack verification, baseline, passing 0.5s candidate, and bounded preparation profiling.
- Pending: Publication and manual CI dispatch.
- Next action: Publish the verified 0.5s policy and dispatch manual CI.

## Outcome and requirements

US-01: As a maintainer, I want faster snapshot feedback with the same captured content and coverage.

| ID | Requirement | Deliverable |
| --- | --- | --- |
| R-01 | Measure costs and validate a faster adaptive capture policy. | 01 |
| R-02 | Preserve all identities, dimensions, references, tolerances, native chrome, and accessibility passes. | 01–02 |
| R-03 | Preserve independent fixture state, awaited readiness, cancellation, cleanup, and the existing timeout derivation. | 01–02 |
| R-04 | Publish verified changes above PR #512, with reproducible evidence. | 01–02 |

X-01: No reference recording, matrix reduction, global mutable fixture reuse, or relaxed pixel proof.
X-02: Calendar and WebKit implementation changes are outside this follow-up.
X-03: No production behavior change is required. Any preparation optimization must preserve the existing demo world and preview behavior.

## Context and evidence

This follows the [completed measurement work](../2026-11-16-snapshot-measurement/README.md) and [STU-121](https://linear.app/kve/issue/STU-121).
The parent full run has 76 tests, 938 captures, 886.837s timed capture work, and a 957.697s runner.
MainTabs has 61 captures taking 154.924s. Its 39 adaptive captures take 121.406s: 65.819s settling and 46.025s preparation.
All adaptive cases declare a 1.5s floor; three annotation captures settle twice.
`DuoLayoutSnapshotFixture.prepare()` awaits a separate demo world and all outline resolutions. The hosted scene also calls preparation from its task.
`WhereFlyoverWorld.build()` constructs a demo scope, starts a session, and activates the report. These steps need separate measurements.
Baseline hardware: M5 Pro, Xcode 27.2 (27B52), iPhone 17 / iOS 27.2.
Repository source and local experiments suffice; no new platform API is proposed.

## Execution order and design

1. [01 — Adaptive settle floor](01-adaptive-floor.md): focused baseline, 0.5s and optionally 0.25s, repeated selected value.
2. [02 — Preparation costs](02-preparation-costs.md): instrument baseline subphases, then select at most two bounded optimization experiments from measured evidence.

The experiments share a baseline but run serially on the same simulator. No architecture change is proposed yet, so a new component diagram is unnecessary. Each configuration keeps its own world. Existing flow: mount scene → await world and artwork → settle native chrome → parse accessibility when requested → capture and compare.

## Questions and resolutions

| ID | Status | Question | Requirements | Blocking impact | Next action |
| --- | --- | --- | --- | --- | --- |
| Q-01 | closed | What smaller floor preserves adaptive chrome on the pinned runtime? | R-01–R-03 | Resolved by repetition | Two 0.5s runs pass; larger repeat diagnostics match successful parent CI. Reject 0.25s for new drift and slower comparisons. |
| Q-02 | closed | Which preparation stage consumes the 46s, and can redundant work be removed? | R-01–R-03 | Resolved to a measured negative result | Plan 02 records scope/session/report timings and the isolated comparison. Retain fresh worlds; no preparation API change is selected. |
| Q-03 | closed | Does lowering the floor change the timeout? | R-03 | Resolved by explicit policy choice | Review identified the coupled ceiling. Plan 01 now records 3s local / 6s CI, local maxima, and the pending CI limit. |

## Plan review

Reviewed 2026-11-17 UTC against `bbbff2a43`: requirements, fixture isolation, mounted-task behavior, native glass floor, repeated annotation settling, recovery, and exact capture coverage. Plans 01 and 02 are executable bounded experiments. The unknowns are their subjects, not prerequisites. No product choices are unresolved. No new architecture sketch is needed for a duration declaration and temporary timers. Independent review later identified the coupled timeout ceiling; the corrected plan explicitly accepts the derived values and preserves the validation limit.

## Review and delivery

Branch: `perf/adaptive-snapshot-readiness`, tracked above `perf/snapshot-measurement` in stack #513.
Independent review covered the full parent-to-working-tree diff, source consumers, raw timing and diagnostic logs, parent CI, and the PNG probe. No residual source findings remain after correcting the timeout claim. Publication and slow-CI validation remain pending.

## Outcome

In progress. STU-121 retains work beyond this bounded follow-up.
