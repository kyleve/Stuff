# 02. Reduce layout work during Calendar zoom

Status: executing. Reviewed on November 20 at `798c61cc4`. Independent of plan 01.

## Outcome and method

US-02 / R-02. Speed up Calendar's repeated month/year zoom while keeping the same scroll position, selection, geometry, motion and accessibility. The hosted test runs six cycles, resizes the same view midway, and checks two viewport widths and both Reduce Motion settings. Keep all four combinations.

A 42-second Time Profiler capture of the hosted test produced 29.373 seconds of CPU sample weight. SwiftUI graph updates appeared in 61% of samples, layout sizing in 27%, and the test's element lookup in 8%. These overlap. Stay indicator construction appeared in 2.384 seconds of samples. The full suite took 75.575 seconds in the unprofiled control, including 56.407 seconds for the zoom test.

1. Inspect the existing month tiles and their zoom copies. First try drawing a stay indicator directly in the bounds its cell already supplies. Preserve the half-gap extension, rounded ends, colors, accessibility contrast and hatch alignment for planned stays.
2. Compare the complete unprofiled `./test --only WhereUITests/CalendarContentViewTests` suite and its zoom test against the same main tree, simulator, inputs and warm build. Repeat the timing to estimate variation. If the design fails visual checks or the time stays flat, revise it or try another measured Calendar rendering cost. Discard unsupported changes.
3. Run relevant day-grid, transition and Calendar image coverage with recording disabled. Inspect any reported differences before retaining a change. Measure suite wall time separately from sampled CPU time and CI runner totals.

The experiment uses the existing SwiftUI view and rendering pipeline. The proposed flow is `DayCell → stay indicator in the cell's bounds → SwiftUI layout`. No new owner or interface is needed. X-02 excludes reducing cycles, shortening the animations, recording changed reference images to pass, or switching the calendar to lazy rows.

## Execution record

The Calendar implementation agent owns the experiment on `perf/calendar-zoom-layout`. The primary agent owns independent review and publication into `main`. Resume with the first rendering experiment.
