# Shared snapshot world initialization

## Planning checkpoint

- Updated: 2026-11-17, starting at PR #516 revision `d366fd1cf`.
- Operation: Execute the user's approved reuse of initialization across visual snapshot variants.
- Scope: Evaluate 39 adaptive MainTabs variants and eight Device Layout Lab variants; retain the three narrow-window cold starts after failed warm-layout probes. Keep the cold/preloaded regression, world/lifecycle/mutation tests, and interactive Flyover behavior independent.
- Stage: Final integration validation for [01 — shared world](01-shared-world.md).
- Completed: Counted 47 repeated visual worlds with the same fixed demo scenario. MainTabs preparation totals 45.077s in the latest profile.
- Pending: Complete the full WhereUI image bundle and publish. Matched 70/reversed 69 images and eight unit tests pass; independent source review is complete. Stack synchronized after #514 and #515 merged; parent is `2c24c3415`.
- Next action: Finish full-bundle validation, then publish and dispatch CI gates.

## Outcome and constraints

US-01: As a maintainer, I want repeated visual variants to initialize their common demo data once per test process.

R-01: Scope reuse to the two approved image matrices. After measured geometry failures, share the 44 compatible cases and retain the three narrow-window cold starts. User approval supersedes the earlier blanket exclusion of shared worlds for this selected work.
R-02: Keep each capture's presentation state independent. Preserve data content, lifecycle correctness, cancellation, retry behavior, and order-independent output.
R-03: Keep all configurations, reference images, tolerances, settle policies, and cold-start coverage.
R-04: Measure setup and capture time; review and publish above #516 with final manual CI gates.

X-01: No shared worlds in mutation/lifecycle tests or ordinary interactive Flyover sessions. No lighter dataset or direct persistence bypass.

## Evidence and questions

The current `DuoLayoutSnapshotFixture` constructs `WhereDemoWorldModel` per case, and that model calls `WhereFlyoverWorld.build()`. The same standard scenario and reference date are repeated. Different captures use different tabs, navigation selections, traits, and viewports. A separate Device Layout Lab regression builds a ninth fresh world and must remain fresh.

Q-01 (closed): The selected image suites inject one test-owned world through fresh demo-model wrappers, except for three narrow-window cases retained after warm-layout failures. Views own navigation and selection. Session, report, services, and preferences are shared only for these noninteractive captures. Source inspection on 2026-11-17 supports this boundary; opposite-order image validation is required.
Q-02 (closed): The bounded measurement in plan 01 will determine the benefit. Acceptance requires lower preparation and runner time without output regressions; no savings are assumed in advance.

This follows [fixture data measurements](../2026-11-17-snapshot-fixture-data/README.md) and [STU-121](https://linear.app/kve/issue/STU-121). The user approved implementation on 2026-11-17. Repository source and measured profiles own this design; no new external platform API is planned.

## Review and delivery

Branch `perf/snapshot-shared-world`, stack #513. Implementation and publication pending. Preserve the unrelated untracked simple-english skill.

## Plan review

2026-11-17, source `9af57f369`: reviewed plan 01 against all four requirements and X-01. The explicit injection keeps previews, lifecycle tests, and the cold regression fresh. Added cancellation and failure-retry checks because the shared task outlives an individual caller. Repository evidence suffices; no new platform API. Mermaid was inspected but not rendered. This is design review, not implementation verification. User approval authorizes execution.

2026-11-17 revision review: the initial candidate and ready-before-hosting probe fail the same three narrow-window references. A 1.5s settle diagnostic produces identical failures. Retaining those three fresh worlds is the bounded compatibility fallback; 44 cases remain shared. This revises the technical implementation within the approved two-matrix scope, preserves all coverage, and avoids a separate shared-renderer change. Independent review supports this boundary.
