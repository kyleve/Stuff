# Shared snapshot world initialization

## Planning checkpoint

- Updated: 2026-11-17, starting at PR #516 revision `d366fd1cf`.
- Operation: Execute the user's approved reuse of initialization across visual snapshot variants.
- Scope: Evaluate 39 adaptive MainTabs variants and eight Device Layout Lab variants; retain the three narrow-window cold starts after failed warm-layout probes. Keep the cold/preloaded regression, world/lifecycle/mutation tests, and interactive Flyover behavior independent.
- Stage: Complete; [PR #517](https://github.com/kyleve/Stuff/pull/517) is ready for review.
- Completed: Share one initialization across 44 visual cases; retain three narrow cold starts. Eight unit tests, 70 matched images, 69 reversed-order images, and all 801 WhereUI images pass. Matched capture savings: 42.478s (27.7%).
- Pending: Remote CI results and the separately recorded warm narrow-viewport renderer limitation. The issue remains In Review. After #516 merged, stack synchronization preserved the tested tree exactly on `e07e95cee`.
- Next action: Review PR #517 and its remote CI results; no further implementation is planned in this slice.

## Outcome and constraints

US-01: As a maintainer, I want repeated visual variants to initialize their common demo data once per test process.

R-01: Scope reuse to the two approved image matrices. After measured geometry failures, share the 44 compatible cases and retain the three narrow-window cold starts. User approval supersedes the earlier blanket exclusion of shared worlds for this selected work.
R-02: Keep each capture's presentation state independent. Preserve data content, lifecycle correctness, cancellation, retry behavior, and order-independent output.
R-03: Keep all configurations, reference images, tolerances, settle policies, and cold-start coverage.
R-04: Measure setup and capture time; review and publish above #516 with final manual CI gates.

X-01: No shared worlds in mutation/lifecycle tests or ordinary interactive Flyover sessions. No lighter dataset or direct persistence bypass.

## Evidence and questions

Before this change, `DuoLayoutSnapshotFixture` constructed `WhereDemoWorldModel` per case, and that model called `WhereFlyoverWorld.build()`. The same standard scenario and reference date are repeated. Different captures use different tabs, navigation selections, traits, and viewports. A separate Device Layout Lab regression builds a ninth fresh world and must remain fresh.

Q-01 (closed): The selected image suites inject one test-owned world through fresh demo-model wrappers, except for three narrow-window cases retained after warm-layout failures. Views own navigation and selection. Session, report, services, and preferences are shared only for these noninteractive captures. Source inspection and 69 reversed-order image assertions on 2026-11-17 support this fixed matrix. Mounted Locations reconciliation can update last-seen counts automatically; the world is not immutable.
Q-02 (closed): Matched 70-capture time falls from 153.241s to 110.763s; runner time falls from 165.430s to 124.253s. The full run passes all references, but it uses `--review` while the prior full profile omitted that diagnostic work. Those full runs do not establish overall or CI wall-clock savings. See plan 01 for exact phase evidence.

This follows [fixture data measurements](../2026-11-17-snapshot-fixture-data/README.md) and [STU-121](https://linear.app/kve/issue/STU-121). The user approved implementation on 2026-11-17. Repository source and measured profiles own this design; no new external platform API is planned.

## Review and delivery

Branch `perf/snapshot-shared-world`, stack #513, [PR #517](https://github.com/kyleve/Stuff/pull/517), based on `main` after #516 merged. Implementation `6e3ec2062` has the same tested tree as reviewed `ce78104d7`. The unrelated untracked simple-english skill remains unchanged.

## Plan review

2026-11-17, source `9af57f369`: reviewed plan 01 against all four requirements and X-01. The explicit injection keeps previews, lifecycle tests, and the cold regression fresh. Added cancellation and failure-retry checks because the shared task outlives an individual caller. Repository evidence suffices; no new platform API. Mermaid was inspected but not rendered. This is design review, not implementation verification. User approval authorizes execution.

2026-11-17 revision review: the initial candidate and ready-before-hosting probe fail the same three narrow-window references. A 1.5s settle diagnostic produces identical failures. Retaining those three fresh worlds is the bounded compatibility fallback; 44 cases remain shared. This revises the technical implementation within the approved two-matrix scope, preserves all coverage, and avoids a separate shared-renderer change. Independent review supports this boundary.
