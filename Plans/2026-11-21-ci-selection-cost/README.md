# Price affected-test selection in iOS CI

## Planning checkpoint

The owner requested a replay of the last 100 merged PRs after [#555](https://github.com/kyleve/Stuff/pull/555). This follows the [local selector experiment](../2026-11-21-affected-test-selection/RESULTS.md). Its six representative PRs established which bundles the selector chose. The next decision needs worker time, credit estimates, and merge-gate economics. [STU-344](https://linear.app/kve/issue/STU-344)

The primary agent owns the report on `perf/price-affected-test-selection`. The replay worker owns the historical sample and selector outputs, the timing worker the price model, and the independent reviewer the policy and fixture-cache comparison. [Plan 01](01-replay.md) is complete. The landed-diff replay and the earlier-head sensitivity are published in the [cost comparison](RESULTS.md). The recommended next trial is to cache the installer-site fixture.

| ID | Requirement for the CI maintainer (US-01) |
| --- | --- |
| R-01 | Replay 100 merged-to-main PRs using the landed selector, the actual diff, and the existing lightweight CI rules. |
| R-02 | Price each worker, count empty workers and shorter critical paths, and report uncertainty and full-validation requirements. |
| R-03 | Compare the result with the opportunity to cache the installer-site snapshot fixture. |
| X-01 | Use existing data. Changes to CI selection, merge evidence, runner counts, caching, and test behavior require a separate decision. |

Q-01 (closed for the method). The owner approved a cost replay before a CI trial. Source review at `327b3f58e` confirmed that existing merge reuse requires full PR results and that the two existing #554 runs retained per-worker timing data. Plan 01 prices a selected PR head and discusses the cost of retaining that requirement. This is an evidence report and proposes no Swift or runner architecture.
