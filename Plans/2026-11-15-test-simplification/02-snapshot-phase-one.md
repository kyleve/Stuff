# 02 — Snapshot phase one

- Status: complete
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

- Narrowed the five affected suites at their existing declarations.
- Kept all MainTabs preview state names through `PreviewScenarios`, including FlatElsewhere and equivalent fold poses.
- Removed the dark Inspector quarantine without claiming that STU-20's rendering defect is fixed.
- Verified the exact 29 deletions and unchanged bytes for all 137 retained references in the affected suites.
- Independent review found two preview-only issues: capture hooks did not load Elsewhere in previews, and repeated capture case names collided in the preview cutsheet.
  The preview provider now emits 35 unique cases and loads Elsewhere from its mounted task. The follow-up source review found no remaining issue.
  SnapshotKit's contract now states both preview requirements.
- Swift formatting, diff whitespace, and the 71-suite shard inventory checks passed.
- The five selected snapshot suites passed with `--record never --timings`: 8 test declarations and 137 reference captures.
  The loading/failed Locations navigation-bar and inset probe also passed.
  Log: `/private/tmp/stuff-test-reduction-phase-one.log`; full output and timing identities were retained alongside it.
- After the preview correction, a fresh build passed 15 tests across `MainTabsTests`, `MainTabsTestsDuo`, `YearViewTests`,
  `LocationsViewTests`, `LocationsViewTestsDuo`, `WhereFlyoverCatalogTests`, and `WhereFlyoverDataTests`.
  The final MainTabs assertion run also passed all 61 references with unchanged images.
  Command: `./test --no-generate --record never --timings`, with repeated `--only` for those seven unit suites and `WhereUISnapshotTests/MainTabsSnapshotTests`.
  Log: `/private/tmp/stuff-test-reduction-phase-one-final.log`.
- Timing identities match every remaining reference in the five changed suites, including the repeated final MainTabs run.
- Xcode preview rendering was not exercised. Preview identity and readiness changes received source review and compiled in the test build.
- Published as `d36763ed8` in [PR #505](https://github.com/kyleve/Stuff/pull/505).
  STU-20 now records the removal while retaining its unresolved renderer status and historical evidence.

## Resume point

Complete. Continue with [03](03-snapshot-phase-two.md).
