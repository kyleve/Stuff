# SnapshotKitTesting – Module Shape

SnapshotKitTesting is the test-only half of the snapshot-testing framework. It provides the capture and comparison pipeline and the `assertSnapshots` runner over a [`SnapshotKit`](../SnapshotKit) matrix. See [`README.md`](README.md).

Read the root [`AGENTS.md`](../../AGENTS.md) first.

## Scope & dependencies

- **Depend on `SnapshotKit`, `TestHostSupport`, and `SnapshotTesting`.** Also depend on AccessibilitySnapshot's focused Core + Previews products (cashapp).
- **Link the comparison engine, XCTest/Testing, and the SwiftUI accessibility renderer.**
- **Consume this module only from test bundles through `extraPackageProducts`.** That includes per-module image bundles (`WhereUISnapshotTests`, `PeriscopeToolsSnapshotTests`, `InspectorSnapshotTests`, gathered into the `StuffSnapshotTests` *scheme*) and `SnapshotKitTestingTests`.
- **Never link this module from a shipping app or `StuffTestHost`.**
- **"Process-global" state here is module-global — one copy per consuming `.xctest`.** That is safe only because each bundle gets its own host process.
- **If two copies co-load into one process, they flip the safe-area swizzle's parity.** They also hide captures from each other's lock.
- **Tripwire: if a toolchain ever shares one host process across bundles, re-measure before adding a consumer.** See topology and measurement in the snapshot-bundle comment in `Project.swift` and the root [`AGENTS.md`](../../AGENTS.md#targets).
- **`WhereUISnapshotTests` double-embeds `SnapshotKit`, tolerated and guarded.** This product's closure plus WhereUI's own copy live in one image. The other image bundles do not link WhereUI.
- **Guard: `WhereUISnapshotTests.SnapshotCaptureFlagProbeTests` fails loudly if the copies split.** Mechanism: PR #145.
- **Re-export `SnapshotKit` and `SnapshotTesting`** so consumers need one import.
- **Declare the library target in [`Package.swift`](../../Package.swift).**

## Invariants an agent can't re-derive

- **The rendering pipeline is one async function.** All captures (standard and accessibility) flow through `renderSnapshotImage(...)`.
- **Its `async` is load-bearing.** A synchronous `Snapshotting` pullback could never settle `.task`-driven content.
- **Accessibility annotations use AccessibilitySnapshot's SwiftUI renderer.** Keep the focused `AccessibilitySnapshotCore` + `AccessibilitySnapshotPreviews` products.
- **Raised-floor accessibility captures parse twice.** Settle between passes and keep only the second render (`AccessibilitySnapshotViewControllerTests`).
- **The umbrella also links the upstream SnapshotTesting integration that this module replaces.**
- **The compare sees on-disk bytes.** Every capture round-trips through PNG encoding before comparison.
- **Removing PNG encoding re-opens the wide-gamut vs. sRGB flake.** See `renderSnapshotImage`'s doc.
- **`CILabDeltaE` is not perceptually uniform.** The ΔE tolerance is loose by design.
- **The verdict's metric is far steeper near black than the CIE76 it approximates.**
- **On this toolchain, a ±1/255 drift reads as ΔE 0.15-0.19 in pastels.** In dark greys it reads up to 4.2.
- **In the worst near-black corner, with channels moving in opposite directions, it reads up to 12.1.** CIE76 calls the same drift ~0.3.
- **That is why `defaultSnapshotPerceptualPrecision` is 0.90 (ΔE 10).** Do not use something eye-shaped like 0.98 (ΔE 2).
- **Relax this knob, never `defaultSnapshotPrecision`.** Environmental noise is bounded in per-pixel amplitude but scatters over dark content.
- **Widening the area budget instead would hide a real regression confined to one component.**
- **Evidence: CI run 30390830180, `calendarContent.FullContent_fullHeight`, which 0.98 failed.** Every one of its 30,572 differing pixels was off by exactly one unit.
- **87% of those pixels were near-black glyph pixels.** True CIE76 maximum was 0.99 — invisible.
- **Yet 17,007 pixels (0.157%) cleared ΔE 2 and blew the 0.1% budget.**
- **At ΔE 10 that capture contributes zero pixels.**
- **The genuine glyph-shift regression in `inspectorSurfaces.SwiftData_iPhone_dark` still fails at 0.178%.** Differing pixels massed at ΔE 62.
- **0.95 (ΔE 5) was rejected.** It passes, but leaves 7,120 noise pixels at 66% of the budget.
- **Only the pipeline prints a report channel.** A test asks for the payload.
- **`./test` recovers `SNAPSHOT_TIMING` and `SNAPSHOT_DIFF` by grepping run logs.** By hand, it also recovers `SNAPSHOT_SETTLE`.
- **It counts timing lines as captured images for the progress line.**
- **Anything that prints one is a row in a report and an image in the count.** Nothing marks it synthetic.
- **Split each channel for that reason.** `report(...)` / `emit()` print. `line(...)` only returns the JSON.
- **A test that pins the wire shape calls `line(...)`.**
- **Derive review reference paths with swift-snapshot-testing's exact name
  sanitization.** Spaces and punctuation become one hyphen. Guard:
  `SnapshotReferenceDiffTests`.
- **When they were one function, this module's own tests put a fabricated reference at the top of `./test --review`.** Its numbers were borrowed from a real regression.
- **Five invented captures also landed in `--timings`.** Then a run that captured nothing reported "5 captures, 0.024s per image".
- **The runner fails fast, once, on setup problems.** Examples: a simulator that does not match the `SNAPSHOT_EXPECTED_*` pins, two variants sharing one reference name.
- **Report one clear issue, never hundreds of pixel diffs.**
- **An unsettled capture is a failure, not a silent fallback.**
- **Freeze endless motion behind `\.isCapturingSnapshot`.** Use deterministic readiness or `.settledAtLeast` for finite work.
- **The explicit CI multiplier may scale only maximum settle/hook ceilings.** Never scale the floor, quiet proof, cadence, or image tolerance.
- **Guards: `SnapshotSettleTimeoutPolicyTests` and `SnapshotRenderingSupportTests`.**
- **A settled capture is not a ready capture.** The loop proves the pixels stopped changing, not that intended content arrived.
- **For native navigation or tab glass, do not use `SnapshotSettle.immediate`.**
- **Keep a measured `SnapshotSettle.settledAtLeast` floor for delayed native-glass adaptation.**
  Remove it only after a toolchain remeasurement or a system readiness signal.
  See PRs #101, #144, #151, and #232.
- **Use `SnapshotMeasurementReadiness.immediate` only for a fixture with a synchronous final height.**
  This option skips only measurement settling. It does not change the final
  `SnapshotSettle`.
- **A loading placeholder is perfectly pixel-stable.** A gap between async phases settles clean and bakes the spinner. Then the suite reports green.
- **Pixel stability cannot become a readiness signal.** Nothing public sees pending dispatch or Swift-concurrency work — see below.
- **If content arrives asynchronously, make the case deterministic instead.**
- **Seed the fixture so its first frame is final (`resolution.Empty`).** Or await a completion signal from `onReadyToSnapshot` (`root.LoggedIn`).
- **Both incidents, and how each was found, are ledgered in [`Where/TODOs.md`](../../Where/TODOs.md).**
- **Height-changing readiness runs before measurement.**
- **Intrinsic/full-content cases await `onReadyToMeasure` only after the sizing probe is hosted and laid out.** Then they settle and resolve height.
- **The hook is bounded by the effective settle ceiling.** It must cooperate with cancellation. Reject it for fixed sizing.
- **Guards: `PreMeasureHookTests` and `SnapshotMeasurementHookTests`.**
- **`.timedOut` requires observed motion.** Starvation is `.starved`.
- **A change-free settle loop keeps running until it can prove stability.** A starved machine can fit fewer passes than stability needs.
- **Only a hard cap gives up as `.starved`.** That is an environment failure, not view motion.
- **Guard: `SnapshotRenderingSupportTests`.**
- **Captures are single-tenant per process.** `renderSnapshotImage` serializes through a FIFO `@MainActor` mutex.
- **The safe-area swizzle is depth-counted.** Nested captures trap.
- **Keep the suite serial anyway.** Concurrent scheduling degrades to queued-serial, gaining nothing.
- **Guard: `SnapshotKitTestingTests.ConcurrentCaptureTests`.** The interleaving failure and the reasons not to parallelize are recorded below, under the rejected experiments. The snapshot job's own copy of that warning did not survive its move to CircleCI in PR #237 — restoring it is filed in the root [`TODOs.md`](../../TODOs.md).
- **Rendering requires `StuffTestHost`'s key window** (`TestHostSupport.hostKeyWindow()`). It is not usable from a non-hosted bundle.
- **Pin determinism.** The pipeline overrides safe-area insets and quiesces animations.
- **Set `SnapshotCaptureTrait` on the content controller, not a wrapper.** It must survive the intrinsic-measurement re-hosting so views can freeze never-settling motion.
- **Tile-and-stitch is load-bearing, not legacy.** UIKit renders a blank image for views past ~2000pt on iOS 27.0.
- **Do not remove the tiling without re-running the probe.** Guard: `SnapshotKitTestingTests.LargeViewCaptureTests`.
- **Include UIKit-backed SwiftUI containers in full-content sizing.**
- **When a full-width scroll view such as `Form` reports its viewport through `sizeThatFits`, add surrounding chrome to the size.**
- **Device presets retain their normal viewport height as the minimum.** Guard: `SnapshotKitTestingTests.LargeViewCaptureTests`.
- **Use one authoritative scroller for two-axis full-content sizing.** Resolve both dimensions from the largest viewport-filling scroll descendant. Converge the size as one value. Reset it to the leading/top edge.
- **Reject unsafe two-axis captures before allocation.** Limit them to 32,000 pixels per dimension and 100 million pixels total. Guard: `SnapshotKitTestingTests.LargeViewCaptureTests`.
- **Intrinsic height must converge before comparison.**
- **If bounded fixed-point passes are exhausted, fail the assertion and skip comparison/recording.** Never bless the last arbitrary height.
- **Guard: `LargeViewCaptureTests.rejectsNonConvergingBoundedScrollMeasurement`.**
- **Immediate measurement never shortens final capture settling.** It skips only the intrinsic-sizing probe's settle for synchronously sized fixtures.
- **The final `.settled` / `.settledAtLeast` policy still runs.** Guards: `AsyncContentCaptureTests`.
- **A settle phase costs its floor, not its passes.**
- **Measured 2026-07-28 with `SNAPSHOT_TIMING=1` over 260 references of the time.** The suite holds 472 as of 2026-08-30. Re-measure before acting on the split below.
- **The conclusion (the floor dominates) is what to rely on, not the seconds.**
- **192 captures sat at 0.25-0.35s — the `minDuration` floor plus a pass or two.** The floor accounts for ~70s of the ~84s of settle time.
- **The render passes themselves are ~14s across the whole suite.** Making passes cheaper is worth ~11%. Removing floors is worth ~54%.
- **A floor can come off only with a deterministic completion seam for that case.** Example: `root.LoggedIn` awaits `launcher.run()` from `onReadyToSnapshot`.
- **Never remove a floor through introspection.**

## Three things measured and rejected — don't re-derive them

- **Sharding the suite across simulators on one Mac is 2.7x slower, and wrong.**
- **Measured 2026-07-28 on a 10-core / 24 GB machine: the serial suite runs in 142s** (twice, 142.2 and 142.1).
- **The same suite split into four duration-balanced slices across four booted simulators took 387s.** Each slice had its own process with its own `StuffTestHost`.
- **That sharded run produced 9 failures** (two settle timeouts, one image mismatch).
- **Separate processes fix the shared-state interleaving that sank the earlier in-process attempt.**
- **They do not fix the real constraint: every shard contends for one render server.**
- **Then `drawHierarchy` slows down enough to push captures past their settle budget.**
- **The bar for keeping sharding was a 30% win.**
- **Isolated CI runners avoid that contention.** PR #237 retired their duplicated setup/build cost after the M4 Pro migration made one serial job fast enough.
- **Do not reach for `-parallel-testing-enabled` either.** It distributes XCTest *classes*, and Swift Testing presents none.
- **Then it lands everything on one worker.** Swift Testing's own parallelism interleaves captures in a single host process (24+ spurious mismatches, 1.2-3x slower).
- **Quiescence cannot replace the pixel digest.**
- **`SNAPSHOT_SETTLE` selects `pixel` (default), `quiescence`, or `both`.** Quiescence uses a `beforeWaiting` run-loop observer plus a recursive `needsLayout`/`needsDisplay`/`animationKeys` walk.
- **`both` runs them together and reports disagreements.**
- **Run in `both` mode (2026-07-28) over 260 references of the time — 472 as of 2026-08-30.** The counts below are that run's, not current.
- **That run had 226 settle phases, 134 with some disagreement.**
- **8 cases had quiescence declare settled *earlier* than the digest.** Every one was a `Loaded_*` case whose content arrives late.
- **That is the one dangerous direction.** It would capture a frame no reference recorded.
- **That is what `settleContent`'s doc comment predicts.** A SwiftUI update deep in the hosted tree never dirties the root.
- **Flags read after a commit has flushed look clean.**
- **Keep the mechanism so the experiment is re-runnable after a toolchain change.** It is not a candidate default.
- **Sample pending layout before the loop's own `layoutIfNeeded`.** Reading it afterwards makes that third of the signal vacuously clean.
- **Keep separate observed-change flags for the two mechanisms.** Then `both` genuinely leaves the verdict to the digest.
- **Sharing one flag let quiescence flapping return `.timedOut` for content the digest never saw change.** That alters the experiment's own result.
- **Guard: `SnapshotQuiescenceTests.staticContentSettlesRegardlessOfMechanism`.**
- **No public API sees pending dispatch or Swift-concurrency work.**
- **`CFRunLoopGetNextTimerFireDate` reports only `CFRunLoopTimer`s.** Then "is something scheduled to land in 200ms?" is unanswerable.
- **That is why the floors exist and why they need per-case seams.**
- **`CATransaction.addCommitHandler` is macOS-only and absent from the iOS SDK.** A commit-counting variant is not available either.

## Testing

`SnapshotKitTestingTests` (`Tests/`, in the `Stuff-iOS-Tests` scheme) owns the pipeline's own regression tests. They render through `renderSnapshotImage` and need the `StuffTestHost` key window. They assert on probed pixels through the `@_spi(Testing)` `PixelSample`/`probePixel` API rather than LFS reference images — fast, no `__Snapshots__/`, main `test` job. The matrixed image assertions live in the per-module image bundles. The cross-boundary flag probe stays in `WhereUISnapshotTests`, since only a WhereUI-defined view can detect a duplicate-`SnapshotKit` split.
