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
  size-stabilization pass for SwiftUI hosting controllers.
- **Accessibility captures** — for `.accessibility` configurations, content is
  wrapped so the image is annotated with the VoiceOver reading order, labels,
  traits, and activation points.

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
a failure by design, so a run that records can't be mistaken for a pass — record
with the suite trait `@Suite(.snapshots(record: .missing))` (or `.all` to
refresh), review the images, then commit.

## Requirements

- Runs in a hosted test bundle (needs a host app window; in this repo that's
  `StuffTestHost`, reached via `TestHostSupport`).
- Device/OS-pinned: reference images are captured on a fixed simulator (this
  repo's CI uses iPhone 17 / iOS 26.2).
