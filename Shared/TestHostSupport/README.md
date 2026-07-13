# TestHostSupport

UIKit hosting and run-loop helpers for the hosted Swift Testing bundles that run
inside [`StuffTestHost`](../StuffTestHost). It is the single, dependency-free home
for the helpers that used to be duplicated across `WhereTesting` and
`BroadwayTesting`.

## Install

Library product in the root [`Package.swift`](../../Package.swift)
(`Shared/TestHostSupport/Sources`). It is **test-only** — depended on by hosted
test bundles (via the `unitTests` helper in [`Project.swift`](../../Project.swift))
and by the `StuffTestHost` app itself (so its `SceneDelegate` can mark the host
window). Never link it from a shipping app target.

```swift
import TestHostSupport
```

## Quick start

```swift
import Testing
import TestHostSupport

@MainActor
@Test func rendersContent() throws {
    let vc = MyViewController()
    try show(vc) { vc in
        try waitFor { vc.isFullyLoaded }
        #expect(vc.titleLabel.text == "Hello")
    }
}
```

## Public API

- `show(_:loadAndPlaceView:timeout:perform:)` — hosts a `UIViewController` in the
  test host's main window for the duration of `perform`, driving the real UIKit
  appearance lifecycle (`addChild` → attach → `didMove(toParent:)`, reversed on
  teardown) and restoring `layer.speed` even if the body throws.
- `hostKeyWindow()` — the host's designated window (see below), or `nil` before
  the scene connects.
- `waitFor(timeout:predicate:)` — pump the run loop until a predicate holds.
- `waitForOneRunloop()` — drive one brief run-loop pass.
- `UIWindow.isMainTestHostWindow` — the marker the host stamps on its window.

## How it works

`StuffTestHost`'s `SceneDelegate` creates one window, gives it a root view
controller, and sets `window.isMainTestHostWindow = true`. `hostKeyWindow()`
selects *that* window rather than "any key window", so a stray system window
(keyboard, text-effects) or a window a test created can never stand in for it.

`show()` waits (pumping the run loop) for the host window and its root view
controller to exist before hosting, so a test that runs before the host scene has
connected doesn't spuriously fail.

## Contracts & limitations

- **The marker is an associated object keyed on a name-interned `Selector`.**
  This module is a static library embedded into every image that links it (the
  host app and each `.xctest` bundle), so the key must resolve to the same pointer
  in every image — a per-image `static var key` would not. See the doc comment on
  `isMainTestHostWindow`.
- **Main-actor only.** All entry points are `@MainActor`; call them from
  `@MainActor` test suites.
- **No assertions.** These are hosting/timing helpers, not a testing framework —
  they `throw` on timeout so a test fails loudly rather than hanging.
