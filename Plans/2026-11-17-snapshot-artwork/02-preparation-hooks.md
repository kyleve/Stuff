# 02 — Prepare artwork before settling

- Status: executing
- Depends on: None; measure after the verified cache-only step in [plan 01](01-shared-cache.md). The callback migration also works with separate caches.
- Shared requirements: [Overview](README.md), R-02–R-05; exclusions X-01 and X-02.

## Deliverable

Move artwork loading from `onReadyToSnapshot` to `prepareForCapture` in Appearance settings, LocationForecastSummary, LocationForecastPanel, LocationsBackground, and RegionWelcomeCard. All five already declare immediate measurement; their artwork decorates fixed geometry. Preserve every final settle policy and existing artwork model ownership. No new architecture is required: this uses PR #511's existing readiness phase.

## Steps and acceptance

1. Change only the five selected callback labels after plan 01's cache-only measurement. Keep post-settle actions outside this selection unchanged.
2. Run plan 01's five-suite command with matching timing/review flags. Repeat the selected implementation in a separate process. Each run must execute five tests and 63 captures without retries.
3. Compare capture identities, sizes, tiles, reference results, and diagnostic regions against the baseline. Investigate any new larger differences before acceptance; do not record references or relax tolerances.
4. Run `./test --no-generate --skip-host-tests --snapshots --timings --record never` for broad integration after shared cache injection. Run affected unit tests and lint once for the final behavior source, repeating only if later changes invalidate them.
5. Remove temporary profiling, document actual timings and limitations, and run independent review of the complete parent-to-tip diff.
6. Publish above PR #514 with `gh stack submit --auto --open`. Dispatch GitHub and CircleCI full gates on the final tip, verify their revisions, and report pending results without waiting for CI. Append evidence to STU-121 and keep it open.

## Recovery and evidence

Revert only an unsupported callback migration while preserving verified cache reuse. Preserve raw logs outside Git; record concise commands, counts, revisions, and decisions here. Actual artwork publication remains mandatory even on cache hits; the path cache does not hold fixture models or worlds.

## Execution record

The cache-only step passes at `c42e9456d`. The five selected providers now use `prepareForCapture` (six label replacements); all floors, measurement policies, capture configurations, and callback bodies are unchanged.

The first combined profile passes five tests and 63 captures with no retries. It totals 37.346s versus the 65.589s baseline: 28.243s saved (43.1%). The preparation phase takes 0.455s; the earlier post-settle hook phase took 26.163s because it included another settle. Settle passes fall from 911 to 445. All capture identities, policies, dimensions, pixel counts, tiles, and all 22 diagnostic payloads match the baseline. Independent review verified these raw results.

A separate-process repeat passes the same five tests and 63 captures with no retries. Capture time is 37.319s (28.270s saved, 43.1%); preparation takes 0.465s, with 444 settle passes. All 22 diagnostic payloads again match baseline exactly. Full Swift formatting and symbol lint pass.

## Resume point

The callback step is verified. Run full image integration and review the final diff before publication.
