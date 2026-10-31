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
- **The rendering pipeline** — async `renderSnapshotCapture(...)` returns the
  normalized image and PNG bytes. `renderSnapshotImage(...)` wraps it for callers
  needing only the image. Native assertions, hosted PNG export, and HTML snapshots
  share this pipeline on a single fixed simulator: safe-area-inset overriding
  (zero by default. a frame's `safeAreaInsets`, e.g. `.iPhoneNotched`,
  simulates device chrome), animation quiescing, text-cursor hiding, and a
  size-stabilization pass for SwiftUI hosting controllers. Full-content captures
  use a full-width scroll descendant's content size plus surrounding chrome when
  UIKit-backed SwiftUI containers such as `Form` do not report their complete height
  through `sizeThatFits`. This fallback applies only when scroll content exceeds
  the reported intrinsic height. A fully visible short document keeps its intrinsic height.
  Device presets retain their normal viewport height as
  the minimum. After readiness, full-content captures reset the primary scroll view to the top; viewport captures preserve it. Height measurement iterates to a stable fixed point for lazy
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
  The digest permits one 8-bit color step against the quiet-window anchor to
  absorb renderer quantization noise. It keeps that anchor unchanged; any
  two-step change anywhere restarts stability. Final image tolerances are separate.
  `.settledAtLeast(minDuration:)` raises the loop's minimum window for async
  appearance work that starts quiet and lands after the default floor (the
  native glass toolbar/tab bar material adaptation). `.immediate` skips the
  loop for content that's fully renderable after a layout pass. Intrinsic and
  full-content cases can independently set `measurementReadiness: .immediate`
  when their fixture's height is synchronous: only the sizing probe skips its
  settle, while the final capture still pays the case's declared `settle` and
  can observe async visual changes. Keep the default `.sameAsCapture` when an
  async load can change ideal height. Such a case may instead provide
  `onReadyToMeasure`, which runs while the intrinsic probe is hosted and laid
  out, before its settle and size resolution. The hook must cooperate with
  cancellation and is rejected for fixed sizing. The settle ceiling bounds it
  unless the capture API supplies an explicit `measurementHookTimeout`. A case's
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

## Pixel settling

The settle loop renders samples at 0.25 pixels per point and normalizes them to 8-bit, premultiplied sRGB RGBA.
Every channel can differ from the fixed anchor by at most one unit (1/255).
This allowance covers measured render noise without using the final comparison's broader perceptual and area tolerances.

The anchor stays fixed throughout each quiet window.
A larger channel difference, changed image dimensions, or missing sample resets that window.
Two matching passes must span at least 120 ms, and the case's minimum duration still applies.
The loop retains its 16 ms suspension between passes and its existing timeout, starvation, and cancellation behavior.

The fixed anchor detects cumulative motion that exceeds one unit within the quiet window.
It cannot distinguish slower motion inside that allowance from noise, or detect detail lost at the sample resolution.
Readiness hooks and measured minimum durations remain necessary for asynchronous content and native glass adaptation.
Final reference comparisons keep their existing tolerances and use the full capture after PNG encoding and decoding.

## Quick start

```swift
import SnapshotKitTesting
import Testing

@MainActor
struct MyBadgeSnapshotTests {
    @Test func variants() async { await assertSnapshots(of: MyBadge.self) }
}
```

