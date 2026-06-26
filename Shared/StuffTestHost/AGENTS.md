# StuffTestHost – Module Shape

StuffTestHost is the **iOS test host app** for hosted Swift Testing bundles.
It is not a library — Tuist declares it as an `.app` target in
[`Project.swift`](../../Project.swift). See [`README.md`](README.md) for scope.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns build
system, formatting, and global conventions. Read that first.

## Scope & dependencies

- **UIKit only.** No feature UI, no SwiftUI entry point, no test assertions in
  production sources.
- Bundle ID `com.stuff.stufftesthost`. Every `unitTests(...)` target in
  `Project.swift` lists `.target(name: "StuffTestHost")` as a dependency so
  Xcode injects the host at test time.

## Key types

- [`AppDelegate`](Sources/AppDelegate.swift) — `@MainActor @main`; returns a
  `UISceneConfiguration` named `"Default Configuration"` with
  `SceneDelegate` as delegate (mirrors the plist scene manifest).
- [`SceneDelegate`](Sources/SceneDelegate.swift) — `@MainActor`; on connect,
  creates `UIWindow`, sets an empty `UIViewController` as root, calls
  `makeKeyAndVisible()`.

## Invariants to preserve

- **Key window with root VC.** Hosted tests assume `WhereTesting.hostKeyWindow()`
  returns a window whose `rootViewController` is non-nil. Do not defer window
  creation or leave root unset.
- **Scene name matches plist.** `"Default Configuration"` must stay aligned with
  `UIApplicationSceneManifest` in `Project.swift` and
  `configurationForConnecting`.

## Bundle.module embedding checklist

When a hosted test bundle exercises SPM code that loads **processed resources**
via `Bundle.module`, the resource bundle must be embedded in **this host app**:

1. Confirm the library uses `.process(...)` / resource targets in
   [`Package.swift`](../../Package.swift).
2. Add `.package(product: "<Library>")` to the `StuffTestHost` target in
   [`Project.swift`](../../Project.swift) (not only to the test bundle).
3. Regenerate the Xcode project (`./ide --no-open`) and verify
   `Stuff_<Module>.bundle` appears in the host's "Copy Bundle Resources" (or
   Tuist's embed output).
4. Add or extend a smoke test that touches the resource path (e.g.
   `RegionAttributor.shared` for WhereCore) so a missing embed fails in CI.

Today the host embeds **WhereCore** for GeoJSON region polygons even when a test
bundle does not import WhereCore — a deliberate trade-off documented here until
a slimmer host split is designed.

## Conventions

- Keep `@MainActor` on `AppDelegate` and `SceneDelegate` aligned with the
  production Where app delegate isolation.
- Source file names match types (`AppDelegate.swift`, not `TestHostApp.swift`).

## Testing

The host itself has no test target. Invariants are covered by
[`StuffTestHostSmokeTests`](../LifecycleKit/Tests/StuffTestHostSmokeTests.swift)
in `LifecycleKitTests` and indirectly by every `WhereTesting.show` call site.
