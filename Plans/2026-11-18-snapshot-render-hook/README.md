# Can snapshot tests capture a settled frame sooner?

## Checkpoint

The repository owner approved a real-host experiment with SwiftUI’s test-render hook and asked whether the 250ms default might be necessary only for Liquid Glass controls. This follows [PR 533](https://github.com/kyleve/Stuff/pull/533) at `c23b824da`. The [experiment](01-render-hook-and-glass.md) runs on `perf/snapshot-render-hook`. The coordinator owns serial simulator runs, acceptance and publication. Separate investigators own the temporary renderer, hosted controls and image/trace analysis. [STU-121](https://linear.app/kve/issue/STU-121) tracks snapshot performance.

## Questions and acceptance

US-01. A maintainer wants to capture the intended size and pixels as soon as they are available. R-01 compares SwiftUI’s underscored render method with an otherwise identical ordinary draw. R-02 tests the 250ms minimum independently of the 120ms pixel check, with known glass and glass-free content. R-03 checks real fixtures against fresh ordinary and independently delayed captures, verifies hook coverage and measures any accepted optimization. X-01 excludes reference updates, changes to public appearance and promotion of undocumented APIs without evidence.

Q-01 (open, experiment). Does explicitly rendering queued SwiftUI work make the final pixels or measured size available immediately? Q-02 (open, experiment). Is the absence of a glass control sufficient to shorten the default wait, or is an application readiness signal still required? The pinned SDK exposes the hook. The [original floor change](https://github.com/kyleve/Stuff/commit/6558824a84dfef32eb8f5af266d575541551be3c) identifies pre-adaptation native glass. The [clock trials](../2026-11-18-settlement-clocks/01-clock-and-readiness-trials.md) separately demonstrated late data and draw-dependent geometry. The design was checked against both paths and the previous exact-image comparisons. These questions determine the result of the experiment and do not block execution.