No `@Suite(.snapshots(...))` trait is needed: `assertSnapshots` resolves the
record mode itself (see [Recording](#recording)), so a plain suite is enough — 
though a trait still takes effect if you add one.
Reference images live beside the test file under `__Snapshots__/<test-file-name>/`.
Git LFS stores these images (see the root `.gitattributes`). The runner selects
the directory from each `SnapshotConfiguration`:

| Capture | Directory within the suite |
|---------|----------------------------|
| Ordinary light or dark image | The suite directory |
| Accessibility annotations, including combinations with other traits | The suite directory |
| Standard image with non-default Dynamic Type, increased contrast, RTL layout, or bold text | `other/` |

Device size, frame, and custom names do not change the directory.
Filenames retain the test function and configuration identifier.
[`snapshotReferenceURL`](Sources/SnapshotReferenceURL.swift) supplies the same
location to recording, comparison, and review reports.
Recording a new image fails the test, so a recording run cannot count as a pass.

## Hosted PNG capture

`captureSnapshotPNG` uses the same hosted renderer without comparing a
reference image. It accepts the view, configuration, name, sizing strategy,
safe-area insets, readiness hooks, and settle policy. The returned
`SnapshotPNG` contains PNG data, point and pixel dimensions, and image scale.

The operation acquires the capture lock before it finds the host window or prepares content.
Queued cancellation is checked before content mounts. It also applies snapshot traits,
including the interface idiom and size classes from `Frame.layoutTraits`.
It then does full-content
measurement, accessibility annotation, settling, and PNG round-tripping. Call
it only from a test bundle hosted by `StuffTestHost`. It needs the host app's
key window. A rendering or encoding error throws. The caller must not publish
a partial artifact.

## HTML snapshots

`assertHTMLSnapshots(of:named:configurations:)` renders static, self-contained HTML in
a hosted `WKWebView`. Each configuration uses a fresh, ephemeral web view.
Page JavaScript and HTTP(S) resource loads are disabled. Navigation, fonts,
and painting must finish before full-content height measurement.

The WebKit wrapper passes through `assertSnapshots` like a native view.
The shared pipeline owns hosting, traits, the capture lock, tiled rendering,
PNG normalization, comparison, recording, timing, and diffs.

The throwing `onReadyToMeasure` hook waits for document readiness while hosted.
WebKit must paint after each viewport resize before its height can be measured again.
Read document height in the same JavaScript callback. UIKit scroll-size updates can arrive after that callback.
The HTML adapter supplies the complete size. Generic scroll measurement does not inspect its internal scroll views.
This browser-specific loop finishes before the shared intrinsic measurement starts.
The hook has a 10-second timeout, scaled by the existing CI timeout multiplier.
Failures and cancellation tear down the host without comparing or recording an image.

Native callers can also throw from `onReadyToMeasure` and set
`measurementHookTimeout` on `assertSnapshots`, `captureSnapshotPNG`, or
`renderSnapshotImage`. With no override, the existing settle ceiling applies.
Hooks must cooperate with cancellation. An override changes only the hook ceiling;
it does not raise the settle floor or change image tolerances.
Only standard, one-axis full-content configurations are supported.
These images capture the document without Safari chrome or accessibility annotations.
The capture host hides native scroll-edge effects so they cannot blur document content.
Set `layoutTraits: .tabletPortrait` for tablet cases; these request desktop page mode.

```swift
try await assertHTMLSnapshots(
    of: html,
    named: "Downloads",
    configurations: [
        .init(device: .iPhoneFullContent),
        .init(colorScheme: .dark, device: .iPhoneFullContent),
    ],
)
```

Keep fixture generation with the page owner. The
[install-site suite](../../Tools/SnapshotTests/InstallerSiteSnapshotTests.swift)
uses HTML generated by the production Astro renderer during each build.
Its fixture generator embeds the emitted CSS and artwork for offline capture.

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

Synchronous autorelease pools bound settle samples, tile rendering, capture normalization, and reference comparison.
The capture pool returns only the normalized image and PNG bytes. Pools never span an `await`.

`SNAPSHOT_SETTLE` selects the stability mechanism (`pixel`, `quiescence`,
`both`). see [`AGENTS.md`](AGENTS.md) for why `pixel` is the only safe default.

`SNAPSHOT_SETTLE_TIMEOUT_MULTIPLIER` scales the maximum observed-motion and
readiness-hook ceilings from 1× through 4×. It does not change minimum floors,
the quiet-window proof, render cadence, or image tolerances, so stable captures
finish at the same point. Local runs leave it unset (1×). snapshot CI explicitly
uses 2×. `./test` forwards it into the hosted test process.

## Retries after settling failures

`assertSnapshots` allows three attempts per independent capture when settling
times out or cannot prove stability on a slow runner. Each cutsheet panel has its
own attempt budget. Each retry starts after capture
cleanup, with a fresh host controller and the same timeout budget. Measurement,
readiness hooks, and final capture run again. Supplied views and external model
objects remain shared. Readiness hooks must tolerate repeated execution.

After three settling failures, the runner records the final error. Cancellation
stops immediately. Other rendering errors and reference mismatches fail without
retries. Direct image and PNG capture APIs remain single-attempt operations.

`SNAPSHOT_RETRY` lines identify failed attempts and successful recovery. `./test`
shows these lines without adding to test or image counts. A successful capture
emits one timing line that includes time spent on failed attempts.

## Requirements

- Runs in a hosted test bundle (needs a host app window. in this repo that's
  `StuffTestHost`, reached via `TestHostSupport`).
- Device/OS-pinned: reference images are captured on a fixed simulator (this
  repo's CI uses the defaults and runtime pins in `Project.swift` and `test`).
- Timezone-pinned: references bake wall-clock dates/times into pixels, so the
  snapshot scheme pins `TZ` (and the runner verifies it via
  `SNAPSHOT_EXPECTED_TIMEZONE`) — see `testScheme` in `Project.swift`.

## Component comparison sheets

Use `SnapshotCase.cutsheet(name:configurations:panels:)` to capture the same
component state across consumer-defined appearances. Each `SnapshotPanel` has a
stable typed identity, a display label, and a lazy content builder. Build fresh
fixture state inside that builder. Each configuration produces one two-column
sheet with unscaled, independently hosted panels. Additional panels wrap to new rows.

The consumer chooses the reference group; Where's theme helper selects `themes`.
The runner stores one PNG with a versioned panel map in its Description metadata.
Each panel uses the ordinary image comparator and its own pixel budget. The complete
sheet also guards headings and spacing. Membership, labels, dimensions, and missing
or malformed metadata fail explicitly. Review the PNG before recording. Preserve
its metadata when copying references; image optimizers that strip metadata invalidate
cutsheet references.

Single views and cutsheets share configured capture and reference recording helpers.
Each panel's hosting view uses the sheet's fixed white background, including in dark mode.
This fills transparent margins without changing component layout. A component's own background remains visible above it.
Panels retain independent settling and fresh fixtures. The runner compares panels
before assembling their captured images in a SwiftUI `Grid`. SwiftUI lays out labels
and images; geometry observations supply the embedded panel map. The shared hosted
renderer captures the grid. The original component views run only for their independent
captures. All failing panels appear in the verdict, subject to the existing recording policy.

Ordinary cases accept an optional `SnapshotReferenceGroup`. The default keeps
existing paths. Groups are stable lowercase slugs owned by the consumer; they do
not change configuration identifiers. Special traits use `other/` inside the group.
Use component sheets for appearance coverage and keep screen variants for critical
integration or materially different composition. Preview sheets approximate layout;
the hosted test capture remains authoritative.

The runner reads SnapshotKit's `Capture` SPI and switches exhaustively between
single-view and cutsheet captures. Panel collections are validated before capture.
No empty-array fallback selects the single-view path.

## Adaptive containers

The runner applies each frame's layout traits before mounting its content.
It reads fallback width and display scale from the marked test host window.
Each configuration invokes the content builder again. Models captured outside that builder still need separate fixtures and hooks.
See [SnapshotKit's adaptive container contract](../SnapshotKit/README.md#adaptive-containers) for viewport coverage and measured device profiles.

Fixed, regular-width phone captures retain their scene so native bar heights stay stable during settlement.
The pipeline selects this path from the content controller’s layout traits before hosting.
Other synthetic captures detach the marked window. This prevents physical reserved regions from truncating compact titles and keeps full-content search anchored to expanded content.
For fixed captures, the pipeline subtracts the resized host controller’s native insets from the requested clearance.
It detaches already-mounted subjects before configuring the capture host.
Only the captured root overrides its safe-area getter. Native controller insets supply ancestor clearance; root pinning preserves translated tile geometry.
Annotation padding has zero safe-area insets so image content and accessibility outlines share the same layout.
The host controller propagates the configured content insets through native navigation containers.

The pipeline restores the scene, frames, additional insets, visibility, and key state after success or failure.
Window discovery, environment checks, and content preparation run under the same capture lock.
Capture hooks use their retained model or view references while the window is detached.

A nil safe-area override retains native scene geometry.
Synthetic captures validate composition and complete content. Native floating bars can retain system positioning despite custom content insets.
Native Duo checks validate their clearance and reserved-region delivery.
