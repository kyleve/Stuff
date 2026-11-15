# 01 — Content width

- Status: executing
- Depends on: None
- Shared context: [Overview](README.md)

## Deliverable

Implement R-01 through R-04 for US-01 and US-02. Preserve exclusions X-01 through X-03 in the overview.
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

## Steps

1. Add the width policy, private root modifier, stylesheet style, usage documentation, and focused hosted coverage. Verify and commit this groundwork.
2. Apply the modifier to the selected screen content and Timeline ribbon. Extend calendar and snapshot coverage, verify, and commit the rollout.

## Acceptance and verification

- Verify 600-point, 900-point, and fluid layouts in narrow and wide containers.
- Verify inherited and nested policies, sibling isolation, and policy changes with retained state.
- Verify centered Calendar tile positions, zoom, forecast anchors, and resize restoration.
- Verify landscape iPad, Duo, narrow iPhone, large text, and both themes through production screen snapshots.
- Run `./test WhereUITests WhereUISnapshotTests --review` from the repository root.
- Inspect changed images before recording intentional updates. Run a separate `--record never` assertion pass.
- Run `./swiftformat --lint` and `./sf-symbols --lint`.
- Review the complete branch diff, push, open the PR, and publish representative screen snapshots through github-workflow.

## Recovery

Retain the branch and completed commits. Rebuild after source changes. Reuse test products only when they contain the current source.
Record only the intended snapshot changes after visual review.

## Progress

- [x] Implement and verify the modifier groundwork.
- [ ] Integrate and verify the main screens.
- [ ] Review and publish the completed work.

## Execution record

- 2026-11-15: Confirmed a clean checkout and Xcode 27.2. Created `codex/content-width` from the reviewed source revision.
- 2026-11-15: Added both modifiers, inherited width policies, stylesheet limits, hosted layout coverage, and usage documentation.
- The first build found a private nested observable test type that its generated extension could not access. File scope access corrected the test fixture.
- `./test --no-generate --only WhereUITests/WhereContentRootTests --only WhereUITests/WhereStylesheetTests --only SnapshotKitTestingTests/SnapshotImageRenderingTests` passed 53 tests. Architecture and default host checks passed.
- `./swiftformat --lint` and `./sf-symbols --lint` passed. The symbol check first found six pre-existing raw symbols in `SnapshotImageRenderingTests`. Typed replacements use its existing SFSafeSymbols dependency and preserve the icons. This repair has a separate prerequisite commit.
- Groundwork review found no remaining actionable issue. The hosted test verifies inherited, overridden, fluid, and narrow widths while retaining the same scroll view and offset. Screen integration and image verification remain pending.

## Resume point

Apply the modifiers to the selected screens and extend rendering and Calendar interaction coverage.

## Outcome

In progress.
