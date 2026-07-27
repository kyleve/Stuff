# StuffTestHost

A minimal UIKit iOS app that **hosts** Swift Testing unit-test bundles. Hosted
tests run in a real process with a key window and root view controller so
`TestHostSupport.show(_:perform:)` can drive UIKit appearance lifecycle and SwiftUI
`onAppear` in tests.

The host intentionally does almost nothing: blank root view, no business logic.
Feature code under test lives in SPM libraries; test bundles link those libraries
plus `TestHostSupport` and run inside this app (see [`Project.swift`](../../Project.swift)).

## What it provides

- `@main` [`AppDelegate`](Sources/AppDelegate.swift) — scene configuration for
  the default window scene.
- [`SceneDelegate`](Sources/SceneDelegate.swift) — creates a key window with an
  empty `UIViewController` as root and marks it `isMainTestHostWindow` (from
  `TestHostSupport`) so `hostKeyWindow()` can find it.

## Bundle.module and resources

Some SPM resources (notably WhereCore's GeoJSON region data) resolve via
`Bundle.module` at runtime. That accessor looks the bundle up with
`Bundle(for:)` — the bundle the code is linked into — and on Xcode 27 each
`.xctest` carries its own copies of the resource bundles for what it links, so a
hosted test finds them in the test bundle and never falls back to the host's
`Bundle.main`.

So the host embeds no resource bundles and depends on nothing but
`TestHostSupport`. If a bundle hits a missing resource, give *that* bundle a
dependency on the product that owns it rather than adding the product to the
host, which would make every unrelated bundle in the scheme pay for it. The
`StuffTestHost` target in [`Project.swift`](../../Project.swift) carries the
long form of this.

## Testing the host

Host invariants (key window + root view controller) are asserted by
[`StuffTestHostSmokeTests`](../LifecycleKit/Tests/StuffTestHostSmokeTests.swift)
in `LifecycleKitTests`. Individual feature bundles rely on `TestHostSupport.show`
for deeper lifecycle coverage.
