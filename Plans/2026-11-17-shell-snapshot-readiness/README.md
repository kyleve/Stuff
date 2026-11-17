# Elsewhere and MainTabs snapshot readiness

## Planning checkpoint

- Updated: 2026-11-17. User approved investigating both opportunities after PR #518.
- Operation: Measure two bounded readiness changes and retain improvements supported by unchanged image output.
- Scope: Elsewhere artwork before capture settling; completion of MainTabs' mounted activation before capture settling. Preserve final pixel checks and measured native floors.
- Stage: Both changes verified; review and publication.
- Completed: Synchronized the parent after #517 merged; `49712814b` has the same complete tree as the previously tested `5691ed10f`. Baseline passed all 79 captures. Elsewhere saved 6.206s with identical images; see plan 01.
- Pending: Complete independent review and publication. PR #518 has merged with passing checks; synchronize the stack after committing and compare the tested tree.
- Next action: Publish the verified changes. Elsewhere is committed as `c4843ee05`; MainTabs code and validation are recorded in plan 02.

## Outcome and constraints

US-01: As a maintainer, I want snapshots to await their required work once and avoid redundant settling.
R-01: Preserve references, configurations, dimensions, tolerances, final pixel stability, and native-glass floors.
R-02: Completion must belong to the current mounted work, including cancellation, retries, and rehosting. A preloaded model's `.loaded` state is insufficient.
R-03: Compare matched `--timings --review --record never` runs. Phase cost is not a promised saving. Retain supported negative results and remove failed prototypes.
X-01: No global settle-policy changes, private runtime inspection, disabled native effects, or changes to production activation semantics merely to accelerate fixtures.

## Execution order

1. [Elsewhere artwork preparation](01-elsewhere-artwork.md): current horizon, independently testable.
2. [MainTabs mounted activation](02-main-tabs-activation.md): refine after tracing completion and cancellation boundaries.

Each retained change gets its own verified commit on `perf/snapshot-shell-readiness`, above PR #518. [STU-121](https://linear.app/kve/issue/STU-121) owns this continuation. The earlier completed plans remain unchanged.

## Questions and evidence

Q-01 (closed, plan 01/R-01): Does moving Elsewhere artwork preparation before final settling preserve every image and remove the second settle? The matched experiment preserved all 18 images exactly and saved 6.206s. Measurement already awaits the resolved model. Integrated into plan 01's execution evidence on 2026-11-17.

Q-02 (closed, plan 02/R-02): What signals completion of the actual mounted MainTabs activation without accepting a preloaded, canceled, superseded, or previous-host result? Source inspection supports a DEBUG-only per-mount receipt completed after the existing activation task returns without cancellation. The 17 affected fixtures have fixed scene phases and perform no writes or year changes; this is not a general scene-idle signal. Plan 02 records cancellation, rehosting, and retry coverage. The baseline attributes 8.567s to the existing hook and second settle. Integrated and reviewed on 2026-11-17.

Q-03 (closed, both/R-03): What savings survive matched output checks? The final matched 79-image comparison falls from 113.220s to 89.639s, saving 23.581s (20.8%). Elsewhere saves 6.200s; MainTabs saves 17.381s. Plan 02 records output limits and the separately corrected retry fixture. Native adaptation remains separate: adaptive MainTabs cases retain their measured 0.5s floor. Integrated on 2026-11-17.

## Plan review

2026-11-17, parent `49712814b`: source and contract review supports the bounded Elsewhere experiment. Its callback only loads geometry into the injected cache and does not need settled UI. MainTabs cannot use its initial loaded flag: the mounted task starts a lifecycle revision and asynchronously refreshes multiple models. Plan 02 remains an outline until a specific completion boundary is reviewed. No new product decisions are required for these authorized experiments.

2026-11-17, completed-diff review: a fresh independent reviewer examined `49712814b` through `c4843ee05` plus the uncommitted MainTabs implementation, tests, documentation, and raw artifacts. No actionable findings remain. The review verified per-mount ownership, fixed-scene scope, cancellation, retry behavior, unchanged image metadata and floors, and the measured savings. It retained the corrected retry-fixture finding: selecting Settings requires a `WhereModel` environment; the focused regression passed after that dependency was supplied. Plan 02 records the failed combined invocation and subsequent successful checks separately.
