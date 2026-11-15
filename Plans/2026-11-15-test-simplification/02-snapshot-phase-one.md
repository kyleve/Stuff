# 02 — Snapshot phase one

- Status: ready
- Depends on: [01](01-unit-tests-and-guidance.md)
- Shared context: [Overview](README.md)
- Requirements: R-03 and R-05; exclusions X-01 and X-02 apply.

## Deliverable

Remove 29 reference PNGs, reducing the baseline from 954 to 925.
No production data flow or architecture changes are required.

| Suite | Before → after | Retained coverage |
| --- | --- | --- |
| YearView | 20 → 12 | Loaded phone light/dark/AX5/annotations and tablet light; existing extra states; each load state at innerPortrait |
| MainTabs | 75 → 61 | Focused Elsewhere integration; WelcomeYear light; WelcomeLocations variants; distinct adaptive frames and Locations selection |
| LocationsView | 57 → 54 | Each load state at innerPortrait; all loaded scenarios; navigation-bar/inset probes |
| UpdateFailureCard | 10 → 7 | MissingFeed light/dark and the complete OfflineCached representative |
| Inspector | 4 → 3 | Strict SwiftData light and Root light/dark; remove the intermittent dark quarantine |

## Steps

1. Narrow recorded configurations at their existing declarations.
2. Keep preview and Flyover state names, including FlatElsewhere, independently of recorded image selection.
3. Remove only unselected references. Leave retained PNG bytes, readiness hooks, frames, and comparison budgets unchanged.
4. Keep fold-transition unit guards and the selected Locations tabletop integration image.
5. Record the coverage tradeoffs and preserve STU-20's unresolved renderer status.

## Acceptance and verification

- Compare emitted identities and remaining references for the five changed suites.
- Compare retained PNG hashes against the baseline; expect no modifications.
- Run `./test --snapshots --record never --timings` with `--only` for the five suites.
- Run relevant catalog and fold-state guards through `./test --only`.
- Run Swift formatting checks and `./snapshot-shards check`.
- Review and publish this step before phase two.

## Recovery

If an unchanged reference fails, inspect its output and baseline before changing any image.
Do not record unrelated differences to complete a matrix reduction.

## Progress and evidence

Not started. The audit verified all 29 reference identities and identified the retained coverage.

## Resume point

After step 01, apply the first snapshot selection changes.
