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

- **The rendering pipeline is a single strategy, not per-call code.** All
  captures (standard and accessibility) flow through the same
  `Snapshotting<UIViewController, UIImage>` so a config's traits/size/type are the
  only thing that varies. Accessibility is just a `snapshotType`, wrapped before
  the same capture — not a separate path.
- **Rendering runs in the host key window.** It requires `StuffTestHost`'s window
  (via `TestHostSupport.hostKeyWindow()`); it is not usable from a non-hosted
  bundle.
- **Determinism is pinned.** Reference images are only valid for the fixed
  simulator/scale; the pipeline overrides safe-area insets and quiesces
  animations so the physical device insets and in-flight transitions don't leak
  into the image.
- The porting note for the rendering workarounds (safe-area override, size
  stabilization, cursor hiding, accessibility wrapper) is recorded only here in
  the repo — the source files carry no third-party attribution by request.

## Testing

No dedicated test bundle; exercised by every `*SnapshotTests` bundle that calls
`assertSnapshots` (currently `WhereUISnapshotTests`).
