# Snapshot measurement and readiness performance

## Planning checkpoint

- Updated: 2026-11-17 UTC; parent `f4e3b4c8c`, tested source `da968a6b3`.
- Operation: Complete the measured snapshot improvements.
- Requested scope: Continue through the largest remaining opportunities, stacked on PR #511.
- Stage: Complete; PR #512 is ready for review in stack #513.
- Completed: Bounded WebKit experiments, synchronous measurement changes, repeated Locations floor validation, full image integration, independent review, and publication.
- Remaining scope: Further readiness investigations stay in STU-121 and STU-122.
- Next action: Review PR #512. Follow its checks for the separate manual CI gates required by stacked branches.

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
Fixture source and focused captures establish the selected scope. The WebKit investigation also uses primary platform documentation.

## Planning horizon

Completed [01 — WebKit readiness](01-webkit-readiness.md), [02 — Synchronous measurement](02-synchronous-measurement.md), and [03 — Locations floor](03-locations-floor.md).
These plans share R-01–R-04 and retain the existing pipeline and APIs.
Unselected candidates remain in Linear.

## Questions and resolutions

| ID | Status | Question | Affected requirements | Blocking impact | Next action |
| --- | --- | --- | --- | --- | --- |
| Q-01 | closed | Which expensive measurement probes already have synchronous final height? | R-01–R-03 | Resolved for plan 02 | RegionSummaryCard, seeded FlightDayDetailView, and standalone MonthAccessibility qualify. Full Calendar remains task-driven. |
| Q-02 | closed | What consumes the 49s of WebKit readiness, and can a deterministic signal avoid it? | R-01–R-03 | Resolved for this bounded experiment | Navigation dominates. Two reuse variants retain most of that cost; no WebKit change is selected. Further work stays in STU-122. |
| Q-03 | closed | Which raised floors have explicit completion evidence after PR #511? | R-01–R-03 | Resolved by repeated captures | Prepared Locations cases have seeded counts and awaited paths. The 0.25s floor passes twice plus full integration, with native chrome and accessibility guards retained. |

## Plan review

[01 — WebKit readiness](01-webkit-readiness.md) was reviewed for experiment bounds, baseline, invariants, recovery, and verification at `f4e3b4c8c`. The WebKit experiment is concluded with no retained source change. Plan 02 passed focused coverage after tracing height ownership and task behavior. Plan 03 passed both candidates and a separate 0.25s repetition after tracing initial counts, preference ownership, and delayed reconciliation. Full integration passes all 76 tests and 938 captures at `da968a6b3`, with no retries. No product choices are unresolved; the user authorized these performance investigations and implementation.

## Review and delivery

Independent review covered `f4e3b4c8c..da968a6b3`, all four Swift changes, all four plan files, and their readiness/geometry consumers. No actionable findings remain. The reviewer independently matched focused and repeated capture identities, dimensions, sizing, tiles, and larger byte-drift diagnostics against the parent and baseline CI. Full integration passes all 76 tests and 938 captures at `da968a6b3`, with no retries.

Published [PR #512](https://github.com/kyleve/Stuff/pull/512) in [stack #513](https://github.com/kyleve/Stuff/stack/513). The parent PR head and description are unchanged.

The stack is `main` → `perf/snapshot-readiness` (PR #511) → `perf/snapshot-measurement`.
All temporary instrumentation is removed. Plans 02 and 03 change fixture declarations only. Each verified step has its own commit.

## Outcome

Full image integration passes at `da968a6b3`: 76 tests, 938 captures, zero retries, unchanged references and tolerances. Capture identities, pixel dimensions, sizing, and tile counts match the parent.

| Measurement | PR #511 | PR #512 | Reduction |
| --- | ---: | ---: | ---: |
| Test runner | 1,009.319s | 957.697s | 51.622s (5.11%) |
| Timed captures | 940.378s | 886.837s | 53.541s (5.69%) |
| Four affected suites' captures | 215.339s | 159.671s | 55.668s (25.85%) |

Unchanged suites total 725.039s before and 727.166s after. Both full runs use `./test --no-generate --snapshots --timings --record never` on the same M5 Pro, Xcode 27.2 (27B52), and iPhone 17 / iOS 27.2. Runner time excludes build and generation. This is one full run per revision; the selected Locations matrix also passed a separate repetition.

`./swiftformat --lint`, `./sf-symbols --lint`, architecture checks, and `git diff --check` pass. `./sync-agents --check` passes in a clean export of tracked files. The working checkout retains an unrelated untracked skill that exceeds the guidance size limit. Raw logs, capture rows, test results, and the matched comparison remain in the session's `snapshot-next-results` artifacts.

[PR #512](https://github.com/kyleve/Stuff/pull/512) contains the retained changes. [STU-121](https://linear.app/kve/issue/STU-121) retains further measurement and floor work; [STU-122](https://linear.app/kve/issue/STU-122) records the WebKit experiment and further navigation profiling. No WebKit implementation is retained.

## Question resolution evidence

- Q-01: Source at `f4e3b4c8c` establishes fixed RegionSummaryCard artwork geometry, a nil scan in seeded FlightDayDetailView reports, and a fully supplied MonthGridView. Plan 02 implements the resulting scope.
- Q-02: Plan 01 records 46.192s navigation versus 1.712s paint. Both bounded reuse experiments retain most navigation cost. [Apple’s data-store contract](https://developer.apple.com/documentation/webkit/wkwebsitedatastore) confirms that store reuse also shares cookies and caches, so it needs an explicit isolation design. No such API is added for the limited measured gain.
- Q-03: Plan 03 records the seeded-count and artwork evidence. It preserves a floor and both accessibility passes while testing the pinned runtime.
