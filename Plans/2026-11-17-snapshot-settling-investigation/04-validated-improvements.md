# 04 — Deliver validated improvements

- Status: draft
- Depends on: [03](03-controlled-experiments.md), evidence accepted; clean-source checks and publication pending.
- Shared context: [Overview](README.md), R-04 and X-02–X-04.

## Intended outcome

Remove proven redundant measurement settles and place artwork preparation before final settling. Preserve the complete image matrix, geometry, reference data, tolerances, cancellation, retry freshness, and all final capture floors.

## Proposed selected changes

Settings was rejected: all 16 early measurements changed capture height. Its existing measurement settle remains necessary even with synchronous data.

Plan 03 accepts setting `measurementReadiness: .immediate` explicitly on five synchronous fixture providers:

- `Shared/InstallerKitUI/Sources/UpdateBuildView.swift` and `UpdateHistoryView.swift`: fresh cached catalogs and a fixed fixture clock keep automatic refresh cache-only.
- `Where/WhereUI/Sources/Resolution/FlightReviewPointRow.swift`: prepared point data and a fixed-height map capture surface.
- `Where/WhereUI/Sources/Settings/PrivacyPassportCard.swift`: supplied disclosure content; motion changes the surface, not layout.
- `Where/WhereUI/Sources/Onboarding/OnboardingThemeSelectionView.swift`: supplied selection and artwork that preserves card layout.

Move only Onboarding's existing artwork hook from `onReadyToSnapshot` to `prepareForCapture`. Keep mounted-card final settling: warming the path cache does not certify publication into each card model.
The first cold control/candidate pair passes ten pixel-identical captures, including visible California artwork in both specimens. Its capture total falls from 12.536s to 6.076s; both repeated 62-capture pairs and the delayed oracle are also pixel-identical.

Keep the renderer unchanged. Its two bounded candidates have no repeatable end-to-end gain. Retain actual hierarchy-render guards for colored/translucent content, cumulative fading, one sample pixel, and wide-color neighbors. Remove every temporary experiment flag, image dump, added delay, and format print.

## Design and implementation steps

These are case declarations and regression coverage, with no new architecture or public API. The existing pipeline and pseudocode in plan 03 apply. Swift sketches describe the intended calls, not compilation evidence.

1. Complete plan 03 and review its acceptance evidence. Remove temporary probes; save their scripts, source hashes, logs, captures, and negative results outside Git. Commit experiment findings and useful regression guards as groundwork.
2. Add explicit readiness parameters and move Onboarding's hook. Explain the synchronous sizing or layout-preserving artwork assumption beside each provider. Keep each model builder and all matrices unchanged. Commit the verified behavior change separately.
3. Run `./swiftformat --lint`, the framework regressions through `./test SnapshotKitTestingTests --no-generate`, and affected image suites through `./test --snapshots --record never --review --timings --no-generate --only Bundle/Suite`.
4. Run the complete image suite serially with `./test --snapshots --record never --review --timings --no-generate`. Reconcile the capture multiset, pixels, tiles, retries, test identities, and intended policy changes against plan 02. This includes MainTabs, PlanningRegionPicker, Root, and Flyover late-change adversaries.
5. Review the final diff independently under `code-review`, publish above PR #524 through `gh stack`, and verify isolated CI. Keep the plan checkpoint and STU-121 current; do not merge without user authorization.

## Acceptance

- Every accepted fixture has normal/candidate repeated controls and an independent later-capture oracle with unchanged dimensions and explained pixel differences. Inspect Onboarding artwork in a cold process.
- Final production declarations pass affected and full-image assertions without recording references or narrowing coverage. Framework guards preserve noise, quiet windows, timeout/starvation, cancellation, retries, and cleanup.
- Savings distinguish repeated focused capture/settle totals from test time and full-suite observations. Do not extrapolate renderer CPU percentages into wall-clock savings.
- No experiment flags, extra waits, dump code, or untracked user files enter the commits.
- Root/Device Layout owner-task cancellation, DevicesSettings overlapping start cancellation, and the additional PlacesYear hook remain explicit follow-up scope in STU-121; do not call the broader issue complete.

## Review and resume point

All five-family controls and the delayed oracle pass with 62 pixel-identical images. Review confirms explicit fixture eligibility, preserved final settling, and excluded Settings/native paths. Await plan 03 publication before implementation. User authorization already covers execution; no additional approval is required.
