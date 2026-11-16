# 02 — Screen roots and broader adoption

- Status: executing
- Depends on: [01 — Content width](01-content-width.md)
- Shared context: [Overview](README.md)
- Issue: [STU-331](https://linear.app/kve/issue/STU-331/center-main-screen-content-with-inherited-width-policies)

## Scope and authorization

The user approved the review recommendations after PR #506 feedback.
This follow-up removes redundant image matrices, adds screen conveniences, and extends the width policy to Settings, Explore Features, and onboarding.
The first plan remains the historical record of the initial rollout.

## Contracts and guards

| Requirement | Owner and existing guard |
| --- | --- |
| Width and padding use stylesheet values. Omitted width inherits the ancestor policy. | Shared presentation contracts; `WhereContentRootTests`, `WhereStylesheetTests` |
| Navigation, sheets, and scroll state retain their owners and identity. | Primary contracts; hosted screen-root and native-container tests |
| Calendar anchors remain outside the constrained column. Timeline keeps its pinned ribbon. | Year contracts; `CalendarContentViewTests` and existing screen snapshots |
| Native forms and lists retain their scrolling, sections, and background. | Building UI layout guidance; hosted native-container tests and existing Settings snapshots |
| Nested screen roots add no second scroller or padding in release. New presentations can establish independent roots. | Shared root guard; focused hosted nesting and presentation coverage |
| Image coverage follows distinct layouts without a theme/device/policy product. | SnapshotKit contracts; retained-reference accounting and `WhereFlyoverCatalogTests` |

## Design

```swift
// Conveniences over the existing width policy.
content.whereScreenRoot() // Inherited width, standard padding, vertical scrolling.
content.whereScreenRoot(.wide, padding: .none)
Form { rows }.whereFormRoot() // Native container retains ownership.
```

The screen modifier composes scrolling, padding, and the existing content root.
A native-container adapter adds safe-area gutters from the same width policy and compensates scroll-indicator margins.
An optional `WhereScreen` protocol delegates its default body to the screen modifier.
Explicit presentation boundaries reset root nesting without discarding the inherited width.
These modifiers own presentation only. No services or persistence change, so a separate data-flow diagram is unnecessary.

Calendar and Timeline retain their specialized containers. Maps and media previews retain their available width.
The rollout covers Settings details, Explore Features, onboarding, region customization, and license text.
Further data editors and app-icon grid changes remain outside this follow-up.

## Steps and verification

1. Remove the four added snapshot loops, their 18 references, and their configuration helper. Verify retained captures and Flyover identities, then commit and reply.
2. Add screen-root, padding, optional protocol, and native-container support. Verify inheritance, explicit overrides, resizing, identity, nesting fallback, and presentation boundaries.
3. Adopt the helpers on the selected screens. Review changed existing images, record intentional updates, and run separate assertions with recording disabled.
4. Review the final diff independently. Update documentation, PR evidence, issue state, and each addressed review thread. Commit and push each verified step.

Verification uses `./test --no-generate` with focused hosted suites and affected image suites.
The final pass includes the complete WhereUI unit bundle, formatting, and typed-symbol lint.
No additional full-screen snapshot matrices are required.

## Verification selection

The final assertion uses these existing suites with recording disabled. No snapshot cases or configurations are added.

```sh
./test --no-generate --no-build \
  --only WhereUISnapshotTests/AboutSettingsViewSnapshotTests \
  --only WhereUISnapshotTests/AppearanceSettingsViewSnapshotTests \
  --only WhereUISnapshotTests/DataSettingsViewSnapshotTests \
  --only WhereUISnapshotTests/DevicesSettingsViewSnapshotTests \
  --only WhereUISnapshotTests/PrivacyDiagnosticsSettingsViewSnapshotTests \
  --only WhereUISnapshotTests/SettingsViewSnapshotTests \
  --only WhereUISnapshotTests/EstimatedTimeFeaturesViewSnapshotTests \
  --only WhereUISnapshotTests/InsightsAccuracyFeaturesViewSnapshotTests \
  --only WhereUISnapshotTests/PersonalizationFeaturesViewSnapshotTests \
  --only WhereUISnapshotTests/PlacesYearFeaturesViewSnapshotTests \
  --only WhereUISnapshotTests/PrivacyBackupsFeaturesViewSnapshotTests \
  --only WhereUISnapshotTests/RecordingFeaturesViewSnapshotTests \
  --only WhereUISnapshotTests/ShareEvidenceFeaturesViewSnapshotTests \
  --only WhereUISnapshotTests/SiriFeaturesViewSnapshotTests \
  --only WhereUISnapshotTests/WidgetFeaturesViewSnapshotTests \
  --only WhereUISnapshotTests/LicenseViewSnapshotTests \
  --only WhereUISnapshotTests/OnboardingViewSnapshotTests \
  --only WhereUISnapshotTests/OnboardingThemeSelectionViewSnapshotTests \
  --only WhereUISnapshotTests/RegionCustomizeViewSnapshotTests \
  --only WhereUISnapshotTests/RegionsSettingsViewSnapshotTests \
  --only WhereUISnapshotTests/CalendarContentViewSnapshotTests \
  --only WhereUISnapshotTests/ElsewhereViewSnapshotTests \
  --only WhereUISnapshotTests/LocationsViewSnapshotTests \
  --only WhereUISnapshotTests/PresenceTimelineListSnapshotTests \
  --record never --review --timings
```

## Review

- Reviewed against `d8d3c3eb5f0317c407eeff69140caad816399450` and all five human review comments on PR #506.
- The user approved implementation in this conversation.
- Hosted tests verify the native adapter and independent presentation scopes before rollout.
- Independent review covered the helpers, selected callers, presentation boundaries, and full-content measurement paths.
- Review found two native-layout defects. Explicit content margins replaced native gutters at the width cutoff. Subtracting safe-area insets from the already-reduced proposal exceeded the limit. Additive gutters and the proposed geometry width address these defects.
- Landscape onboarding at the largest text size needed a vertical scrolling path. Each intro page now scrolls independently, with bottom space to clear the page indicator. A hosted regression failed before the correction and verifies the final line remains reachable above the fixed footer.

## Progress

- [x] Remove redundant snapshot coverage.
- [x] Implement and verify shared helpers.
- [x] Adopt and verify the selected screens.
- [ ] Review, push, and reconcile PR feedback.

## Execution record

- Started from a clean `codex/content-width` checkout. PR #506 still targets `ff3f9ec8` and has no newer source revision.
- Removed exactly 18 new references, the four added loops, and their configuration helper. The retained files are unchanged.
- `./test --no-generate --only WhereUITests/WhereFlyoverCatalogTests --only WhereUISnapshotTests/CalendarContentViewSnapshotTests --only WhereUISnapshotTests/ElsewhereViewSnapshotTests --only WhereUISnapshotTests/LocationsViewSnapshotTests --only WhereUISnapshotTests/PresenceTimelineListSnapshotTests --record never --timings` passed two catalog tests and six image tests covering 183 captures. Formatting passed.
- Added screen-root, padding, protocol, native-container, and presentation-boundary helpers. Hosted coverage exercises inherited and explicit widths, padding, nesting fallback, navigation, sheets, resizing, and retained scroll identity.
- Native coverage includes Form, automatic List, plain List, and sidebar List. It checks 600/601 and 900/901 boundaries in both size classes, plus asymmetric caller safe-area padding.
- All 723 WhereUI tests in 156 suites passed with the final helpers, selected adoptions, and onboarding correction. Formatting, symbol lint, architecture checks, and default host checks passed.
- Visual review covered 52 intentional iPad updates across ten existing suites. The remaining 131 captures in the initial selection passed their existing references. The recorded PNG bytes match the reviewed captures.
- The 24-suite assertion pass covered 26 image tests and 366 captures. All passed before the final onboarding scrolling correction. After that correction, all 13 onboarding captures passed again with recording disabled. Exactly 53 existing references changed: the 52 iPad captures and one iPhone AX5 capture.
- The independent reviewer found no remaining actionable issue, including in the final onboarding source, regression test, and images. The assertion-reporter seam covers nesting fallback; the debug trap and optimized-release binary were not run directly. Scroll-indicator coverage uses UIKit insets rather than a physical-device capture.

## Resume point

Publish the verified screen adoptions, refresh PR screenshots and review replies, and reconcile the issue evidence.
