# Await MainTabs' mounted activation

Status: outline
Dependencies: none; execute after plan 01 to keep measurements and commits distinct.
Requirements: [US-01, R-01–R-03, X-01](README.md#outcome-and-constraints).

## Intended result and refinement trigger

Investigate replacing `settle → activate again → settle` in the 17 welcome/update captures with `await mounted activation → settle`. The other MainTabs families keep their current readiness and floors.

Q-02 must identify the exact mounted operation and its cancellation/supersession behavior before implementation. The shell task and foreground handling both call `YearReportModel.activate()`, which starts a new lifecycle revision. Fixture data starts loaded, so observing `.loaded` does not prove completion. The previous Calendar review also showed that retries reuse the root view value in fresh hosting controllers.

Refine when source inspection identifies a narrow completion seam that preserves production activation semantics and can distinguish fresh mounts, retries, cancellation, and any superseding work. Add a bounded prototype method and focused behavioral checks, then compare the complete 61-capture MainTabs matrix. A supported negative result is acceptable; remove unproven prototypes.

A detailed diagram and Swift sketch depend on the completion seam. No generic readiness framework or production activation coalescing is selected.
