# 03 — Snapshot phase two and remaining candidates

- Status: complete
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
| Other Periscope hosting families | Retain for now: no equivalent image coverage was found for every tool. Their mount assertions do not establish async completion or store rebinding. [STU-49](https://linear.app/kve/issue/STU-49) owns the remaining 18 checks across nine files. |
| Alerts and VisibleYear hosting checks | Retain the existing mount checks because there is no direct image suite for either screen. |
| PlannedStayEditor | Retain its two representative matrices. NewStay and FlexibleStay render different date-control branches, and flexible arrival/departure adds controls and accessibility labels. Keep overlap and stale-save states. |

Source review did not establish equivalent coverage for the retained candidates. No additional reduction or replacement test is proposed for them.

- Applied all 32 audited removals plus four Gap tablet variants. Every retained PNG remains unchanged.
- Removed `PeriscopeViewerHostingTests` and its local defaults helper: two fewer test declarations.
- Final inventory against `2193072f6`: 3,030 → 2,973 unit declarations; 954 → 889 PNGs; 1,011 → 946 reference panels.
  The 65 deleted references represent 101,888,066 hydrated bytes (97.2 MiB).
- Swift formatting, diff whitespace, guidance checks, and the 71-suite shard inventory passed.
- Focused verification passed: 23 Periscope unit tests and 82 reference captures across ten snapshot suites.
  Emitted timing identities match all remaining references in those suites. No reference was recorded or modified.
- Command: `./test --record never --timings`, with repeated `--only` for these selections:
  `PeriscopeToolsTests/PeriscopeViewerModelTests`, `PeriscopeStylesheetTests`, and `PeriscopeStylesheetEnvironmentTests`;
  `WhereUISnapshotTests/AboutSettingsViewSnapshotTests`, `DataSettingsViewSnapshotTests`, `DevicesSettingsViewSnapshotTests`,
  `LicenseViewSnapshotTests`, `RegionsSettingsViewSnapshotTests`, `DayRelabelViewSnapshotTests`, `ManualDayViewSnapshotTests`,
  `LoggedDaysViewSnapshotTests`, and `FlightReviewPointRowSnapshotTests`;
  `PeriscopeToolsSnapshotTests/PeriscopeViewerSnapshotTests`.
  Log: `/private/tmp/stuff-test-reduction-phase-two.log`; full output and timing identities were retained alongside it.
- Independent review against `d36763ed8` found no actionable code issue. It verified every deletion and all 80 retained WhereUI PNG hashes.
- The review identified STU-49's obsolete blanket snapshot-conversion request. Its partial cleanup and current selection policy are recorded without changing the historical migration manifest.
- Delivery: the final implementation commit for this plan in [PR #505](https://github.com/kyleve/Stuff/pull/505). STU-332 stays In Review until merge and acceptance verification.
- The full local suite and physical-device testing were not run: production behavior, capture infrastructure, and image pixels did not change.
  Final CI status is reported on the PR; no runtime savings are claimed.

## Resume point

Complete. Review [PR #505](https://github.com/kyleve/Stuff/pull/505); no implementation step remains in this series.
