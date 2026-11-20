# Reduce ordinary iOS test runtime

## Planning checkpoint

On November 20 the owner selected both Time Profiler findings for implementation as separate PRs into `main`. This follows the [snapshot performance work](../2026-11-18-snapshot-performance/README.md). The two experiments apply to ordinary iOS tests. They share a baseline and have independent implementations, branches, checks and merge order. The numbered records in this directory own measured results, review and delivery.

| Deliverable | Outcome | Owner and execution branch |
| --- | --- | --- |
| [01. Demo journal batch · PR 549](https://github.com/kyleve/Stuff/pull/549) · [reviewed plan](https://github.com/kyleve/Stuff/blob/26745d86c/Plans/2026-11-20-ios-test-performance/01-demo-journal-batch.md) · [STU-203](https://linear.app/kve/issue/STU-203) | US-01 / R-01. Seed the same demo world and publish its final derived data once. | Demo implementation agent, `perf/demo-journal-batch` |
| [02. Calendar zoom layout · PR 548](https://github.com/kyleve/Stuff/pull/548) · [reviewed plan](https://github.com/kyleve/Stuff/blob/53c2bdf40/Plans/2026-11-20-ios-test-performance/02-calendar-zoom-layout.md) · [STU-338](https://linear.app/kve/issue/STU-338) | US-02 / R-02. Reduce rendering work while retaining the same zoom interactions and images. | Calendar implementation agent, `perf/calendar-zoom-layout` |

The primary agent owns the completed-diff reviews and PR handoff. Compare like-for-like, unprofiled runs and report sample weights separately. Verification and publication for either branch can proceed independently.

## Evidence and decisions

Three passing CI runs ranked Calendar zoom first at 63–71 seconds and the demo issue-category matrix second at 24–25 seconds. On the latest run the iOS unit worker used 1,792 credits and finished about a minute after snapshots. A local control at the same tree as `798c61cc4` passed all 22 tests. Absolute simulator times depend on the runner. [CircleCI unit job](https://app.circleci.com/workflow/75b4d836-dd45-4a9b-87e3-86222eb101bc/job/3cd2c380-3c96-4784-8b45-627847f44c65)

Q-01 (closed). The demo spends time rebuilding widget history after intermediate writes. One transactional import can exercise the production services while retaining all issue masks. Q-02 (closed). The Calendar trace included substantially more SwiftUI layout work than test-side element lookup. Preserve the six real zoom cycles across both widths and motion preferences. Both decisions follow the measured profiles and the owner's November 20 request.

Reviewed against main `798c61cc4`. Each numbered plan defines a bounded experiment and the checks that determine whether to retain it. X-01 preserves data and audit semantics. X-02 preserves Calendar coverage, motion and rendering. Both exclude changes to CI scheduling, worker count and parallelism.

## Native child safe-area follow-up

The November 20 suite survey measured two unnecessary visual settling passes around a read-only UIKit geometry check. The owner selected the measured change for a separate PR to main. [Plan 03](03-native-insets.md) records the twelve configurations and acceptance evidence. Published in [PR 552](https://github.com/kyleve/Stuff/pull/552). [STU-339](https://linear.app/kve/issue/STU-339)
