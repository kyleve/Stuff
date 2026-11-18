# Snapshot dependencies and settling

[STU-121](https://linear.app/kve/issue/STU-121) tracks snapshot performance. Timed comparisons use the per-call diagnostics from [PR 524](https://github.com/kyleve/Stuff/pull/524) at `e479fa140`. The dependency updates and corrected accessibility image target `main` directly.

## Checkpoint

On November 18 the user requested testing newer snapshot packages as a route to faster settling, then approved publishing the updates together against `main`. The [dependency trial](01-dependency-trial.md) is complete. After reviewing the 0.13 badge and legend changes, the user approved adopting that release in [PR 539](https://github.com/kyleve/Stuff/pull/539). The [annotation refresh](02-annotation-refresh.md) is complete. All 159 framework tests and 979 image captures passed. The updated run establishes the next settling baseline.

## Scope and questions

US-01. A maintainer wants to capture settled geometry and pixels sooner while retaining meaningful image comparisons. R-01 identifies changes to rendering, accessibility and readiness in the two direct snapshot dependencies. R-02 validates any proposed upgrade against existing references and records whether the measured evidence supports a speedup. X-01 fixes references, tolerances and settle policies for every performance comparison. The initial upgrade corrected the tall-view reference. The subsequent [annotation refresh](02-annotation-refresh.md) adopts the 0.13 design across accessibility configurations.

Q-01 (closed, R-01/R-02). Do the current releases expose a readiness signal or reduce measured settling? Inspection of the tagged sources found no new signal on the capture path. In four local runs, both 0.12.1 timings fell inside the range of the two 0.12.0 controls. The [results](01-dependency-trial.md#timing-result) distinguish the tall-view fix from the timing evidence.

## Where a future settling experiment could start

In the post-530 local and CI traces, 148 intrinsic captures had one ordinary measurement settle and one ordinary content settle, with no accessibility parsing or readiness-hook phase. Their measurement settles alone took 43.6 seconds locally and 67.1 summed worker-seconds in CI. A pilot could retain one mounted view, measure after a draw, then prove stability at its final size. Those figures are the cost to investigate. Real savings depend on how much sizing and settling still has to run. [PR 530](https://github.com/kyleve/Stuff/pull/530) · [CI measurement](https://app.circleci.com/workflow/df6d565c-6c0f-450f-a067-ce45ea4fd1f5/job/e2998bf0-229f-4fe0-bb99-367433cb4bab)

The previous geometry experiment found a change in viewport or effective safe-area insets between stages in all 36 sampled controls. Its late-growing fixture measured 80 points before reaching 240. Those are concrete checks for any pilot that shares a host. [Geometry experiment](../2026-11-18-settlement-clocks/01-clock-and-readiness-trials.md#can-the-two-waits-be-combined)
