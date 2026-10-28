# StuffTestHost – Module Shape

StuffTestHost is the **iOS test host app** for hosted Swift Testing bundles. It is a UIKit-only `.app` target in [`Project.swift`](../../Project.swift), not a library. Every `unitTests(...)` bundle depends on it so Xcode injects the host at test time. See [`README.md`](README.md) for scope.

Read the root [`AGENTS.md`](../../AGENTS.md) first. That file owns build system, formatting, and global conventions.

## Scope & invariants

- **Use UIKit only.** Do not add feature UI, a SwiftUI entry point, or test assertions in production sources.
- **Provide a key window with a root VC.** Hosted tests assume `TestHostSupport.hostKeyWindow()` returns a window whose `rootViewController` is non-nil. Do not defer window creation. Do not leave root unset.
- **Stamp the window in `SceneDelegate`.** Set `isMainTestHostWindow` in `scene(_:willConnectTo:)`. `TestHostSupport.hostKeyWindow()` finds the host window only by that marker, not by "the first key window".
- **Keep the scene name aligned with the plist.** `AppDelegate` must modify and return the session's plist-derived configuration. Do not construct a separately named configuration that can drift from `Project.swift`.

## Don't add products here for `Bundle.module`

The host depends on `TestHostSupport` and nothing else. It embeds no resource bundles.

Hosted tests resolve `Bundle.module` through `PACKAGE_RESOURCE_BUNDLE_PATH`. Accessors use a DEBUG-only override. Every test scheme and `./test` point it at the built-products directory. See `packageResourceEnvironment` in [`Project.swift`](../../Project.swift) for the full story. That includes why Xcode 27 beta 4 made the override necessary and why the old WhereCore host embed cannot return.

If a resource is missing, do not add a product here. The embed breaks String Catalog symbol generation under beta 4.

If a resource is missing, do not add a product that `WhereUI` already embeds to a test bundle's `extraPackageProducts`. That mints duplicate type metadata. The root [`AGENTS.md`](../../AGENTS.md#never-double-link-a-product-whereui-already-carries) double-linking rule exists to prevent that.

## Testing

The host has no test target. `StuffTestHostSmokeTests` (in `LifecycleKitTests`) and every `TestHostSupport.show` call site cover its invariants.
