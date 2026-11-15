# 01 — Content width

- Status: executing
- Depends on: None
- Shared context: [Overview](README.md)

## Deliverable

Implement R-01 through R-05 for US-01 and US-02. Preserve exclusions X-01 through X-03 in the overview.
The main scrolling content defaults to a centered 600-point column, with inherited wide and fluid overrides available to callers.

## Contracts and existing guards

| Contract | Owner | Guard |
| --- | --- | --- |
| Authored dimensions belong to the stylesheet. | WhereUI shared presentation contract | `WhereStylesheetTests` |
| Navigation state stays above adaptive branches. | WhereUI Primary contract | `LocationsViewTestsDuo`, `YearViewTests` |
| Calendar targets and transition measurements preserve scroll state. | WhereUI Year contract | `CalendarContentViewTests`, `CalendarZoomTransitionStateTests` |
| Eager content measurement supplies actual calendar and Timeline heights. | WhereUI Year contract | Calendar and Timeline snapshot suites |
| Screen matrices use production fixtures and explicit readiness. | SnapshotKit and WhereUI test contracts | `WhereUISnapshotTests` |

Applicable guidance: root and Where contracts, WhereUI Shared/Primary/Year/test contracts, building-ui, swiftui-pro, running-tests, and swift-testing-pro.
Documentation follows the repository documentation contract and simple-english.

## Architecture sketch

```swift
// Proposed internal interfaces. Existing navigation and scroll views remain owners.
enum WhereContentWidth { case regular, wide, fluid }
extension View {
    func whereContentWidth(_ width: WhereContentWidth) -> some View
    func whereContentRoot() -> some View
}
```

The width modifier writes an environment value. The root modifier reads that value and resolves the limit from `WhereStylesheet.contentRoot`.
An inner frame accepts the available width up to the limit. An outer frame fills the available width and centers the inner frame.
The environment changes no model, persistence, asynchronous operation, or lifetime ownership. A separate data-flow diagram is unnecessary for these two view modifiers.
The outer root marks its descendants through a private environment value. An inner root asserts in debug and passes through in release.

## Steps

1. Add the width policy, private root modifier, stylesheet style, usage documentation, and focused hosted coverage. Verify and commit this groundwork.
2. Apply the modifier to the selected screen content and Timeline ribbon. Extend calendar and snapshot coverage, verify, and commit the rollout.

## Acceptance and verification

- Verify 600-point, 900-point, and fluid layouts in narrow and wide containers.
- Verify inherited and nested policies, sibling isolation, and policy changes with retained state.
- Verify centered Calendar tile positions, zoom, forecast anchors, and resize restoration.
- Verify landscape iPad, Duo, narrow iPhone, large text, and both themes through production screen snapshots.
- Run the complete `WhereUITests` bundle and the affected image suites through `./test --review`.
  Image coverage includes Calendar, Elsewhere, Locations, Timeline, Year, MainTabs, RootView, DeviceLayoutLab, EstimatedTimeFeatures, and PlacesYearFeatures.
- Inspect changed images before recording intentional updates. Run a separate `--record never` assertion pass.
- Run `./swiftformat --lint` and `./sf-symbols --lint`.
- Review the complete branch diff, push, open the PR, and publish representative screen snapshots through github-workflow.

The final assertion selection is:

```sh
./test --no-generate --only WhereUITests \
  --only WhereUISnapshotTests/CalendarContentViewSnapshotTests \
  --only WhereUISnapshotTests/DeviceLayoutLabViewSnapshotTests \
  --only WhereUISnapshotTests/ElsewhereViewSnapshotTests \
  --only WhereUISnapshotTests/LocationsViewSnapshotTests \
  --only WhereUISnapshotTests/MainTabsSnapshotTests \
  --only WhereUISnapshotTests/PresenceTimelineListSnapshotTests \
  --only WhereUISnapshotTests/YearViewSnapshotTests \
  --only WhereUISnapshotTests/RootViewSnapshotTests \
  --only WhereUISnapshotTests/EstimatedTimeFeaturesViewSnapshotTests \
  --only WhereUISnapshotTests/PlacesYearFeaturesViewSnapshotTests \
  --record never --review --timings
```

