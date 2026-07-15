# Broadway – Module Group Shape

Broadway is a design-system stack imported into Stuff (git history preserved)
from its own repo. It centers on `BContext` — a type-keyed environment (traits,
themes, lazily-cached stylesheets) that flows through a UIKit + SwiftUI view
hierarchy. See [`README.md`](README.md).

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns build,
formatting, and global conventions. Read that first.

## Modules & dependencies

- **BroadwayCore** — foundation types (Foundation + UIKit). No sibling deps.
- **BroadwayUI** — components (SwiftUI + UIKit). Depends on BroadwayCore.
- **BroadwayCatalog** — showcase app. Depends on BroadwayUI.

UIKit hosting helpers for Broadway's hosted test bundles live in the shared
[`TestHostSupport`](../TestHostSupport) module (not a Broadway module).

Libraries live in [`Package.swift`](../../Package.swift); the app + hosted test
bundles in [`Project.swift`](../../Project.swift) (the shared `unitTests` helper,
`com.stuff.broadway.*` bundle IDs).

## Invariants an agent can't re-derive

- **`BContext` owns a cached `BStylesheets`.** Mutating `baseTraits`,
  `traitOverrides`, or `themes` must refresh that cache (the `didSet`s do);
  `stylesheets` is `@EquatableIgnored`, so it stays out of `BContext` equality.
- **`BRootViewController` defers setup** — child creation, trait observation,
  and context are wired on `viewIsAppearing`, so `context` is `nil` before the
  controller enters a valid hierarchy.
- **Broadway tests run in the shared `StuffTestHost`** via `TestHostSupport`
  (`show`, `hostKeyWindow`). The host stamps its window with
  `isMainTestHostWindow` and `hostKeyWindow()` selects only that window — don't
  reintroduce a "first key window" or `UIApplication.shared.delegate?.window`
  lookup.

## Testing

Hosted Swift Testing bundles (`BroadwayCoreTests`, `BroadwayUITests`,
`BroadwayCatalogTests`) run in `StuffTestHost` and link `TestHostSupport`. 1:1
test files per the root rules.
