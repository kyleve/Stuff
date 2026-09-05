# Flyover – Module Shape

Flyover is an app-agnostic SwiftUI developer browser for registered screen states and their push/modal relationships. See [`README.md`](README.md) for the public API and integration guide.

Read the root [`AGENTS.md`](../../AGENTS.md) first. That file owns build, formatting, and global conventions.

## Scope & dependencies

- **Flyover may import SwiftUI, SFSafeSymbols, BroadwayCore/BroadwayUI, and SnapshotKit.** It must not import WhereCore, WhereUI, persistence frameworks, or any app module.
- **Keep the static exporter generic over `ScreenID`.** Accept the hosted PNG operation as a closure. Never import SnapshotKitTesting.
- **Keep the web shell under [`Web/`](Web).** Do not make it an app-bundle resource or add remote assets.
- **Apps own their typed screen IDs, demo/synthetic state, catalog construction, and the DEBUG-only entry point** that hosts ``FlyoverView``.
- **Use English literals for strings** in this developer-only shared tool. An app localizes the entry point it adds to its own UI.

## Invariants

- **Keep catalog registration explicit and typed.** Do not add source scanning, build scripts, or macros without revisiting the API and build-cost tradeoff.
- **Present Flyover outside an ambient `NavigationStack`.** Use a separate presentation domain such as `fullScreenCover`.
- **Route Flyover appearance through `FlyoverStylesheet`.** `FlyoverView` seeds its Broadway root so the tool renders independently of its host. Follow the repo [`building-ui`](../../.agents/skills/building-ui/SKILL.md) skill for the general stylesheet, layout, accessibility, preview, and snapshot rules.
- **Keep overview screen content inert.** Enable native interaction only in the focused inspector. Per-frame controls remain interactive in both modes.
- **Give every screen a `NavigationStack` by default** so its navigation chrome renders in the frame. Use `.none` only for self-contained navigation roots and non-screen surfaces.
- **Keep variant content builders lazy.** Catalog construction must not instantiate off-screen views or their models.
- **Load the canvas from the viewport.** Keep at most six automatic screen trees live. A manually requested preview replaces that set with one tree. Presenting the focused inspector suspends the canvas set.
- **Open the canvas fitted to its first group's width.** Reserve whole-graph framing for the explicit Fit All action.
- **Cap automatic graph-depth stacks at the stylesheet row limit.** Spill overflow right inside one labeled depth band while preserving explicit `FlyoverPosition` values exactly.
- **Invoke variant builders through the serial deferred load coordinator.** Never invoke them synchronously from a SwiftUI `body`. Preview fixtures may open expensive in-memory stores.
- **Canvas preview readiness is the latest nonempty visible-load expectation.** Variant or generation changes supersede stale completions. Cancelled waiters must resume. `FlyoverSnapshotTests` awaits it before full-content measurement.
- **Keep global traits session-only.** Apply them to registered content, not Flyover chrome.
- **Register forward push/modal routes only.** Flyover derives Back/Dismiss cues from incoming routes.
- **Type erase only at the heterogeneous content/control registry boundary.**
- **Validate every stable screen and variant identifier before capture.** Use generated ordinals for image paths.
- **Serve only a validated generated artifact.** Bind to loopback unless the user selects LAN access.
- **Load every visible web screenshot.** Apply the residency limits only to offscreen preload candidates.
- **Preserve snapshot-backed capture intent.** Reject mixed sizing matrices unless the app supplies an explicit export policy.
- **Fail full-content export when sizing does not converge.** Never publish a viewport fallback.

## Testing

Swift Testing in [`Tests/`](Tests) covers catalog validation, graph layout, and session state. Rendering is pinned in [`SnapshotTests/`](SnapshotTests) through the module's `FlyoverSnapshotTests` target in the shared `StuffSnapshotTests` scheme.