## Recovery

Retain the branch and completed commits. Rebuild after source changes. Reuse test products only when they contain the current source.
Record only the intended snapshot changes after visual review.

## Progress

- [x] Implement and verify the modifier groundwork.
- [x] Integrate and verify the main screens.
- [ ] Review and publish the completed work.

## Execution record

- 2026-11-15: Confirmed a clean checkout and Xcode 27.2. Created `codex/content-width` from the reviewed source revision.
- 2026-11-15: Added both modifiers, inherited width policies, stylesheet limits, hosted layout coverage, and usage documentation.
- The first build found a private nested observable test type that its generated extension could not access. File scope access corrected the test fixture.
- `./test --no-generate --only WhereUITests/WhereContentRootTests --only WhereUITests/WhereStylesheetTests --only SnapshotKitTestingTests/SnapshotImageRenderingTests` passed 53 tests. Architecture and default host checks passed.
- `./swiftformat --lint` and `./sf-symbols --lint` passed. The symbol check first found six pre-existing raw symbols in `SnapshotImageRenderingTests`. Typed replacements use its existing SFSafeSymbols dependency and preserve the icons. This repair has a separate prerequisite commit.
- Groundwork review found no remaining actionable issue. The hosted test verifies inherited, overridden, fluid, and narrow widths while retaining the same scroll view and offset. Screen integration and image verification remain pending.
- The first broad rollout run completed 715 Swift Testing tests with two failures in the Flyover catalog. New snapshot names collided across themes and configurations. Unique case names correct those failures. The old snapshot run was interrupted after this source change, before reference review.
- The user added R-05 during implementation. The modifier now marks its descendants, asserts on nesting in debug, and passes inner content through in release. Sibling roots and width overrides retain their behavior.
- The Calendar test now compares its overlay measurement with the rendered month's horizontal frame. This directly guards the full-width content anchor.
- The rebuilt run selects all WhereUI unit tests and the ten affected image suites. This covers changed screens, their composition owners, and the unchanged Timeline excerpts without rerunning unrelated screen images.
- A fresh independent review covered the complete diff from `2193072f6` through `5da5c805f` plus the uncommitted rollout. It found no actionable source issue. Nesting behavior has source review; a debug trap and optimized release fallback were not exercised directly.
- The rebuilt complete WhereUI run passed 715 tests in 153 suites. The ten affected image suites completed 14 tests. They identified 18 new references and 73 differing existing references.
- Visual review confirmed the intended wide columns, both themes, full-width backgrounds and chrome, and aligned Timeline ribbons. It also found a one-pixel vertical shift in several narrow Locations captures. Pixel comparison isolated the shift to one card. A top-alignment experiment did not remove it and was reverted. A controlled comparison with the previous Locations and Timeline source is running before reference updates.
- The user accepted one-pixel SwiftUI rounding differences. The baseline comparison was stopped, its temporary source changes were restored, and the original two-frame modifier was retained. Reference updates include the reviewed rounding differences.
- The record pass updated exactly the 73 reviewed existing references. The 18 new references were also reviewed. Main then advanced to `ff3f9ec8` with Device Layout Lab appearance coverage. Its disjoint changes merged without conflicts before the final assertion pass. The new dark landscape reference requires the same width update.
- The merged Lab check found only the expected dark landscape reference failure. Its before/after image shows the centered Calendar column with full-width chrome and background. Independent review against `ff3f9ec8` found no logical integration issue.
- The integrated revision passed all 717 WhereUI tests. Final Swift formatting, typed-symbol lint, architecture, and host checks passed. The final image assertion pass uses recording disabled.
- Final assertions passed on Xcode 27.2: 717 tests in 153 WhereUI suites, plus 14 image tests in 10 suites covering 325 captures. Recording was disabled. The final image set adds 18 landscape captures and updates 74 existing references, including the merged dark Lab capture.

## Resume point

All source and reference updates passed verification. Commit the rollout and pending main integration, push, open the PR, add screen snapshot comments, and record publication.

## Outcome

Implementation verified. Publication pending.
