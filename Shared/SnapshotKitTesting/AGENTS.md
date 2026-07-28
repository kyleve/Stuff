# SnapshotKitTesting – Module Shape

The test-only half of the snapshot-testing framework: the capture + comparison
pipeline and the `assertSnapshots` runner over a [`SnapshotKit`](../SnapshotKit)
matrix. See [`README.md`](README.md).

Complements the root [`AGENTS.md`](../../AGENTS.md) — read that first.

## Scope & dependencies

- Depends on `SnapshotKit`, `TestHostSupport`, `SnapshotTesting`
  (swift-snapshot-testing), and `AccessibilitySnapshot` (cashapp). It links the
  comparison engine + XCTest/Testing, so it is **only** consumed by test
  bundles via `extraPackageProducts` — the per-module image bundles
  (`WhereUISnapshotTests`, `PeriscopeToolsSnapshotTests`,
  `SwiftDataInspectorSnapshotTests`, gathered into the `StuffSnapshotTests`
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
- **The compare sees on-disk bytes.** Every capture round-trips through PNG
  encoding before comparison; removing it re-opens the wide-gamut vs. sRGB
  flake (see `renderSnapshotImage`'s doc).
- **The runner fails fast, once, on setup problems** (a simulator that doesn't
  match the `SNAPSHOT_EXPECTED_*` pins, two variants sharing one reference
  name) — one clear issue, never hundreds of pixel diffs.
- **An unsettled capture is a failure, not a silent fallback.** Don't "fix" a
  settle timeout by widening the budget — freeze the motion behind
  `\.isCapturingSnapshot`, or use `.settledAtLeast` only for genuinely slow
  (not endless) content.
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
- **A settle phase costs its floor, not its passes.** Measured over all 260
  references with `SNAPSHOT_TIMING=1`: 192 captures sit at 0.25-0.35s, the
  `minDuration` floor plus a pass or two, and the floor accounts for ~70s of
  the ~84s of settle time. The render passes themselves are ~14s across the
  whole suite. So making passes cheaper is worth ~11% and removing floors is
  worth ~54% — but a floor can only come off with a **deterministic completion
  seam** for that case (as `root.LoggedIn` does by awaiting `launcher.run()`
  from `onReadyToSnapshot`), never by introspection.

## Two things measured and rejected — don't re-derive them

- **Quiescence can't replace the pixel digest.** `SNAPSHOT_SETTLE` selects
  `pixel` (default), `quiescence` (a `beforeWaiting` run-loop observer plus a
  recursive `needsLayout`/`needsDisplay`/`animationKeys` walk), or `both`, which
  runs them together and reports disagreements while letting the digest keep the
  verdict. Run in `both` mode over all 260 references: 226 settle phases, 133
  with some disagreement, and **11 where quiescence declared settled *earlier*
  than the digest** — every one a `Loaded_*` case whose content arrives late.
  That is the one dangerous direction (it would capture a frame no reference
  recorded), and it is exactly what `settleContent`'s doc comment predicts: a
  SwiftUI update deep in the hosted tree never dirties the root, and flags read
  after a commit has flushed look clean. The mechanism is kept so the experiment
  is re-runnable after a toolchain change; it is not a candidate default.
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
