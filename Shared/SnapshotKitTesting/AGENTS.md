# SnapshotKitTesting – Module Shape

The test-only half of the snapshot-testing framework: the capture + comparison
pipeline and the `assertSnapshots` runner over a [`SnapshotKit`](../SnapshotKit)
matrix. See [`README.md`](README.md).

Complements the root [`AGENTS.md`](../../AGENTS.md) — read that first.

## Scope & dependencies

- Depends on `SnapshotKit`, `TestHostSupport`, `SnapshotTesting`
  (swift-snapshot-testing), and `AccessibilitySnapshot` (cashapp). It links the
  comparison engine + XCTest/Testing, so it is **only** consumed by
  `*SnapshotTests` bundles via `extraPackageProducts` — **never** a shipping app
  or `StuffTestHost`.
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
- **Captures are single-tenant per process.** Every test renders into the one
  `StuffTestHost` key window and the settle phase suspends, so xcodebuild
  parallel testing corrupts captures (verified; see the snapshot job comment in
  `.github/workflows/ci.yml`) — keep the suite serial.
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
  image for views taller/wider than ~2000pt on the target toolchain (iOS 26.2 —
  verified by a probe during development, guarded by
  `WhereUISnapshotTests.LargeViewCaptureTests`). Captures go through
  `SnapshotWrappingViewController` + `tileAndStitchImage`; don't remove the
  tiling on the assumption the bug is fixed without re-running that check.
- The rendering workarounds (safe-area override, tile-and-stitch, size
  stabilization, cursor hiding, animation quiescing, accessibility wrapper) are
  adapted from a prior art snapshot library; that provenance is recorded only
  here in the repo — the source files carry no third-party attribution by request.

## Testing

No dedicated test bundle; exercised by every `*SnapshotTests` bundle that calls
`assertSnapshots` (currently `WhereUISnapshotTests`).
