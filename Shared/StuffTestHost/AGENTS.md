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
- **Scene name matches plist.** `"Default Configuration"` is spelled in two
  places — `AppDelegate`'s `configurationForConnecting` and the
  `UIApplicationSceneManifest` in `Project.swift` — and they must stay aligned
  or the scene never connects and every hosted test loses its window.

## Don't add products here for `Bundle.module`

The host depends on `TestHostSupport` and nothing else, and embeds no resource
bundles. A hosted test's `Bundle.module` resolves through `Bundle(for:)` — the
`.xctest`, which on Xcode 27 carries its own copies of the resource bundles for
the code it links — so it never falls back to the host's `Bundle.main`. That
follows from every product linking statically into each consumer, which the root
[`AGENTS.md`](../../AGENTS.md#never-double-link-a-product-whereui-already-carries)
records.

A missing-resource failure is therefore fixed on the *test bundle* that needs
it, by depending on the product that owns the resource; adding the product to
the host makes every unrelated bundle in the scheme carry it. The
`StuffTestHost` target in [`Project.swift`](../../Project.swift) records why the
host's old `WhereCore` dependency was removed.

## Testing

The host itself has no test target; its invariants are covered by
`StuffTestHostSmokeTests` (in `LifecycleKitTests`) and every
`TestHostSupport.show` call site.
