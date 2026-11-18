# Pending layout during snapshot settling

The repository owner requested a recursive check immediately after the settle loop calls `layoutIfNeeded()`. The question is whether a child still has pending layout and whether processing it immediately can bring the captured image to its stable state sooner. This follows the [settlement clock investigation](../2026-11-18-settlement-clocks/README.md) and [PR 532](https://github.com/kyleve/Stuff/pull/532).

## Checkpoint

The [experiment](01-post-layout-observation.md) runs on `perf/snapshot-pending-layout` from `f12cb58d8`. The coordinator owns simulator runs and publication. The three investigations covered the recursive probe, hosted controls and trace analysis. All focused treatments and fixture controls are complete. The next checkpoint is full-suite verification of the retained switch. [STU-121](https://linear.app/kve/issue/STU-121) tracks snapshot performance.

## Requirements and review

US-01. A maintainer needs to identify pending layout in real snapshot hierarchies and determine whether further synchronous layout helps. R-01 requires an opt-in diagnostic that identifies the affected view and pass. R-02 tests how flags change across drawing and suspension, with controls that distinguish layout from display and delayed updates. R-03 compares a bounded intervention against ordinary images and settlement. X-01 excludes global invalidation, changes to timing floors, pixel tolerances and reference updates.

Q-01 (closed for trial design). UIKit exposes the marked state through each view's backing layer. Walk every subview even if its parent is clean. The existing quiescence experiment combines several signals and short-circuits on any positive. Q-02 (closed for trial design). A remaining flag could be actionable or come from a view that stays dirty. Test it against both the next pixel samples and independent capture output. The design was reviewed against the renderer, timing schema and PR 532 traces at `f12cb58d8`. Execution is authorized by the request.
