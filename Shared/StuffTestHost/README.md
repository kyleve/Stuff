# StuffTestHost

A minimal UIKit iOS app that **hosts** Swift Testing unit-test bundles. Hosted
tests run in a real process with a key window and root view controller so
`WhereTesting.show(_:perform:)` can drive UIKit appearance lifecycle and SwiftUI
`onAppear` in tests.

The host intentionally does almost nothing: blank root view, no business logic.
Feature code under test lives in SPM libraries; test bundles link those libraries
plus `WhereTesting` and run inside this app (see [`Project.swift`](../../Project.swift)).

## What it provides

- `@main` [`AppDelegate`](Sources/AppDelegate.swift) — scene configuration for
  the default window scene.
- [`SceneDelegate`](Sources/SceneDelegate.swift) — creates a key window with an
  empty `UIViewController` as root.

## Bundle.module embedding

Some SPM resources (notably WhereCore GeoJSON region data) resolve via
`Bundle.module` at runtime. In a hosted test, that bundle must be **embedded in
the host app**, not only linked into the test bundle — otherwise `Bundle.module`
traps when code first touches those resources.

`StuffTestHost` depends on `WhereCore` in `Project.swift` so Tuist embeds
`Stuff_WhereCore.bundle` into the host. See [`AGENTS.md`](AGENTS.md) for the
checklist when adding modules with processed resources.

## Testing the host

Host invariants (key window + root view controller) are asserted by
[`StuffTestHostSmokeTests`](../LifecycleKit/Tests/StuffTestHostSmokeTests.swift)
in `LifecycleKitTests`. Individual feature bundles rely on `WhereTesting.show`
for deeper lifecycle coverage.
