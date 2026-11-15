# 03 — Snapshot phase two and remaining candidates

- Status: ready
- Depends on: [02](02-snapshot-phase-one.md)
- Shared context: [Overview](README.md)
- Requirements: R-04 and R-05; exclusions X-01 and X-02 apply.

## Deliverable and steps

1. Remove iPad dark, AX5, contrast, and annotation captures from eight representative cases.
   The cases are About Default, Data Default, Devices Default, License Default, Regions Overview, DayRelabel Default, ManualDay Add, and LoggedDays Loaded.
2. Retain all five phone configurations, the light iPad baseline, and every additional named state.
   These changes remove 32 references and leave 893 before any fixture reframing.
3. Assess FlightReviewPointRow's screen-sized fixture for intrinsic component coverage at production row width.
   If its Form context is preserved, use five Gap configurations and two each for Restore and Ground.
   Record and review new fixture images separately from unchanged captures.
4. Assess the remaining Periscope hosting-only tests, Alerts/VisibleYear hosting checks, and repeated PlannedStayEditor matrices.
   Remove additional cases only where source and retained guards establish redundant coverage.
5. Record each remaining candidate's disposition, final counts, validation, and publication.

The explicit tradeoff is less tablet-by-trait coverage. Each representative still covers tablet layout and phone accessibility.
No production data flow or Swift architecture changes are required.

## Acceptance and verification

- Compare selected identities and remaining references for all eight suites.
- Require unchanged bytes for deletion-only captures.
- Run selected suites through `./test --snapshots --record never --timings`.
- If the row fixture changes, record only its new captures, inspect all images, then assert with `--record never`.
- Run retained unit guards affected by any additional cleanup.
- Run applicable formatting and shard checks, review the complete diff, and publish a ready PR.
- Link final evidence and unresolved related issues from the overview and STU-332.

## Recovery

Keep reframed images separate from deletion-only changes.
If a proposed cut removes unique meaningful coverage, retain it and record that disposition.

## Progress and evidence

Not started. All 32 proposed reference identities exist at the baseline.

## Resume point

After step 02, apply the eight tablet-matrix reductions and assess the remaining candidates.
