# Snapshot measurement and readiness performance

## Planning checkpoint

- Updated: 2026-11-16, parent revision `f4e3b4c8cb6fb26b49cb3b12fed6cc91b10dbede`.
- Operation: Plan and execute the next measured snapshot improvements.
- Requested scope: Continue through the largest remaining opportunities, stacked on PR #511.
- Stage: Full integration and independent review.
- Completed: WebKit bounded experiments; validated and committed synchronous measurement changes; validated both Locations candidates and a separate 0.25s repeat.
- Pending: Full image integration, final independent review evidence, stack publication, and Linear updates.
- Next action: Run the full image suite at the selected source revision, then publish the stack and final measurements.

## Outcome and scope

Reduce snapshot execution time while preserving rendered content, sizing, coverage, failure reporting, and cancellation.
Deliver measured changes above [PR #511](https://github.com/kyleve/Stuff/pull/511).
Related work: [STU-121](https://linear.app/kve/issue/STU-121) and [STU-122](https://linear.app/kve/issue/STU-122).

## User stories

| ID | Story |
| --- | --- |
| US-01 | As a maintainer, I want faster snapshot feedback with the same rendering and readiness guarantees. |

## Requirements

| ID | Required behavior | Story | Deliverable |
| --- | --- | --- | --- |
| R-01 | Choose changes from measured capture costs and report matched before/after evidence. | US-01 | Plans 01–03 |
| R-02 | Preserve capture identities, dimensions, references, tolerances, and native chrome readiness. | US-01 | Every selected change |
| R-03 | Preserve failure, cancellation, cleanup, and serialization contracts. | US-01 | Every selected change |
| R-04 | Publish verified work in a tracked stack above PR #511. | US-01 | Final integration |

## Not required and explicitly avoided

| ID | Category | Exclusion | Reason |
| --- | --- | --- | --- |
| X-01 | Explicitly avoided | Weaker pixel stability, broader image tolerances, or fewer configurations. | These alter coverage instead of removing avoidable work. |
| X-02 | Explicitly avoided | Simulator parallelism or heuristic replacement of the pixel proof. | Existing measured regressions remain applicable. |
| X-03 | Not required | Production appearance changes or reference recording. | This work changes test execution. |

## Research and evidence

The completed profile at the parent revision reports 938 captures in 940.378s and a 1,009.319s test runner.
Intrinsic measurement costs 181.684s; Locations and MainTabs final settling costs 147.810s; InstallerSite measurement callbacks cost 49.000s.
The baseline is one full local run on Apple M5 Pro, Xcode 27.2, and iPhone 17 / iOS 27.2.
Raw evidence remains in the session's `snapshot-readiness-results` artifact directory.
Repository evidence will determine which waits can change. Platform claims will use primary documentation when required.

## Planning horizon

Execute [01 — WebKit readiness](01-webkit-readiness.md) and [02 — Synchronous measurement](02-synchronous-measurement.md).
Then refine [03 — Locations floor](03-locations-floor.md) from their evidence.
These plans share R-01–R-04; each retains the existing pipeline and APIs unless plan 01 establishes a scoped reuse need.
Unselected candidates remain in Linear.

## Questions and resolutions

| ID | Status | Question | Affected requirements | Blocking impact | Next action |
| --- | --- | --- | --- | --- | --- |
| Q-01 | closed | Which expensive measurement probes already have synchronous final height? | R-01–R-03 | Resolved for plan 02 | RegionSummaryCard, seeded FlightDayDetailView, and standalone MonthAccessibility qualify. Full Calendar remains task-driven. |
| Q-02 | closed | What consumes the 49s of WebKit readiness, and can a deterministic signal avoid it? | R-01–R-03 | Resolved for this bounded experiment | Navigation dominates. Two reuse variants retain most of that cost; no WebKit change is selected. Further work stays in STU-122. |
| Q-03 | closed | Which raised floors have explicit completion evidence after PR #511? | R-01–R-03 | Resolved to a bounded experiment | Prepared Locations cases have seeded counts and awaited paths. Remeasure 0.5s and 0.25s while retaining native chrome and accessibility guards. |

## Plan review

[01 — WebKit readiness](01-webkit-readiness.md) was reviewed for experiment bounds, baseline, invariants, recovery, and verification at `f4e3b4c8c`. The WebKit experiment is concluded with no retained source change. Plan 02 passed focused coverage after tracing height ownership and task behavior. Plan 03 passed both candidates and a separate 0.25s repetition after tracing initial counts, preference ownership, and delayed reconciliation. Full integration remains pending. No product choices are unresolved; the user authorized these performance investigations and implementation.

## Review and delivery

The stack is `main` → `perf/snapshot-readiness` (PR #511) → `perf/snapshot-measurement`.
All temporary instrumentation is removed. Plans 02 and 03 change fixture declarations only. Each verified step will have its own commit.

## Outcome

Focused changes pass. Final integration and publication are in progress.

## Question resolution evidence

- Q-01: Source at `f4e3b4c8c` establishes fixed RegionSummaryCard artwork geometry, a nil scan in seeded FlightDayDetailView reports, and a fully supplied MonthGridView. Plan 02 implements the resulting scope.
- Q-02: Plan 01 records 46.192s navigation versus 1.712s paint. Both bounded reuse experiments retain most navigation cost. [Apple’s data-store contract](https://developer.apple.com/documentation/webkit/wkwebsitedatastore) confirms that store reuse also shares cookies and caches, so it needs an explicit isolation design. No such API is added for the limited measured gain.
- Q-03: Plan 03 records the seeded-count and artwork evidence. It preserves a floor and both accessibility passes while testing the pinned runtime.
