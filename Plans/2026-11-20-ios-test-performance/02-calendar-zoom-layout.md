# 02. Reduce layout work during Calendar zoom

Status: complete. Published in [PR 548](https://github.com/kyleve/Stuff/pull/548). Reviewed on November 20 at `798c61cc4`. Independent of plan 01.

## Outcome and method

US-02 / R-02. Speed up Calendar's repeated month/year zoom while keeping the same scroll position, selection, geometry, motion and accessibility. The hosted test runs six cycles, resizes the same view midway, and checks two viewport widths and both Reduce Motion settings. Keep all four combinations.

A 42-second Time Profiler capture of the hosted test produced 29.373 seconds of CPU sample weight. SwiftUI graph updates appeared in 61% of samples, layout sizing in 27%, and the test's element lookup in 8%. These overlap. Stay indicator construction appeared in 2.384 seconds of samples. The full suite took 75.575 seconds in the unprofiled control, including 56.407 seconds for the zoom test.

1. Inspect the existing month tiles and their zoom copies. First try drawing a stay indicator directly in the bounds its cell already supplies. Preserve the half-gap extension, rounded ends, colors, accessibility contrast and hatch alignment for planned stays.
2. Compare the complete unprofiled `./test --only WhereUITests/CalendarContentViewTests` suite and its zoom test against the same main tree, simulator, inputs and warm build. Repeat the timing to estimate variation. If the design fails visual checks or the time stays flat, revise it or try another measured Calendar rendering cost. Discard unsupported changes.
3. Run relevant day-grid, transition and Calendar image coverage with recording disabled. Inspect any reported differences before retaining a change. Measure suite wall time separately from sampled CPU time and CI runner totals.

The experiment uses the existing SwiftUI view and rendering pipeline. The proposed flow is `DayCell → stay indicator in the cell's bounds → SwiftUI layout`. No new owner or interface is needed. X-02 excludes reducing cycles, shortening the animations, recording changed reference images to pass, or switching the calendar to lazy rows.

## Execution record

The Calendar implementation agent owns `perf/calendar-zoom-layout`. The primary agent owns independent review and publication. [PR 548](https://github.com/kyleve/Stuff/pull/548) · [STU-338](https://linear.app/kve/issue/STU-338)

| Isolated code change | Suite / zoom seconds | Decision |
| --- | ---: | --- |
| Original control | 75.575 / 56.407 | Retain the full test matrix and repeat the baseline for the final comparison. |
| Draw the stay band directly in the cell's proposed bounds | 87.773 / 68.306 | Hosted behavior passed during a concurrent build. Strict snapshots showed the planned-stay hatch had moved. Restore the original renderer. |
| Build day-level accessibility only for standalone cells | 76.038 / 56.975 | Whole months already expose a single summary. Removing child work did not shorten this run. |
| Eager equal-width stacks per week | 76.582 / 57.211 | Restore the native grid. |
| Native grid with fixed-height tracks behind day cells | 78.287 / 58.703 | Extra sizing wrappers did not shorten the run. |

Further source inspection found that preparing a zoom and starting its animation each mount a fresh copy of the same visible source months. Compare retaining the source views by target identity through both phases. Keep the final scroll alignment, overlay occlusion, full animation completion and Reduce Motion behavior. Verify the interactive phases with the hosted tests.

## Retaining the source months

The flight now has one identity for the entire transition and one tile per target. During preparation, each source tile uses its measured frame for both ends. When the destination is ready, the same source tile receives its destination frame and starts the existing animation. If the destination was ready at the first mount, the animation also starts. The lifecycle still ends through SwiftUI's full animation-completion callback.

| Matched local result | Main, two runs | Candidate, two runs |
| --- | ---: | ---: |
| Existing 10 hosted Calendar tests | 75.575, 75.513 s | 72.579, 72.304 s |
| Zoom test, four parameter combinations | 56.407, 56.721 s | 54.213, 54.154 s |

On the same iPhone 17 and iOS 27.2 simulator, the existing suite saved 3.103 seconds (4.1%) and its zoom test saved 2.381 seconds (4.2%) on average. The reduction came from the two spatial zoom cases. The Reduce Motion cases bypass the spatial overlay and tracked the control. These are local measurements across two runs per version.

The new regression test took 0.095 seconds, bringing the net local saving across the existing suite and new test to about 3.0 seconds. On main, the source mounted twice when the destination arrived after preparation. The candidate mounted each endpoint once, including when the destination was already available. An independent reviewer checked identity, cancellation, completion and the test. In a separate real-spring experiment, both versions took about one second and drew intermediate widths between the 120- and 370-point endpoints in both entry paths.

The focused run of `WhereUITests/CalendarContentViewTests` passed all 10 existing tests. Additional `./test` selections covered `CalendarMonthAccessibilityTests`, `CalendarPresentationStateTests`, `CalendarZoomOverlayTests` and `CalendarZoomTransitionStateTests` (21 tests), plus both tests and 66 images in `WhereUISnapshotTests/CalendarContentViewSnapshotTests` with `--record never --review`. Seventeen comparisons differed by at most one color-channel level, within the existing tolerance. No images were recorded. Architecture and host checks, SwiftFormat lint and diff checks passed. RTL and spoken VoiceOver behavior were reviewed in source.

Implemented at `09d395501`. [Implementation PR](https://github.com/kyleve/Stuff/pull/548) · [STU-338](https://linear.app/kve/issue/STU-338)
