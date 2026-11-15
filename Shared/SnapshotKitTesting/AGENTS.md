# SnapshotKitTesting – Module Shape

SnapshotKitTesting owns hosted capture and comparison. See [README.md](README.md) for its API.
Read the root [AGENTS.md](../../AGENTS.md) and [SnapshotKit contract](../SnapshotKit/AGENTS.md) for case construction, frame/trait semantics, coverage, and readiness selection.

## Scope & dependencies

- Test bundles only; never link into shipping apps or `StuffTestHost`. Use `extraPackageProducts`, or `productDependency` when this is the bundle's primary dependency.
  Keep SnapshotKit, TestHostSupport, SnapshotTesting, and AccessibilitySnapshot's focused Core + Previews products. Re-export SnapshotKit and SnapshotTesting.
- Module-global state has one copy per consuming `.xctest`, safe only with separate host processes.
  Co-loaded copies break safe-area swizzle parity and lock isolation. Re-measure if the toolchain shares a host process; see `Project.swift`'s snapshot-bundle comment and [target topology](../../.agents/references/targets.md#targets).
- WhereUISnapshotTests' double-embedded SnapshotKit is guarded by `SnapshotCaptureFlagProbeTests` (PR #145). Other image bundles do not link WhereUI.
- Read case subjects through `Capture` SPI and dispatch exhaustively by case, never by panel-array emptiness.

## Invariants an agent can't re-derive

### Paths, pixels, and reports

- Use `snapshotReferenceURL` for recording, comparison, and review; preserve filenames when directories change.
  Standard non-default Dynamic Type, contrast, RTL, and bold captures go under `other/`. Accessibility annotations stay at the selected group root; device, frame, name, and light/dark do not select `other/`. Guard: `SnapshotReferenceURLTests`.
- All standard, accessibility, and hosted PNG captures use async `renderSnapshotCapture` and its capture lock; `renderSnapshotImage` is the image-only wrapper.
  PNG export requires the host window, with no headless renderer. A synchronous pullback cannot settle task-driven content.
- Compare PNG-round-tripped bytes to prevent wide-gamut/sRGB drift. Reuse captured PNG bytes for ordinary assertions/recording; encode composed cutsheets separately.
  Keep autorelease pools synchronous and drain intermediates before async suspension. See `renderSnapshotImage`'s documentation.
- Keep `defaultSnapshotPerceptualPrecision` at 0.90 (ΔE 10). `CILabDeltaE` exaggerates near-black channel noise; loosen per-pixel tolerance, never the pixel-area budget, for environmental noise.
  Historical tolerance measurements remain in Git history and CI run 30390830180.
- Only pipeline `report`/`emit` functions print `SNAPSHOT_TIMING`, `SNAPSHOT_DIFF`, or `SNAPSHOT_SETTLE` channels.
  Wire-format tests call `line` to obtain JSON without printing; report consumers count emitted timings as actual captures.

### Hosting and accessibility

- Read bounds and scale from `TestHostSupport.hostKeyWindow()`, never the process-global main screen. Non-hosted bundles cannot render.
- Detach already-mounted subjects before host configuration. Reconcile insets after containment and settling, when native geometry updates.
  Override only the captured root's safe-area getter during pixel rendering; preserve native getters during containment, measurement, and settling.
- Default scene retention applies only to fixed, regular-width phone captures with inset overrides, using content-controller traits before hosting.
  Detach other synthetic captures unless `.retained` is explicit. Keep retention off general presets; resize the marked window with the content and review chrome/completeness at each opt-in.
- Restore scene, frames, insets, visibility, and key state on every exit. Nil inset overrides retain native geometry.
  Overrides describe content clearance, not native bar positions or Duo reserved-region delivery; validate those on the native runtime.
  Guards: `SnapshotImageRenderingTests`, `LargeViewCaptureTests`.
- Mount accessibility subjects before readiness/settling and preserve controller parentage during parsing except for upstream tiling.
  Sample native bar metadata synchronously and per instance; restore window geometry before rendering/parsing and restore getters on every exit. Never assign stored `accessibilityElements`.
  Guards: `AccessibilitySnapshotViewControllerTests`, `SnapshotAccessibilityViewportTests`.
- Annotation padding has zero safe-area insets; subject clearance belongs to the captured root. Preserve centered-content outline alignment.
  Raised-floor annotation captures parse twice, settling at original capture size between passes and expanding only after the final parse.
- Set `SnapshotCaptureTrait` on the content controller so it survives measurement re-hosting. Quiesce animations through the pipeline.

### Readiness, retries, and serialization

- Fail setup once with a clear issue for environment-pin mismatches or duplicate reference names, without producing cascades of pixel diffs.
- Unsettled captures fail. Assertions retry only `settleTimedOut` and `settleStarved`, up to three attempts per view or panel.
  After cleanup and lock release, create a fresh controller, reuse models, and rerun repeatable readiness hooks. Preserve cancellation and report the final original error once.
  Direct image/PNG APIs remain single-attempt; comparison/recording requires successful capture. Guards: `SnapshotCaptureRetryTests`, `AssertSnapshotsTests`.
