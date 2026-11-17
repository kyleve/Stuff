# Elsewhere and MainTabs snapshot readiness

## Planning checkpoint

- Updated: 2026-11-17. User approved investigating both opportunities after PR #518.
- Operation: Measure two bounded readiness changes and retain improvements supported by unchanged image output.
- Scope: Elsewhere artwork before capture settling; completion of MainTabs' mounted activation before capture settling. Preserve final pixel checks and measured native floors.
- Stage: Elsewhere verified; MainTabs completion design.
- Completed: Synchronized the parent after #517 merged; `49712814b` has the same complete tree as the previously tested `5691ed10f`. Baseline passed all 79 captures. Elsewhere saved 6.206s with identical images; see plan 01.
- Pending: MainTabs completion design/probe, focused regression coverage, independent review, and publication.
- Next action: Commit the verified Elsewhere change, then refine and execute plan 02.

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

Q-02 (open, plan 02/R-02): What signals completion of the actual mounted MainTabs activation without accepting a preloaded, canceled, superseded, or previous-host result? Seventeen welcome/update captures still call `report.activate()` after settling. The latest focused profile attributes 8.557s to that hook and second settle.

Q-03 (open, both/R-03): What savings survive matched output checks? Native adaptation remains separate: the adaptive MainTabs cases already prepare before capture and retain their measured 0.5s floor.

## Plan review

2026-11-17, parent `49712814b`: source and contract review supports the bounded Elsewhere experiment. Its callback only loads geometry into the injected cache and does not need settled UI. MainTabs cannot use its initial loaded flag: the mounted task starts a lifecycle revision and asynchronously refreshes multiple models. Plan 02 remains an outline until a specific completion boundary is reviewed. No new product decisions are required for these authorized experiments.
