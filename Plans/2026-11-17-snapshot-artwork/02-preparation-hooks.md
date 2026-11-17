# 02 — Prepare artwork before settling

- Status: ready
- Depends on: [Shared cache](01-shared-cache.md)
- Shared requirements: [Overview](README.md), R-02–R-05; exclusions X-01 and X-02.

## Deliverable

Move artwork loading from `onReadyToSnapshot` to `prepareForCapture` in Appearance settings, LocationForecastSummary, LocationForecastPanel, LocationsBackground, and RegionWelcomeCard. All five already declare immediate measurement; their artwork decorates fixed geometry. Preserve every final settle policy and each view's own artwork publication. No new architecture is required: this uses PR #511's existing readiness phase.

## Steps and acceptance

1. Change only the five selected callback labels after plan 01's cache-only measurement. Keep post-settle actions outside this selection unchanged.
2. Run plan 01's five-suite command with matching timing/review flags. Repeat the selected implementation in a separate process. Each run must execute five tests and 63 captures without retries.
3. Compare capture identities, sizes, tiles, reference results, and diagnostic regions against the baseline. Investigate any new larger differences before acceptance; do not record references or relax tolerances.
4. Run `./test --no-generate --skip-host-tests --snapshots --timings --record never` for broad integration after shared cache injection. Run affected unit tests and lint once for the final behavior source, repeating only if later changes invalidate them.
5. Remove temporary profiling, document actual timings and limitations, and run independent review of the complete parent-to-tip diff.
6. Publish above PR #514 with `gh stack submit --auto --open`. Dispatch GitHub and CircleCI full gates on the final tip, verify their revisions, and report pending results without waiting for CI. Append evidence to STU-121 and keep it open.

## Recovery and evidence

Revert only an unsupported callback migration while preserving verified cache reuse. Preserve raw logs outside Git; record concise commands, counts, revisions, and decisions here. Fresh fixture state and actual artwork publication remain mandatory even on cache hits.

## Execution record

Not started.

## Resume point

Wait for plan 01's cache-only validation, then migrate the five selected hooks.
