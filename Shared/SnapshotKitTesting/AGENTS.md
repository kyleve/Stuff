# SnapshotKitTesting – Module Shape

The test-only half of the snapshot-testing framework: the capture + comparison
pipeline and the `assertSnapshots` runner over a [`SnapshotKit`](../SnapshotKit)
matrix. See [`README.md`](README.md).

Complements the root [`AGENTS.md`](../../AGENTS.md) — read that first.

## Scope & dependencies

- Depends on `SnapshotKit`, `TestHostSupport`, `SnapshotTesting`
  (swift-snapshot-testing), and AccessibilitySnapshot's focused Core + Previews
  products (cashapp). It links the comparison engine + XCTest/Testing and the
  SwiftUI accessibility renderer, so it is **only** consumed by test
  bundles via `extraPackageProducts` — the per-module image bundles
  (`WhereUISnapshotTests`, `PeriscopeToolsSnapshotTests`,
  `InspectorSnapshotTests`, gathered into the `StuffSnapshotTests`
  *scheme*) and `SnapshotKitTestingTests` — **never** a shipping app or
  `StuffTestHost`.
- **"Process-global" state here is module-global — one copy per consuming
  `.xctest` — and that is safe only because each bundle gets its own host
  process.** Two copies co-loaded into one process would flip the safe-area
  swizzle's parity and hide captures from each other's lock. Tripwire: if a
  toolchain ever shares one host process across bundles, re-measure before
  adding a consumer — topology and measurement in the snapshot-bundle comment
  in `Project.swift` and the root [`AGENTS.md`](../../AGENTS.md#targets).
- **`WhereUISnapshotTests` double-embeds `SnapshotKit`, tolerated and
  guarded** (this product's closure plus WhereUI's own copy in one image; the
  other image bundles don't link WhereUI). Guard:
  `WhereUISnapshotTests.SnapshotCaptureFlagProbeTests` fails loudly if the
  copies split; mechanism: PR #145.
- Re-exports `SnapshotKit` and `SnapshotTesting` so consumers need one import.
- Library target in [`Package.swift`](../../Package.swift).

## Invariants an agent can't re-derive

- **The rendering pipeline is one async function.** All captures (standard and
  accessibility) flow through `renderSnapshotImage(...)`; its `async` is
  load-bearing — a synchronous `Snapshotting` pullback could never settle
  `.task`-driven content.
- **Accessibility annotations use AccessibilitySnapshot's SwiftUI renderer.**
  Keep the focused `AccessibilitySnapshotCore` +
  `AccessibilitySnapshotPreviews` products; the umbrella also links the
  upstream SnapshotTesting integration that this module replaces.
- **The compare sees on-disk bytes.** Every capture round-trips through PNG
  encoding before comparison; removing it re-opens the wide-gamut vs. sRGB
  flake (see `renderSnapshotImage`'s doc).
- **`CILabDeltaE` is not perceptually uniform, so the ΔE tolerance is loose by
  design.** The verdict's metric is far steeper near black than the CIE76 it
  approximates: measured on this toolchain, a ±1/255 drift reads as ΔE
  0.15-0.19 in pastels, up to 4.2 in dark greys, and up to **12.1** in the
  worst near-black corner when channels move in opposite directions — where
  CIE76 calls the same drift ~0.3. That is why
  `defaultSnapshotPerceptualPrecision` is **0.90** (ΔE 10) rather than
  something eye-shaped like 0.98 (ΔE 2). Relax *this* knob, never
  `defaultSnapshotPrecision`: environmental noise is bounded in per-pixel
  amplitude but scatters over whatever content is dark, so widening the *area*
  budget instead is what would hide a real regression confined to one
  component. Evidence, from the CI attachments of run 30390830180
  (`calendarContent.FullContent_fullHeight`, which 0.98 failed): every one of
  its 30,572 differing pixels was off by exactly one unit, 87% of them
  near-black glyph pixels, true CIE76 maximum **0.99** — invisible, yet 17,007
  pixels (0.157%) cleared ΔE 2 and blew the 0.1% budget. At ΔE 10 that capture
  contributes **zero** pixels, while the genuine glyph-shift regression in
  `inspectorSurfaces.SwiftData_iPhone_dark` (differing pixels massed
  at ΔE 62) still fails at 0.178%. 0.95 (ΔE 5) was rejected: it passes, but
  leaves 7,120 noise pixels at 66% of the budget, i.e. one bad CI day from red.
- **Only the pipeline prints a report channel; a test asks for the payload.**
  `./test` recovers `SNAPSHOT_TIMING` and `SNAPSHOT_DIFF` (and, by hand,
  `SNAPSHOT_SETTLE`) by grepping them out of the run logs, and it counts timing
  lines as *captured images* for the progress line — so anything that prints one
  is a row in a report and an image in the count, with nothing marking it
  synthetic. Each channel is split for that reason: `report(...)` / `emit()`
  print, `line(...)` only returns the JSON, and a test pinning the wire shape
  calls `line(...)`. Not hypothetical — when they were one function, this
  module's own tests put a fabricated reference at the *top* of
  `./test --review` (its numbers were borrowed from a real regression) and five
  invented captures into `--timings`, so a run that captured nothing at all
  reported "5 captures, 0.024s per image".
- **The runner fails fast, once, on setup problems** (a simulator that doesn't
  match the `SNAPSHOT_EXPECTED_*` pins, two variants sharing one reference
  name) — one clear issue, never hundreds of pixel diffs.
- **An unsettled capture is a failure, not a silent fallback.** Don't "fix" a
  settle timeout by widening the budget — freeze the motion behind
  `\.isCapturingSnapshot`, or use `.settledAtLeast` only for genuinely slow
  (not endless) content.
- **A settled capture is not a ready capture.** The loop proves the pixels
  stopped changing, not that the content the case meant to show ever arrived —
  a loading placeholder is perfectly pixel-stable, so a gap between phases of
  async work settles clean and bakes the spinner, and the suite reports green.
  Pixel stability can't be strengthened into a readiness signal (nothing public
  sees pending dispatch or Swift-concurrency work — see below), so a case whose
  content arrives asynchronously must be made deterministic instead: seed the
  fixture so its first frame is final (`resolution.Empty`), or await a
  completion signal from `onReadyToSnapshot` (`root.LoggedIn`). Both incidents,
  and how each was found, are ledgered in
  [`Where/TODOs.md`](../../Where/TODOs.md).
- **`.timedOut` requires observed motion; starvation is `.starved`.** A
  change-free settle loop keeps running until it can prove stability (a
  starved machine can fit fewer passes than stability needs), and only a hard
  cap gives up as `.starved` — an environment failure, not view motion.
  Guard: `SnapshotRenderingSupportTests`.
- **Captures are single-tenant per process** — `renderSnapshotImage`
  serializes through a FIFO `@MainActor` mutex, the safe-area swizzle is
  depth-counted, and nested captures trap. Keep the suite serial anyway:
  concurrent scheduling degrades to queued-serial, gaining nothing. Guard:
  `SnapshotKitTestingTests.ConcurrentCaptureTests`; the interleaving failure
  is recorded in the snapshot job comment in `.github/workflows/ci.yml`.
- **Rendering requires `StuffTestHost`'s key window**
  (`TestHostSupport.hostKeyWindow()`) — not usable from a non-hosted bundle.
- **Determinism is pinned.** The pipeline overrides safe-area insets,
  quiesces animations, and sets `SnapshotCaptureTrait` on the *content*
  controller (not a wrapper — it must survive the intrinsic-measurement
  re-hosting) so views can freeze never-settling motion.
- **Tile-and-stitch is load-bearing, not legacy.** UIKit renders a blank
  image for views past ~2000pt on iOS 27.0; don't remove the tiling without
  re-running the probe. Guard:
  `SnapshotKitTestingTests.LargeViewCaptureTests`.
- **Full-content sizing includes UIKit-backed SwiftUI containers.** When a
  full-width scroll view such as `Form` reports only its viewport through
  `sizeThatFits`, use its content size plus surrounding chrome; device presets
  retain their normal viewport height as the minimum. Guard:
  `SnapshotKitTestingTests.LargeViewCaptureTests`.
- **Intrinsic height must converge before comparison.** Exhausting the bounded
  fixed-point passes fails the assertion and skips comparison/recording; never
  bless the last arbitrary height. Guard:
  `LargeViewCaptureTests.rejectsNonConvergingBoundedScrollMeasurement`.
- **Immediate measurement never shortens final capture settling.** It skips
  only the intrinsic-sizing probe's settle for synchronously sized fixtures;
  the final `.settled` / `.settledAtLeast` policy still runs. Guards:
  `AsyncContentCaptureTests`.
- **A settle phase costs its floor, not its passes.** Measured 2026-07-28 with
  `SNAPSHOT_TIMING=1` over the **260** references of the time — the suite holds
  **381** as of 2026-08-09, so re-measure before acting on the split below;
  the *conclusion* (the floor dominates) is what to rely on, not the seconds.
  Then: 192 captures sat at 0.25-0.35s, the
  `minDuration` floor plus a pass or two, and the floor accounts for ~70s of
  the ~84s of settle time. The render passes themselves are ~14s across the
  whole suite. So making passes cheaper is worth ~11% and removing floors is
  worth ~54% — but a floor can only come off with a **deterministic completion
  seam** for that case (as `root.LoggedIn` does by awaiting `launcher.run()`
  from `onReadyToSnapshot`), never by introspection.

## Three things measured and rejected — don't re-derive them

- **Sharding the suite across simulators on one Mac is 2.7x slower, and wrong.** Measured
  2026-07-28 on a 10-core / 24 GB machine: the serial suite runs in **142s**
  (twice, 142.2 and 142.1); the same suite split into four duration-balanced
  slices across four booted simulators, each its own process with its own
  `StuffTestHost`, took **387s** — and produced **9 failures** (two settle
  timeouts, one image mismatch). Separate processes fix the shared-state
  interleaving that sank the earlier in-process attempt, but they don't fix the
  real constraint: every shard contends for one render server, so
  `drawHierarchy` slows down enough to push captures past their settle budget.
  The bar for keeping it was a 30% win. CI's two shards are different: each
  stays serial on its own runner and render server, with membership owned by
  `.github/snapshot-shards.json`; never reproduce that topology concurrently
  on one developer Mac. Don't reach for
  `-parallel-testing-enabled` either — it distributes XCTest *classes*, and
  Swift Testing presents none, so it lands everything on one worker and lets
  Swift Testing's own parallelism interleave captures in a single host process
  (24+ spurious mismatches, 1.2-3x slower).
- **Quiescence can't replace the pixel digest.** `SNAPSHOT_SETTLE` selects
  `pixel` (default), `quiescence` (a `beforeWaiting` run-loop observer plus a
  recursive `needsLayout`/`needsDisplay`/`animationKeys` walk), or `both`, which
  runs them together and reports disagreements. Run in `both` mode (2026-07-28)
  over the 260 references of the time — 361 today, so the counts below are that
  run's, not current: 226 settle phases, 134 with some disagreement, and **8 where
  quiescence declared settled *earlier* than the digest** — every one a
  `Loaded_*` case whose content arrives late. That is the one dangerous
  direction (it would capture a frame no reference recorded), and it is what
  `settleContent`'s doc comment predicts: a SwiftUI update deep in the hosted
  tree never dirties the root, and flags read after a commit has flushed look
  clean. The mechanism is kept so the experiment is re-runnable after a
  toolchain change; it is not a candidate default.

  Two details that make those numbers mean what they say, both of which were
  wrong in the first attempt at this measurement. Pending layout is sampled
  **before** the loop's own `layoutIfNeeded`, because reading it afterwards makes
  that third of the signal vacuously clean. And the two mechanisms keep
  **separate** observed-change flags, so `both` genuinely leaves the verdict to
  the digest — sharing one let quiescence flapping return `.timedOut` for content
  the digest never saw change, i.e. the experiment altering its own result.
  Guard: `SnapshotQuiescenceTests.staticContentSettlesRegardlessOfMechanism`.
- **No public API sees pending dispatch or Swift-concurrency work.**
  `CFRunLoopGetNextTimerFireDate` reports only `CFRunLoopTimer`s, so "is
  something scheduled to land in 200ms?" is unanswerable — which is why the
  floors exist and why they need per-case seams. Relatedly,
  `CATransaction.addCommitHandler` is **macOS-only** and absent from the iOS
  SDK, so a commit-counting variant of the above isn't available either.

## Testing

`SnapshotKitTestingTests` (`Tests/`, in the `Stuff-iOS-Tests` scheme) owns the
pipeline's own regression tests. They render through `renderSnapshotImage`
(so they need the `StuffTestHost` key window) but assert on probed pixels via
the `@_spi(Testing)` `PixelSample`/`probePixel` API rather than LFS reference
images — fast, no `__Snapshots__/`, main `test` job. The matrixed image
assertions live in the per-module image bundles; the cross-boundary flag
probe stays in `WhereUISnapshotTests`, since only a WhereUI-defined view can
detect a duplicate-`SnapshotKit` split.
