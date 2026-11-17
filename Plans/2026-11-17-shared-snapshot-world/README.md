# Shared snapshot world initialization

## Planning checkpoint

- Updated: 2026-11-17, starting at PR #516 revision `d366fd1cf`.
- Operation: Execute the user's approved reuse of initialization across visual snapshot variants.
- Scope: 39 adaptive MainTabs variants and eight Device Layout Lab variants. Keep the cold/preloaded regression, world/lifecycle/mutation tests, and interactive Flyover behavior independent.
- Stage: Discovery and design.
- Completed: Counted 47 repeated visual worlds with the same fixed demo scenario. MainTabs preparation totals 45.077s in the latest profile.
- Pending: Select shared ownership and isolation boundaries, synchronize the stack after #514 merged, record the bounded implementation and validation plan.
- Next action: Inspect mutable state and readiness before implementing reuse.

## Outcome and constraints

US-01: As a maintainer, I want repeated visual variants to initialize their common demo data once per test process.

R-01: Scope reuse to the two approved image matrices. User approval supersedes the earlier blanket exclusion of shared worlds for this selected work.
R-02: Keep each capture's presentation state independent. Preserve data content, lifecycle correctness, cancellation, retry behavior, and order-independent output.
R-03: Keep all configurations, reference images, tolerances, settle policies, and cold-start coverage.
R-04: Measure setup and capture time; review and publish above #516 with final manual CI gates.

X-01: No shared worlds in mutation/lifecycle tests or ordinary interactive Flyover sessions. No lighter dataset or direct persistence bypass.

## Evidence and questions

The current `DuoLayoutSnapshotFixture` constructs `WhereDemoWorldModel` per case, and that model calls `WhereFlyoverWorld.build()`. The same standard scenario and reference date are repeated. Different captures use different tabs, navigation selections, traits, and viewports. A separate Device Layout Lab regression builds a ninth fresh world and must remain fresh.

Q-01 (open): Which prepared dependencies can be shared while per-capture presentation state remains independent?
Q-02 (open): What measurable benefit remains after preserving required isolation and readiness?

This follows [fixture data measurements](../2026-11-17-snapshot-fixture-data/README.md) and [STU-121](https://linear.app/kve/issue/STU-121). The user approved implementation on 2026-11-17. Repository source and measured profiles own this design; no new external platform API is planned.

## Review and delivery

Branch `perf/snapshot-shared-world`, stack #513. Implementation and publication pending. Preserve the unrelated untracked simple-english skill.
