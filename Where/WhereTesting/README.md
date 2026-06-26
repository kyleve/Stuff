# WhereTesting

UIKit test helpers for **hosted** Swift Testing bundles. Tests run inside
`StuffTestHost`, which provides a real key window; this module places view
controllers in that window and pumps the run loop until async UI state settles.

WhereTesting is for test bundles only — do not link it from production app
targets.

## Installation

`WhereTesting` is a local SPM library (`Where/WhereTesting`). Hosted test
bundles get it automatically via the `unitTests` helper in
[`Project.swift`](../../Project.swift), which also wires `StuffTestHost`.

```swift
.target(name: "YourTests", dependencies: [
    .target(name: "YourModule"),
    .target(name: "WhereTesting"),
])
```

(Tuist's `unitTests(...)` helper adds both `WhereTesting` and `StuffTestHost`.)

## Public API

### Window access

```swift
@MainActor public func hostKeyWindow() -> UIWindow?
```

Returns the test host's key window, or the first window in the first connected
scene.

### Hosting a view controller

```swift
@MainActor public func show<ViewController: UIViewController>(
    _ viewController: ViewController,
    loadAndPlaceView: Bool = true,
    perform test: (ViewController) throws -> Void,
) throws
```

Adds `viewController` as a child of the host root VC, optionally places its view,
runs `test`, then tears down in UIKit container order (`willMove` → remove view
→ `removeFromParent`). Speeds up animations via `layer.speed = 100` for the
duration (reset in `defer`).

### Run-loop helpers

```swift
@MainActor public func waitFor(timeout:predicate:) throws
@MainActor public func waitForOneRunloop()
@MainActor public func renders(within:_:) -> Bool
```

`waitFor` throws `WhereTestingError` on timeout. `renders(within:)` returns
whether a condition became true within the budget (for asserting something never
appears).

### WhereCore test double

[`InMemoryKeyValueStore`](Sources/InMemoryKeyValueStore.swift) implements
`WhereCore.KeyValueStore` in memory with plist round-trip on each `set`, matching
`UserDefaults` persistence constraints.

**Note:** Because this type lives in WhereTesting and depends on WhereCore, every
hosted bundle that links WhereTesting also links WhereCore today. Splitting
UIKit-only helpers from the store double is tracked as a needs-design item in
[`MODULE_AUDIT.md`](../../MODULE_AUDIT.md).

## Typical usage

```swift
import Testing
import UIKit
import WhereTesting

@MainActor
struct MyHostingTests {
    @Test func viewAppears() throws {
        let vc = UIViewController()
        try show(vc) { hosted in
            try waitFor { hosted.view.window != nil }
        }
    }
}
```

See [`ShowLifecycleTests`](../../Shared/LifecycleKit/Tests/ShowLifecycleTests.swift)
for UIKit appearance and SwiftUI `onAppear` coverage.

## Testing

WhereTesting has no dedicated test bundle yet. Behavior is exercised indirectly
via hosted tests in `LifecycleKitTests`, `WhereUITests`, and others.
