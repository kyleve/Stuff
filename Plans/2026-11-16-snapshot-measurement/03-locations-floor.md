# 03 — Remeasure the prepared Locations capture floor

- Status: executing
- Depends on: None; the simulator run is sequenced after plan 02's focused check.
- Shared context: [Overview](README.md)

## Deliverable and requirements

Remeasure the prepared Locations cases on Xcode 27.2 / iOS 27.2 and retain a smaller floor only if repeated captures preserve their output.
This addresses US-01 and R-01–R-04, with X-01–X-03 unchanged.
The baseline `LocationsViewSnapshotTests` has 54 captures, 78.297s capture time, and 64.266s final settling.

## Readiness evidence

`artworkSnapshot` seeds the report and awaits all three outline resolutions before capture settling.
`PreviewSupport.previewPreferences()` creates fresh in-memory preferences. The first card presentation uses current counts when no saved count exists.
Its later reconciliation persists those same counts; it does not introduce a late fixture count or rank transition.
The same model/preferences remain consistent across the case's configurations.
Native glass remains asynchronous and still needs a measured floor plus the unchanged pixel proof.

## Experiment and design

Only `LocationsView.artworkSnapshot` is selected. Cases outside that helper keep their existing floors.
Try 0.5s first, then 0.25s if the first candidate passes. Both remain `.settledAtLeast`, retaining the second accessibility parse.
Keep the 120ms anchored pixel proof, minimum matching passes, capture timeouts, inset reconciliation, and reference comparison unchanged.
No production architecture or data flow changes: an existing fixture duration is remeasured after PR #511 added explicit preparation.

## Steps

1. Change the helper's floor from 1.0s to the first candidate and run all Locations snapshots with timings and review.
2. Compare capture identities, pixel dimensions, references, and drift with the parent profile. Inspect materially different diagnostics.
3. If supported, try the second candidate. If it fails, restore the proven first value; if both fail, restore 1.0s.
4. Repeat the selected candidate in a separate simulator test invocation. Require no capture failures or retries.
5. Run full image coverage at the stack tip and retain the dated measurements beside the declaration and in this plan.
6. Review independently and publish above PR #511. A negative result is valid evidence and stays in STU-121.

## Acceptance and verification

From the repository root, use `./test --no-generate --only WhereUISnapshotTests/LocationsViewSnapshotTests --timings --review --record never` for each candidate and its repetition.
Full integration uses `./test --no-generate --snapshots --timings --record never`.
Require all 54 focused captures and the full suite to pass unchanged references, with matching identities/dimensions and no retries.
Raw diagnostic byte differences need comparison with the parent; normal thresholds are never widened.
The retained value must save measurable settling time. Keep this result specific to the pinned toolchain and prepared fixtures.

## Recovery

Restore only the helper's previous duration if either sizing or output is unreliable. Do not record new references.
Keep untouched cases and production card reconciliation unchanged.

## Review and progress

- 2026-11-16: Reviewed fixture readiness, fresh preferences, delayed reconciliation, native chrome contracts, bounded candidates, and validation at parent `f4e3b4c8c`.
- Q-03 resolved to a bounded toolchain remeasurement of explicitly prepared cases. A lower value is not yet proven.
- The prior outline listed plan 02 as a dependency only for simulator serialization. The implementations are independent; sequencing remains explicit without a publication dependency.
- The 0.5s candidate passed all 54 captures with 43.449s settling, versus 64.266s at the parent.
- The 0.25s candidate passed all 54 captures with 35.819s settling and zero retries. All identities and pixel counts match the parent. The two larger byte-difference rows exactly match baseline CI job 4413; no reference changed.
- The separate 0.25s repetition passed 3 tests and all 54 captures, with 35.585s settling and no retries. Identities, dimensions, and tile counts match. Only 37 of 54 captures use the changed helper. Pending: full integration, final review record, and publication.

## Resume point

Both 0.25s runs passed. Run full image integration, retain the independent review record, and publish the stack.
