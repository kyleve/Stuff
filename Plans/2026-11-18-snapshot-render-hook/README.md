# Can snapshot tests capture a settled frame sooner?

## Checkpoint

The repository owner approved a real-host experiment with SwiftUI’s test-render hook and asked whether the 250ms default might be necessary only for Liquid Glass controls. This follows [PR 533](https://github.com/kyleve/Stuff/pull/533) at `c23b824da`. The [experiment](01-render-hook-and-glass.md) runs on `perf/snapshot-render-hook`. The coordinator owns serial simulator runs, acceptance and publication. Separate investigators cover the temporary renderer, hosted controls and image/trace analysis. Both private-hook comparisons, targeted measurement runs and error-card timing pairs are complete. The only retained code change selects immediate readiness for two standalone error-card cases. The full-suite trial passed 935 captures. Targeted repeats, the clean Installer build and independent review are complete. Publication is the remaining step. [STU-121](https://linear.app/kve/issue/STU-121) tracks snapshot performance.

## Questions and acceptance

US-01. A maintainer wants to capture the intended size and pixels as soon as they are available. R-01 compares SwiftUI’s underscored render method with an otherwise identical ordinary draw. R-02 tests the 250ms minimum independently of the 120ms pixel check, with known glass and glass-free content. R-03 checks real fixtures against fresh ordinary and independently delayed captures, verifies hook coverage and measures any accepted optimization. X-01 excludes reference updates, changes to public appearance and promotion of undocumented APIs without evidence.

Q-01 (closed, R-01/R-03). Does explicitly rendering queued SwiftUI work make the final pixels or measured size available immediately? Both zero-interval methods ran on the mounted content. Each missed the same nine final images as one ordinary hierarchy draw. All three produced accurate Settings heights and all three captured the same early Region Picker measurement frames.

Q-02 (closed, R-02/R-03). Is glass presence enough to select a shorter wait? A glass-free delayed task yielded the wrong pixels with the default minimum removed. An already-ready view with visible glass rendered correctly in every treatment. The [original minimum](https://github.com/kyleve/Stuff/commit/6558824a84dfef32eb8f5af266d575541551be3c) addressed pre-adaptation native glass, and the [clock trials](../2026-11-18-settlement-clocks/01-clock-and-readiness-trials.md) separately demonstrated late data and draw-dependent geometry. The selected policy follows readiness of the specific fixture.
