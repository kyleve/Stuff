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

Some SPM resources (notably RegionKit's GeoJSON region data and the string
catalogs) resolve via `Bundle.module` at runtime. The host embeds no resource
bundles for that: every test scheme sets `PACKAGE_RESOURCE_BUNDLE_PATH` — the
generated accessors' own first lookup candidate — to the built-products
directory, and `./test` delivers the concrete path (xcodebuild doesn't expand
build-setting macros in scheme environment variables, so the scheme value
covers Xcode-IDE runs and the script covers everything else).

The override exists because Xcode 27 beta 4's package linking separates a
product's classes from its resource bundle for hosted tests, defeating the
accessors' default candidates — and the old remedy, embedding WhereCore in
this host, breaks String Catalog symbol generation under the same beta. The
`packageResourceEnvironment` note in [`Project.swift`](../../Project.swift)
carries the full history and how to retire the override.

## Testing the host

Host invariants (key window + root view controller) are asserted by
[`StuffTestHostSmokeTests`](../LifecycleKit/Tests/StuffTestHostSmokeTests.swift)
in `LifecycleKitTests`. Individual feature bundles rely on `TestHostSupport.show`
for deeper lifecycle coverage.
