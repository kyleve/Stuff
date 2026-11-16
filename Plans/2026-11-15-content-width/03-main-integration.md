# 03 — Main integration and focused coverage

- Status: complete
- Depends on: [02 — Screen roots](02-screen-roots.md)
- Shared context: [Overview](README.md)
- Issue: [STU-331](https://linear.app/kve/issue/STU-331/center-main-screen-content-with-inherited-width-policies)

## Scope and evidence

The user requested merging main and reconsidering snapshot coverage.
The branch started at `efe70da7e`; fetched main is `6676b36bc`, including PRs #505 and #507.
Those changes narrow coverage requirements and remove redundant tests and image variants.
Repository source and the updated coverage policy provide the required evidence. Product behavior and the width API remain unchanged.

## Contracts and guards

| Contract | Owner and retained guard |
| --- | --- |
| Width inheritance, nesting fallback, safe-area gutters, and scroll identity remain correct. | Shared presentation contract; hosted content/form/screen-root suites |
| Calendar zoom, pinned Timeline content, and adaptive panes keep their measurement and navigation owners. | Primary/Year contracts; calendar and adaptive hosted tests, existing integration images |
| Test coverage represents distinct behavior rather than copied token constants or repeated appearance axes. | Swift conventions, SnapshotKit, and Broadway coverage guidance |
| Retained image identities and preview/Flyover states remain stable. | SnapshotKit contract; retained-file accounting, recording-disabled assertions, and catalog tests |

## Steps and verification

1. Resolve main's snapshot deletions and streamlined guidance without restoring removed coverage. Remove the branch's redundant literal-token test. Regenerate, run the WhereUI unit bundle and eight intersecting image suites, then commit and push the merge.
2. Narrow five declarations. Appearance, Settings, and Widgets retain phone traits and one iPad baseline. Onboarding and theme selection also retain iPad AX5 for constrained wrapping and footer/picker layout. Preserve theme-selection states, RTL frames, and specialized main-screen coverage. Remove only the 18 unselected references; run the five image suites with recording disabled and verify catalog identities.
3. Review the resulting diff independently. Refresh PR and issue evidence, record counts and validation limits, then commit and push completed work.

No product API, persistence, or dependency changes are introduced by this follow-up.
Coverage reductions preserve retained rendering and reference bytes. The integration run exposed one previously unverified width change in an existing reference.

## Review and progress

- Reviewed scope against branch `efe70da7e` and main `6676b36bc`. The merge has 31 modified/deleted image conflicts and one guidance conflict.
- Preserved all main image deletions and retained the content-root invariant in the shorter shared guidance.
- Independent reviewer: `merge_coverage_review`, covering integration and the complete branch diff against main.
- [x] Verify, commit, and push the main merge: `cdbdf62cf754bb2cbe0f0af1289e4344f6a33bb6`.
- [x] Reduce and verify redundant image axes: 18 removed, 53 retained and asserted.
- [x] Publish final review evidence and complete the record: PR #506 and STU-331 updated.

## Integration findings

- The initial run executed 684 WhereUI tests and 167 image captures. One native safe-area test and one Settings shell image failed.
- Main's updated Locations readiness test left the content controller's inset stale after a synthetic host inset change. Top anchoring remained correct. A 40-transition probe failed at both normal and accelerated animation speeds. Driving the embedded navigation controller's public layout pass made all 40 transitions pass. The final test retains its original four changes, readiness predicates, selection isolation, and pane-replacement restoration checks.
- The retained Duo Settings AX5 capture now shows the intended 600-point row column with full-width search and navigation chrome. Both reviewers approved that existing reference update. It covers shell integration outside plan 02's selected screen suites; the case remains selected.

## Verification

- `./ide --no-open` regenerated the test graph after main's test deletions.
- `./swiftformat --lint`, `./sf-symbols --lint`, `./sync-agents --check`, architecture checks, and default host checks passed.
- After the native-layout correction, the complete `WhereUITests` bundle passed: 684 tests in 150 suites. The confirmation command also reviewed and recorded the single expected MainTabs reference with `--record failed`.
- Initial image integration selected About, Data, Devices, License, Regions, MainTabs, Year, and Locations: 167 captures across eight suites. All except the reviewed Settings reference passed. MainTabs is rerun with recording disabled after that update.
- The five narrowed suites retain 53 references from 71. Their bytes match the pre-reduction files. Removed variants are iPad dark, contrast, and accessibility annotations for all five screens, plus iPad AX5 for Appearance, Settings, and Widgets. Onboarding keeps its fixed-frame devices; theme selection keeps both RTL frames and alternate theme states.
- Final recording-disabled run passed two Flyover catalog tests and 114 captures in six suites: MainTabs 61, Appearance 8, Settings 16, Widgets 8, onboarding 10, and theme selection 11. Every retained reduction reference was executed. Combined with the unchanged seven integration suites, verification covers 220 distinct references across 13 suites.
- Independent review covered the full Swift diff against main, the native-test correction, the five selections, all 18 removals, and the updated Settings capture. No actionable findings remain. All 53 retained reduction PNGs are byte-identical; the updated Settings reference matches its reviewed capture (SHA-256 `c83a7b5640869a922ffc653eda754201aed30415d73c0173a08671d802d427c1`).

Commands (Xcode 27.2):

```sh
./test --no-generate --only WhereUITests \
  --only WhereUISnapshotTests/AboutSettingsViewSnapshotTests \
  --only WhereUISnapshotTests/DataSettingsViewSnapshotTests \
  --only WhereUISnapshotTests/DevicesSettingsViewSnapshotTests \
  --only WhereUISnapshotTests/LicenseViewSnapshotTests \
  --only WhereUISnapshotTests/RegionsSettingsViewSnapshotTests \
  --only WhereUISnapshotTests/MainTabsSnapshotTests \
  --only WhereUISnapshotTests/YearViewSnapshotTests \
  --only WhereUISnapshotTests/LocationsViewSnapshotTests \
  --record never --review --timings

./test --no-generate --only WhereUITests \
  --only WhereUISnapshotTests/MainTabsSnapshotTests \
  --record failed --review --timings

./test --no-generate --only WhereUITests/WhereFlyoverCatalogTests \
  --only WhereUISnapshotTests/MainTabsSnapshotTests \
  --only WhereUISnapshotTests/AppearanceSettingsViewSnapshotTests \
  --only WhereUISnapshotTests/SettingsViewSnapshotTests \
  --only WhereUISnapshotTests/WidgetFeaturesViewSnapshotTests \
  --only WhereUISnapshotTests/OnboardingViewSnapshotTests \
  --only WhereUISnapshotTests/OnboardingThemeSelectionViewSnapshotTests \
  --record never --review --timings
```

The first command exposed the two integration issues recorded above. The second passed all unit tests and recorded the reviewed reference; recording intentionally reports that update as a failed comparison. The third passed with recording disabled. Temporary 40-transition probes were removed; the final test retains its original four-transition sequence.

## Delivery

- Merge: `cdbdf62cf754bb2cbe0f0af1289e4344f6a33bb6`, with main `6676b36bc` as its second parent.
- Coverage reduction and final source: `9d5ab08b9c69d8fbb369db9a4e7ff3f2f9995c61`.
- Both commits are pushed to [PR #506](https://github.com/kyleve/Stuff/pull/506), ready for review. Its body, the existing API reply, and the existing Settings snapshot comment contain current evidence. The [native-layout review note](https://github.com/kyleve/Stuff/pull/506#discussion_r4581569416) records the integration finding.
- Verified the published body, rendered image markup, all 24 retained screen comments, existing human-thread replies, and four published image hashes. Browser UI verification was unavailable; GitHub API HTML and image bytes provided publication evidence.
- STU-331 was updated and remains In Review. CI is asynchronous; local verification is complete. Plan 02's physical-device and optimized-build validation limits remain.

## Resume point

Implementation, review, and publication are complete. Await PR review; the linked issue stays In Review until merge and acceptance verification.
