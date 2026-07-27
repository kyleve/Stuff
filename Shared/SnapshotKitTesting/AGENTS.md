# SnapshotKitTesting – Module Shape

The test-only half of the snapshot-testing framework: the capture + comparison
pipeline and the `assertSnapshots` runner over a [`SnapshotKit`](../SnapshotKit)
matrix. See [`README.md`](README.md).

Complements the root [`AGENTS.md`](../../AGENTS.md) — read that first.

## Scope & dependencies

- Depends on `SnapshotKit`, `TestHostSupport`, `SnapshotTesting`
  (swift-snapshot-testing), and `AccessibilitySnapshot` (cashapp). It links the
  comparison engine + XCTest/Testing, so it is **only** consumed by the
  `StuffSnapshotTests` and `SnapshotKitTestingTests` bundles via
  `extraPackageProducts` — **never** a shipping app or `StuffTestHost`.
- **Exactly one image-snapshot bundle may exist, and this module is why.**
  Everything below described as "process-global" — the safe-area swizzle's
  depth counter and override globals, `SnapshotCaptureLock`, the animations
  save/restore — is *module*-global, so it is per copy of this module. Each
  `.xctest` statically embeds what it links, so two snapshot bundles co-loaded
  into one `StuffTestHost` process would hold two independent copies of that
  state while sharing one `UIView` method exchange: the depth counters flip
  parity against each other (captures silently render with the simulator's
  real safe-area insets) and neither capture lock can see the other's
  captures. Verified with `nm` on the built bundles — each defines its own
  private `_swizzleDepth`. Hence one bundle, `StuffSnapshotTests`; a new
  module's image suite joins it as another `sources` directory (root
  [`AGENTS.md`](../../AGENTS.md#targets)). `SnapshotKitTestingTests` is the
  sanctioned second consumer only because it runs in a *different* scheme, so
  the two never share a process.
- **The consuming bundle double-embeds `SnapshotKit`, tolerated and guarded.**
  Listing this product in `extraPackageProducts` statically embeds its
  dependency closure — including `SnapshotKit` — into the `.xctest`, while a
  dynamic-framework dependency (WhereUI) carries its own copy: the
  duplicate-type-metadata hazard from the root `AGENTS.md` "Targets" note,
  with `\.isCapturingSnapshot` as the type-keyed cross-boundary lookup at
  risk. There is no cleaner wiring (the pipeline must reach the bundle without
  ever linking into the UI framework), the trait lookup demonstrably resolves
  across both copies today, and
  `StuffSnapshotTests.SnapshotCaptureFlagProbeTests` fails loudly if the
  copies ever split — see the StuffSnapshotTests comment in
  `Project.swift` for the full topology.
- Re-exports `SnapshotKit` and `SnapshotTesting` so consumers need one import.
- Library target in [`Package.swift`](../../Package.swift).

## Invariants an agent can't re-derive

- **The rendering pipeline is a single function, not per-call code.** All
  captures (standard and accessibility) flow through the same async
  `renderSnapshotImage(...)` so a config's traits/size/type are the only thing
  that varies; callers assert on the returned image (its `async` is
  load-bearing — a synchronous `Snapshotting` pullback could never settle
  `.task`-driven content). Accessibility is just a `snapshotType`, wrapped
  before the same capture — not a separate path.
- **The compare sees on-disk bytes.** Every capture is round-tripped through
  PNG encoding before comparison so the perceptual diff runs on exactly what's
  flushed to disk — removing it re-opens the wide-gamut in-memory vs. sRGB
  reference flake (see `renderSnapshotImage`'s doc).
- **The runner fails fast, once, on setup problems.** A simulator that doesn't
  match the scheme's `SNAPSHOT_EXPECTED_*` pins, or two variants that would
  share one reference name, records a single clear issue and asserts nothing —
  never hundreds of confusing pixel diffs.
- **An unsettled capture is a failure, not a silent fallback.** `settleContent`
  returns a `SettleOutcome`, and `reportIfUnsettled` records an issue when the
  budget expires with the content still changing. Capturing whatever frame
  happened to be on screen is how a flaky reference lands, so don't "fix" a
  timeout by widening the budget — freeze the motion behind
  `\.isCapturingSnapshot`, or use `.settledAtLeast` only when the content is
  genuinely slow rather than endless.
- **Captures are single-tenant per process, enforced by `SnapshotCaptureLock`.**
  Every capture holds process-global state (the safe-area swizzle + override
  globals, the animations flag, the one `StuffTestHost` key window) across the
  settle phase's suspensions, so interleaved captures corrupt each other
  (verified — in-process parallel scheduling produced 24+ spurious mismatches;
  see the snapshot job comment in `.github/workflows/ci.yml`).
  `renderSnapshotImage` serializes captures through a FIFO `@MainActor` mutex,
  and the safe-area swizzle is depth-counted so unbalanced pairs can't flip the
  method-exchange parity (guarded by
  `StuffSnapshotTests.ConcurrentCaptureTests`). Nested captures — a hook
  rendering another snapshot — trap. Keep the suite serial anyway: concurrent
  scheduling now degrades to queued-serial rather than corrupt, gaining nothing.
- **Rendering runs in the host key window.** It requires `StuffTestHost`'s window
  (via `TestHostSupport.hostKeyWindow()`); it is not usable from a non-hosted
  bundle.
- **Determinism is pinned.** Reference images are only valid for the fixed
  simulator/scale; the pipeline overrides safe-area insets and quiesces
  animations so the physical device insets and in-flight transitions don't leak
  into the image. It also sets `SnapshotCaptureTrait` on the captured
  controller so views can read `\.isCapturingSnapshot` (SnapshotKit) and freeze
  never-settling motion at a deterministic phase — set on the *content*
  controller, not a wrapper, so it survives the intrinsic-measurement
  re-hosting.
- **Tile-and-stitch is load-bearing, not legacy.** UIKit still renders a blank
  image for views taller/wider than ~2000pt on the target toolchain (iOS 27.0 —
  verified by a probe during development, guarded by
  `StuffSnapshotTests.LargeViewCaptureTests`). Captures go through
  `SnapshotWrappingViewController` + `tileAndStitchImage`; don't remove the
  tiling on the assumption the bug is fixed without re-running that check.

## Testing

`SnapshotKitTestingTests` (`Tests/`, wired in `Project.swift`, in the
`Stuff-iOS-Tests` scheme) owns the pipeline's own regression tests: async-content
settle, concurrent-capture serialization, duplicate-identifier detection,
tile-and-stitch / full-content sizing, the pre-capture hook, the same-image
capture-flag surface, and safe-area composition (the swizzle zeroes the captured
root while an interior `safeAreaInset` still composes). They render through
`renderSnapshotImage` (so they need the `StuffTestHost` key window) but assert on
probed pixels via the `@_spi(Testing)` `PixelSample`/`probePixel` API rather than
LFS reference images — so the bundle is fast, has no `__Snapshots__/`, and runs
in the main `test` job, not the snapshot job. The matrixed image assertions
themselves are still exercised by the consumer bundle
(`StuffSnapshotTests`); the WhereUI↔bundle cross-boundary flag probe stays there
(`SnapshotCaptureFlagProbeTests`), since only a WhereUI-defined view can detect a
duplicate-`SnapshotKit` split.
