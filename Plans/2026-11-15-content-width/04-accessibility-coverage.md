# 04 — Restore accessibility annotation coverage

- Status: executing
- Depends on: [03 — Main integration](03-main-integration.md)
- Shared context: [Overview](README.md)
- Issue: [STU-331](https://linear.app/kve/issue/STU-331/center-main-screen-content-with-inherited-width-policies)

## Scope and decision

On 2026-11-16, the user requested retaining the accessibility snapshots removed by the additional coverage reduction.
Commit `9d5ab08b9` removed five iPad accessibility-annotation configurations from this PR.
Restore those configurations and their original references from `cdbdf62cf` for Appearance, Settings, Widgets, onboarding, and theme selection.
The five suites will retain 58 captures, including phone and iPad annotations.
Their other selections and production rendering remain unchanged.

This corrects plan 03's coverage choice. Its execution history remains accurate.
No new layout, renderer, or helper is required, so an architecture diagram does not apply.

## Contracts and verification

- SnapshotKit owns configuration identity and frame semantics. Restore the original names and frames; onboarding retains its fixed viewport.
- Each screen owns its colocated matrix. Restore `.accessibility` selection as well as its PNG, so CI executes the restored coverage.
- Preserve the existing 53 references byte-for-byte. Compare the five restored files with their pre-deletion hashes.
- Run all five affected image suites with `--record never`, and the Flyover catalog checks. Inspect the restored annotations and review the diff before publication.

## Progress

- [x] Restore and verify all five annotation captures.
- [ ] Review, commit, and push the correction.
- [ ] Update PR/issue evidence and complete this record.

## Verification and review

- All 58 image captures passed with recording disabled: Appearance 9, Settings 17, Widgets 9, onboarding 11, and theme selection 12. The capture log includes all five restored annotation identities and all 53 retained identities.
- Both Flyover catalog tests passed. All five restored PNG hashes match `cdbdf62cf`; all 53 retained references remain byte-identical.
- `./swiftformat --lint`, `./sf-symbols --lint`, architecture checks, and default host checks passed.
- Independent reviewer `merge_coverage_review` reviewed the five configurations, all five annotation images, original hashes, and plan updates against `af8199887`. No actionable findings remain. Case names, reference groups, frame semantics, theme states, AX5/RTL choices, and preview/Flyover identities are preserved.
- Production UI and capture infrastructure are unchanged. The original phone annotation captures remain selected alongside the restored iPad cases.

Command (Xcode 27.2):

```sh
./test --no-generate --only WhereUITests/WhereFlyoverCatalogTests \
  --only WhereUISnapshotTests/AppearanceSettingsViewSnapshotTests \
  --only WhereUISnapshotTests/SettingsViewSnapshotTests \
  --only WhereUISnapshotTests/WidgetFeaturesViewSnapshotTests \
  --only WhereUISnapshotTests/OnboardingViewSnapshotTests \
  --only WhereUISnapshotTests/OnboardingThemeSelectionViewSnapshotTests \
  --record never --review --timings
```

## Resume point

Verification and independent review are complete. Commit and push the correction, then update PR and issue evidence.
