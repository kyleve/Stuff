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
  `WhereTesting.hostKeyWindow()` returns a window whose `rootViewController`
  is non-nil; don't defer window creation or leave root unset.
- **Scene name matches plist.** `"Default Configuration"` must stay aligned
  between `AppDelegate`, `SceneDelegate`, and the `UIApplicationSceneManifest`
  in `Project.swift`.

## Bundle.module embedding checklist

When a hosted test bundle exercises SPM code that loads **processed
resources** via `Bundle.module`, the resource bundle must be embedded in
**this host app**:

1. Confirm the library uses `.process(...)` resources in
   [`Package.swift`](../../Package.swift).
2. Add `.package(product: "<Library>")` to the `StuffTestHost` target in
   [`Project.swift`](../../Project.swift) (not only to the test bundle).
3. Regenerate (`./ide --no-open`) and verify `Stuff_<Module>.bundle` lands in
   the host's embedded resources.
4. Add or extend a smoke test that touches the resource path so a missing
   embed fails in CI.

Today the host embeds **WhereCore** for GeoJSON region polygons even when a
test bundle doesn't import WhereCore — a deliberate trade-off documented here
until a slimmer host split is designed.

## Testing

The host itself has no test target; its invariants are covered by
`StuffTestHostSmokeTests` (in `LifecycleKitTests`) and every
`WhereTesting.show` call site.
