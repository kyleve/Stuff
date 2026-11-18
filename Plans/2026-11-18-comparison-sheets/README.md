# Comparison sheet performance

## Checkpoint

The repository owner selected comparison sheets as the next snapshot performance investigation after [PR 530](https://github.com/kyleve/Stuff/pull/530). The previous [performance plan](../2026-11-18-snapshot-performance/README.md) is complete. This follow-up covers one experiment on `perf/snapshot-comparison-sheets`, based on `7580962fd`. The [experiment](01-sheet-composition.md) is complete and independently reviewed in [PR 531](https://github.com/kyleve/Stuff/pull/531) at `c3f2d24c4`. The root ran the local benchmarks. A second investigator supplied the fixed-input replay. The six affected image suites, full image suite, framework tests and CI passed. [STU-121](https://linear.app/kve/issue/STU-121) tracks snapshot speed and [STU-123](https://linear.app/kve/issue/STU-123) tracks ongoing visibility into sheet costs.

## Scope and decisions

US-01. A developer running component snapshots wants less time between panel capture and the final verdict. R-01 measures that work. R-02 requires the same whole-canvas pixels, approved panel identities, labels and bounds on fixed inputs. R-03 preserves the independent panel and whole-image verdicts, recording policy and existing capture counts. X-01 excludes changes to public readiness policies, panel capture, reference tolerances, committed images and shard assignments.

Q-01 (closed, November 18). Where should the experiment begin? PR 530's five sheet-only suites spent 42.0s locally and 55.3 summed CI seconds outside panel timings. Source inspection found an additional hosted settle for immutable images and labels, then a second PNG encode before writing metadata. The six owning suites include 57 sheets in total. The two suspected costs have independent controls in the experiment. Their benefit is an experimental outcome.

Reviewed the scope and experiment at `7580962fd`. Inspection of the renderer and its guards identified two requirements for accepting an earlier capture: compare the whole canvas including headings and exercise measured placements at host scale. Distinct PNG metadata serializations can represent identical images and maps. CI worker 0, the slowest in the PR 530 run, owned no sheets.

## Outcome

The five sheet-only suites took **25.7% less time locally** and **24.8% less time in CI**. The complete local suite ran in **734.851s**, down from 757.995s on PR 530. Immediate layout of the static grid and lossless PNG metadata writing preserved the whole-canvas pixels, maps and verdicts on all 57 fixed-input sheets. The [execution record](01-sheet-composition.md) includes both full runs, the measured stages before and after, and the limits of whole-job CI attribution.
