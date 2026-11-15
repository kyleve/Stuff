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
3. Keep FlightReviewPointRow's Form context and full-content phone frame.
   Retain five Gap phone configurations, its light tablet baseline, and two each for Restore and Ground.
   Remove Gap's four repeated tablet traits. This avoids fixture reframing and leaves 889 references.
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

All 32 proposed reference identities exist at the baseline. Assessment also supports four row-reference deletions and two unit-test removals.

| Candidate | Decision and evidence |
| --- | --- |
| FlightReviewPointRow | Keep Form styling and width unchanged; use five phone traits plus the light tablet baseline for Gap. The parent screen's point disclosure starts collapsed, so its tablet matrices do not replace the expanded row baseline. |
| PeriscopeViewerHostingTests | Remove both window-exists assertions. Viewer light/dark snapshots exercise its public root; model and stylesheet suites retain query, persistence, and density behavior. The removed tests did not assert comfortable density or loaded content. |
| Other Periscope hosting families | Retain for now: no equivalent image coverage was found for every tool. Their mount assertions do not establish async completion or store rebinding. |
| Alerts and VisibleYear hosting checks | Retain the existing mount checks because there is no direct image suite for either screen. |
| PlannedStayEditor | Retain its two representative matrices. NewStay and FlexibleStay render different date-control branches, and flexible arrival/departure adds controls and accessibility labels. Keep overlap and stale-save states. |

Source review did not establish equivalent coverage for the retained candidates. No additional reduction or replacement test is proposed for them.

## Resume point

After step 02, apply the eight tablet-matrix reductions, narrow Gap's tablet coverage, and remove the two redundant viewer mount tests.
