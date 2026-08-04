# StuffTestHost – Module Shape

StuffTestHost is the **iOS test host app** for hosted Swift Testing bundles —
a UIKit-only `.app` target declared in [`Project.swift`](../../Project.swift)
(not a library). Every `unitTests(...)` bundle depends on it so Xcode injects
the host at test time. See [`README.md`](README.md) for scope.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns build
system, formatting, and global conventions. Read that first.

## Scope & invariants

- **UIKit only** — no feature UI, no SwiftUI entry point, no test assertions
  in production sources.
- **Key window with root VC.** Hosted tests assume
  `TestHostSupport.hostKeyWindow()` returns a window whose `rootViewController`
  is non-nil; don't defer window creation or leave root unset.
- **`SceneDelegate` stamps the window `isMainTestHostWindow`.**
  `TestHostSupport.hostKeyWindow()` finds the host window *only* by that marker
  (not "the first key window"), so the stamp is load-bearing — keep it in
  `scene(_:willConnectTo:)`.
- **The plist owns the scene name.** `AppDelegate` must modify and return the
  session's plist-derived configuration; don't construct a separately named
  configuration that can drift from `Project.swift`.

## Don't add products here for `Bundle.module`

The host depends on `TestHostSupport` and nothing else, and embeds no resource
bundles. Hosted tests' `Bundle.module` lookups resolve through
`PACKAGE_RESOURCE_BUNDLE_PATH` — the accessors' own DEBUG-only override,
pointed at the built-products directory by every test scheme and by `./test`
(see `packageResourceEnvironment` in [`Project.swift`](../../Project.swift)
for the whole story, including why Xcode 27 beta 4 made the override
necessary and why the old WhereCore host embed cannot come back).

Never fix a missing-resource failure by adding a product here (the embed
breaks String Catalog symbol generation under beta 4) or by adding a product
`WhereUI` already embeds to a test bundle's `extraPackageProducts` — that
mints the duplicate type metadata the root
[`AGENTS.md`](../../AGENTS.md#never-double-link-a-product-whereui-already-carries)
double-linking rule exists to prevent.

## Testing

The host itself has no test target; its invariants are covered by
`StuffTestHostSmokeTests` (in `LifecycleKitTests`) and every
`TestHostSupport.show` call site.
