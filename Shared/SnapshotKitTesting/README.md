# SnapshotKitTesting

SnapshotKitTesting is the test-only half of the snapshot-testing framework: the
capture + comparison pipeline and the `assertSnapshots` runner that renders a
[`SnapshotKit`](../SnapshotKit) `SnapshotConfiguration` matrix into reference
images.

It links the snapshot-comparison engine
([swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing))
and the accessibility parser
([AccessibilitySnapshot](https://github.com/cashapp/AccessibilitySnapshot)), so
it is **only** linked by `*SnapshotTests` bundles — never a shipping app. It
re-exports `SnapshotKit` and `SnapshotTesting`, so a test author needs a single
`import SnapshotKitTesting`.

## What's in the box

- **`assertSnapshots(of:)`** — the matrix runner: given a `SnapshotProviding`
  type (or an inline view + configurations), it expands `snapshots × configurations`,
  maps each `SnapshotConfiguration` to a frame size + `UITraitCollection`, renders
  through the pipeline, and asserts each against a reference image named by the
  config's `identifier`.
- **The rendering pipeline** — a custom `Snapshotting<UIViewController, UIImage>`
  strategy that renders any view at any size on a single fixed simulator:
  safe-area-inset overriding, animation quiescing, text-cursor hiding, and a
  size-stabilization pass for SwiftUI hosting controllers. A case's
  `SnapshotSettle` picks the settle phase: `.settled` (default) waits for
  pixel-stable renders so `.task`-driven content loads; `.immediate` skips the
  loop for content that's fully renderable after a layout pass. A case's
  optional `onReadyToSnapshot` hook runs after that settle and before the
  accessibility parse / capture — the deterministic point to focus a field or
  trigger a presented state — and its effects are settled again before the
  image is taken.
- **Accessibility captures** — for `.accessibility` configurations, content is
  wrapped so the image is annotated with the VoiceOver reading order, labels,
  traits, and activation points.
- **`\.isCapturingSnapshot`** — the pipeline overrides `SnapshotCaptureTrait`
  on every captured controller, so SwiftUI content reads the SnapshotKit
  environment flag as `true` and can freeze never-settling motion
  (`repeatForever`, `TimelineView(.animation)`) at a deterministic phase. See
  the contract on the property in `SnapshotKit`.

## Quick start

```swift
import SnapshotKitTesting
import Testing

@MainActor
@Suite(.snapshots(record: .missing))
struct MyBadgeSnapshotTests {
    @Test func variants() { assertSnapshots(of: MyBadge.self) }
}
```

Reference images are written next to the test file under `__Snapshots__/` and
are stored in Git LFS (see the root `.gitattributes`). Recording a new image is
a failure by design, so a run that records can't be mistaken for a pass.

## Recording

The suite trait sets the baseline mode (`@Suite(.snapshots(record: .missing))`
records only images that don't exist yet). To re-record without editing source,
forward a `SNAPSHOT_RECORD` environment variable into the test process —
xcodebuild passes any `TEST_RUNNER_`-prefixed variable through, so in this repo
(verified working):

```bash
TEST_RUNNER_SNAPSHOT_RECORD=failed mise exec -- tuist test WhereUISnapshotTests \
  --no-selective-testing -- \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
```

Values map onto `SnapshotTestingConfiguration.Record`: `all` (rewrite
everything), `failed` (rewrite only failing comparisons — the usual re-record
mode after an intentional UI change), `missing` (only absent references), and
`never` (record nothing; missing references fail — CI-style). Precedence: an
explicit `record:` argument to `assertSnapshots` wins, then `SNAPSHOT_RECORD`,
then the suite trait. Review the recorded images, then commit.

## Diffing failures

Failure messages print the reference and failed-capture file URLs by default.
To get a ready-to-run [Kaleidoscope](https://kaleidoscope.app) command instead,
forward `SNAPSHOT_DIFF_TOOL=ksdiff` the same way
(`TEST_RUNNER_SNAPSHOT_DIFF_TOOL=ksdiff mise exec -- tuist test …`). Absent or
unknown values keep the default plain output.

## Requirements

- Runs in a hosted test bundle (needs a host app window; in this repo that's
  `StuffTestHost`, reached via `TestHostSupport`).
- Device/OS-pinned: reference images are captured on a fixed simulator (this
  repo's CI uses iPhone 17 / iOS 26.2).