- Emit retries through `SNAPSHOT_RETRY`, without extra timing/diff rows. Include failed-attempt time in the successful capture's single timing line. Guard: `Tools/Tests/test_test_runner.py`.
- Settle samples use normalized 8-bit premultiplied sRGB RGBA, allowing one unit per channel and no area exemption.
  Keep a fixed anchor across two matching passes spanning at least 120 ms and the case's minimum duration. Larger differences, changed dimensions, or missing samples reset the proof.
  Never reuse reference-comparison tolerances. Preserve cumulative-fade and single-pixel guards in `SnapshotPixelStabilityTests` and `SnapshotRenderingSupportTests`.
- The CI multiplier scales only maximum settle/hook ceilings, not floors, quiet proof, cadence, or image tolerance. Guards: `SnapshotSettleTimeoutPolicyTests`, `SnapshotRenderingSupportTests`.
- Preserve readiness regressions documented in [STU-279](https://linear.app/kve/issue/STU-279/resolutionempty-never-rendered-the-empty-state-and-its-capture-raced-a) and [STU-280](https://linear.app/kve/issue/STU-280/rootloggedin-failed-3-consecutive-ci-runs-29617740607-29621920437).
- Native navigation/tab glass requires a measured `.settledAtLeast` floor, not `.immediate`. Remove it only after toolchain remeasurement or a system readiness signal (PRs #101, #144, #151, #232).
  Other case floors require deterministic completion evidence before removal; never infer completion through runtime introspection.
- Invoke intrinsic/full-content measurement hooks after hosting/layout and before settling/height resolution; reject them for fixed sizing.
  Bound hooks by the effective settle ceiling or explicit timeout, scaled by the CI multiplier. Preserve errors, skip failed captures, and require cancellation cooperation.
  Guards: `PreMeasureHookTests`, `SnapshotMeasurementHookTests`.
- `.timedOut` requires observed motion. A change-free loop continues until stability is proven or the hard cap yields `.starved`, an environment failure. Guard: `SnapshotRenderingSupportTests`.
- Every entry point acquires the FIFO `@MainActor` mutex before window discovery, environment validation, or content preparation.
  The safe-area swizzle is depth-counted; nested captures trap. Keep suites serial; CI shards on isolated VMs. Guard: `ConcurrentCaptureTests`.

### HTML and full-content sizing

- HTML uses offline WebKit through the standard host, traits, lock, and pixel renderer. Consumer HTML generation stays outside this module.
  Await navigation, fonts, paint, and height convergence in the pre-measure hook. Measure in WebKit after paint, excluding its async UIKit scroll-size mirror via `SnapshotContentSizeProviding`.
  Hide native scroll-edge effects. Guards: `AssertHTMLSnapshotsTests`, `SnapshotWebPageTests`, including `capturesSharpContentAtDocumentEdges`.
- Keep tile-and-stitch until re-running the large-view probe: UIKit renders blank beyond roughly 2000pt on iOS 27.0. Guard: `LargeViewCaptureTests`.
- Include UIKit-backed containers in full-content sizing. When a full-width scroller reports only its viewport and its content exceeds root intrinsic height, measure that content plus surrounding chrome.
  Do not add unused host space when intrinsic height already covers content. Preserve device viewport minimums. Guard: `LargeViewCaptureTests.keepsAShortBoundedScrollViewAtItsIntrinsicHeight`.
- Reset full-content primary scroll positions to top after readiness; viewport captures preserve restored offsets. Guard: `LargeViewCaptureTests.restoredScrollOffsetsApplyOnlyToViewportCaptures`.
- Two-axis sizing uses the largest viewport-filling scroll descendant for both dimensions and converges them together, resetting leading/top.
  Reject dimensions above 32,000 pixels or 100 million total pixels before allocation. Guard: `LargeViewCaptureTests`.
- If bounded measurement passes do not converge, fail and skip comparison/recording. Guard: `LargeViewCaptureTests.rejectsNonConvergingBoundedScrollMeasurement`.

## Measurement evidence

Before changing parallelism, quiescence, or settling mechanisms, read [the measured experiments](Guidance/experiments.md).
Their constraints remain required; repeat measurements at the documented tripwires.

## Component comparisons and reference groups

- Consumers choose theme identities, ordering, and component/full-screen coverage. Accept generic labeled panels and validated groups.
- Preserve ungrouped filenames and use the same resolver for recording, comparison, and review; `other/` nests inside groups.
- Capture each panel independently with fresh fixture state through the hosted readiness/accessibility pipeline.
  Set its host to the sheet's fixed `SnapshotImageGrid.backgroundColor`, independent of appearance. Guard: `AssertComparisonSnapshotsTests.transparentPanelsMatchTheirSheet`.
- Store a versioned panel map in PNG Description metadata; reject missing/invalid maps. Review PNGs before recording and preserve metadata.
- Share configured capture/recording with single views. Collect all panel failures before composing images without re-rendering.
  Store bounds/canvas sizes in whole pixels, including at 3x. Apply existing tolerance per panel, never diluting area budgets across the sheet. Layout/membership changes fail explicitly.
- Count actual panel captures in timings, excluding composition.

## Testing

`SnapshotKitTestingTests` uses the host window and Testing-SPI pixel probes, without LFS references, in the main unit-test job.
Per-module image bundles own matrixed assertions. Keep the cross-boundary flag probe in WhereUISnapshotTests: only a WhereUI-defined view detects its duplicate-SnapshotKit split.
