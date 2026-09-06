# SnapshotKitTesting

SnapshotKitTesting is the test-only half of the snapshot-testing framework: the
capture + comparison pipeline and the `assertSnapshots` runner that renders a
[`SnapshotKit`](../SnapshotKit) `SnapshotConfiguration` matrix into reference
images.

It links the snapshot-comparison engine
([swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing))
and AccessibilitySnapshot's parser plus SwiftUI annotation renderer
([AccessibilitySnapshot](https://github.com/cashapp/AccessibilitySnapshot)), so
it is **only** linked by `*SnapshotTests` bundles — never a shipping app. It
re-exports `SnapshotKit` and `SnapshotTesting`, so a test author needs a single
`import SnapshotKitTesting`.

## What's in the box

- **`assertSnapshots(of:)`** — the matrix runner: given a `SnapshotProviding`
  type (or an inline view + configurations), it expands `snapshots × configurations`,
  maps each `SnapshotConfiguration` to a frame size + `UITraitCollection`, renders
  through the pipeline, and asserts each against a reference image named by the
  config's `identifier`. It fails fast — with one clear issue, asserting
  nothing — when the live simulator doesn't match the scheme's
  `SNAPSHOT_EXPECTED_*` pins or when two variants would collide on one
  reference name.
- **The rendering pipeline** — an async `renderSnapshotImage(...)` that renders
  any view at any size on a single fixed simulator: safe-area-inset overriding
  (zero by default. a frame's `safeAreaInsets`, e.g. `.iPhoneNotched`,
  simulates device chrome), animation quiescing, text-cursor hiding, and a
  size-stabilization pass for SwiftUI hosting controllers. Full-content captures
  use a full-width scroll descendant's content size plus surrounding chrome when
  UIKit-backed SwiftUI containers such as `Form` report only their viewport
  through `sizeThatFits`. device presets retain their normal viewport height as
  the minimum. Height measurement iterates to a stable fixed point for lazy
  content. if it cannot converge within the bounded pass budget, capture throws,
  the assertion records a test issue, and no arbitrary image is compared or
  recorded. Captures serialize process-wide through an internal FIFO mutex — 
  the pipeline holds
  process-global state (the safe-area swizzle, the animations flag, the one
  host window) across its suspensions, so a concurrent call queues behind the
  in-flight capture instead of corrupting it. A case's
  `SnapshotSettle` picks the settle phase: `.settled` (default) waits for
  pixel-stable renders, which gives `.task`-driven content time to load but
  cannot certify that it did — a loading placeholder is pixel-stable too, so a
  case whose final content arrives asynchronously has to be made deterministic
  (seed the fixture so the first frame is final, or gate on
  `onReadyToSnapshot`). 
  `.settledAtLeast(minDuration:)` raises the loop's minimum window for async
  appearance work that starts quiet and lands after the default floor (the
  iOS 26 glass toolbar/tab bar material adaptation). `.immediate` skips the
  loop for content that's fully renderable after a layout pass. Intrinsic and
  full-content cases can independently set `measurementReadiness: .immediate`
  when their fixture's height is synchronous: only the sizing probe skips its
  settle, while the final capture still pays the case's declared `settle` and
  can observe async visual changes. Keep the default `.sameAsCapture` when an
  async load can change ideal height. Such a case may instead provide
  `onReadyToMeasure`, which runs while the intrinsic probe is hosted and laid
  out, before its settle and size resolution. The hook must cooperate with
  cancellation, is bounded by the effective settle ceiling, and is rejected
  for fixed sizing. A case's
  optional `onReadyToSnapshot` hook runs after that settle and before the
  accessibility parse / capture — the deterministic point to focus a field or
  trigger a presented state — and its effects are settled again before the
  image is taken. Content **observed** still moving at the budget **fails the
  test** rather than capturing an arbitrary frame: the failure names the
  capture and the phase, and points at freezing the motion behind
  `\.isCapturingSnapshot` or raising the floor with `.settledAtLeast`. The
  budget bounds observed motion only — a loop that never saw the content
  change but couldn't complete enough render passes to prove stability (a
  starved CI machine) keeps waiting instead of failing falsely, giving up at a
  hard cap several budgets out.
  Explicit two-axis full-content captures resolve one viewport-filling scroll
  view's width and height together, iterate both dimensions to a fixed point,
  and reset that viewport to its leading/top edge. The pipeline rejects a
  capture before allocation if either rendered dimension exceeds 32,000 pixels
  or the complete image exceeds 100 million pixels.
- **Accessibility captures** — for `.accessibility` configurations, content is
  wrapped in AccessibilitySnapshot's SwiftUI renderer so the image is annotated
  with the VoiceOver reading order, labels, traits, and activation points.
  AccessibilitySnapshot temporarily moves the content while it renders. A case
  that uses `.settledAtLeast` discards the first accessibility render, applies
  its settle policy, and parses again. This prevents a transient native-material
  frame from becoming the reference image. Other settle policies parse once.
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
struct MyBadgeSnapshotTests {
    @Test func variants() { assertSnapshots(of: MyBadge.self) }
}
```

No `@Suite(.snapshots(...))` trait is needed: `assertSnapshots` resolves the
record mode itself (see [Recording](#recording)), so a plain suite is enough — 
though a trait still takes effect if you add one.
Reference images are written next to the test file under `__Snapshots__/` and
are stored in Git LFS (see the root `.gitattributes`). Recording a new image is
a failure by design, so a run that records can't be mistaken for a pass.

## Recording

`assertSnapshots` defaults to the `.missing` mode (records only images that
don't exist yet. an existing-image mismatch always fails). To re-record without
editing source:

```bash
./test --snapshots --record failed
```

That forwards `SNAPSHOT_RECORD` into the test process — xcodebuild passes any
`TEST_RUNNER_`-prefixed variable through, which is why the pipeline reads the
unprefixed name.

Values map onto `SnapshotTestingConfiguration.Record`: `all` (rewrite
everything), `failed` (rewrite only failing comparisons — the usual re-record
mode after an intentional UI change), `missing` (only absent references), and
`never` (record nothing. missing references fail — CI-style). Precedence: an
explicit `record:` argument to `assertSnapshots` wins, then `SNAPSHOT_RECORD`,
then a `.snapshots(record:)` suite trait, then swift-snapshot-testing's own
`SNAPSHOT_TESTING_RECORD`, then `.missing`. Review the recorded images, then
commit.

## Diffing failures

`./test --snapshots --review` describes every capture that didn't match its
reference byte for byte: how many pixels differ, what fraction of the image that
is, the largest single-channel delta, and the bounding box of the change. Read
the **max delta** first — it is what separates a broken render from
sub-visible drift, and pixel count does not. The worst genuine defect found so
far touched fewer pixels than the noisiest harmless difference in the suite.
The review path uses the comparison library's filename sanitization, so case
names with spaces or punctuation resolve to their committed reference images.

Failure messages also print the reference and failed-capture file URLs. To get a
ready-to-run [Kaleidoscope](https://kaleidoscope.app) command instead, forward
`SNAPSHOT_DIFF_TOOL=ksdiff` into the test process
(`TEST_RUNNER_SNAPSHOT_DIFF_TOOL=ksdiff`). Absent or unknown values keep the
default plain output.

## Where a capture's time goes

`./test --snapshots --timings` sets `SNAPSHOT_TIMING` and prints a per-phase
breakdown — `settle`, `tileStitch`, `compare`, `pngRoundTrip`, `host`,
`accessibilityParse`, `hook`, `measurementHook`, `intrinsicMeasure`, `drain` — plus the settle pass
distribution, sizing/readiness/capture-settle metadata, and the slowest
individual captures. Reach for it before optimizing
anything here: it is what showed that `drainInFlightAnimations` was burning a
flat second on every image, and that the settle *floor* rather than its render
passes is what the remaining time buys.

`SNAPSHOT_SETTLE` selects the stability mechanism (`pixel`, `quiescence`,
`both`). see [`AGENTS.md`](AGENTS.md) for why `pixel` is the only safe default.

`SNAPSHOT_SETTLE_TIMEOUT_MULTIPLIER` scales the maximum observed-motion and
readiness-hook ceilings from 1× through 4×. It does not change minimum floors,
the quiet-window proof, render cadence, or image tolerances, so stable captures
finish at the same point. Local runs leave it unset (1×). snapshot CI explicitly
uses 2×. `./test` forwards it into the hosted test process.

## Requirements

- Runs in a hosted test bundle (needs a host app window. in this repo that's
  `StuffTestHost`, reached via `TestHostSupport`).
- Device/OS-pinned: reference images are captured on a fixed simulator (this
  repo's CI uses iPhone 17 / iOS 27.0).
- Timezone-pinned: references bake wall-clock dates/times into pixels, so the
  snapshot scheme pins `TZ` (and the runner verifies it via
  `SNAPSHOT_EXPECTED_TIMEZONE`) — see `testScheme` in `Project.swift`.
