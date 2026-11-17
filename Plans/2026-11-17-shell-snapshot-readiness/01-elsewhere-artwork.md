# Prepare Elsewhere artwork before final settling

Status: executing
Dependencies: none.
Requirements: [US-01, R-01–R-03, X-01](README.md#outcome-and-constraints).

## Method and acceptance

1. Record the complete Elsewhere/MainTabs baseline from parent `49712814b` with `--timings --review --record never`.
2. In `ElsewhereView`'s existing snapshot helper, move the unchanged artwork callback from `onReadyToSnapshot` to `prepareForCapture`. Keep model readiness in `onReadyToMeasure`.
3. Run the complete Elsewhere image matrix with the same diagnostic mode. Compare capture identities, dimensions, tiles, pixel diagnostics, phase timings, and retries. Do not record new references.
4. Keep the change only if images remain correct and elapsed capture work improves. Otherwise restore the callback and retain the supported negative evidence.
5. Review the full change and publish its evidence with the MainTabs investigation.

Existing behavior: measure loaded content → settle → load artwork → settle again → capture.
Candidate: measure loaded content → load artwork → settle → capture.
This only selects an existing callback phase; no new architecture or Swift pseudocode is needed.

Review, 2026-11-17: `prepareForCapture` runs after final hosting and before pixel settling, is bounded, and preserves cancellation. `loadCardArtwork` receives the same resolved regions and injected cache. Source inspection establishes suitability for an experiment, not image equivalence. Existing capture infrastructure tests cover this callback contract; the 18 owning images cover the actual screen change.

## Execution evidence

The baseline at `49712814b` passed both suites: 79 captures, 390,611,286 pixels, 79 tiles, and no retries. The focused Elsewhere candidate passed all 18 captures with the same 93,109,392 pixels and 18 tiles. Both runs matched every Elsewhere reference exactly; no references changed.

| Capture work | Baseline | Candidate |
| --- | ---: | ---: |
| Total | 21.891s | 15.685s |
| Post-settle hook, including another settle | 6.212s | 0s |
| Preparation before capture settling | 0s | 0.074s |
| Settle passes | 204 | 132 |

Saving: 6.206s (28.3%). These are local capture totals, not end-to-end CI wall time.

Commands: `TEST_WORKDIR=/private/tmp/stuff-shell-readiness-baseline-20261117 ./test --only WhereUISnapshotTests/ElsewhereViewSnapshotTests --only WhereUISnapshotTests/MainTabsSnapshotTests --no-generate --timings --review --record never`, then the same flags with only Elsewhere and work directory `/private/tmp/stuff-shell-readiness-elsewhere-20261117`. Normal architecture and host checks passed. `./swiftformat --lint` and `./sf-symbols --lint` passed.

Resume: retain the callback change. Independent review and publication remain, alongside plan 02.
