# Broadway – Module Group Shape

Broadway is a design-system stack centered on `BContext` — a type-keyed
environment (traits, themes, lazily-cached stylesheets) that flows through a
UIKit + SwiftUI view hierarchy. See [`README.md`](README.md).

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns build,
formatting, and global conventions. Read that first.

## Modules & dependencies

- **BroadwayCore** — foundation types (Foundation + UIKit). No sibling deps.
- **BroadwayUI** — components (SwiftUI + UIKit). Depends on BroadwayCore.
- **BroadwayCatalog** — showcase app. Depends on BroadwayUI and SFSafeSymbols.

UIKit hosting helpers for Broadway's hosted test bundles live in the shared
[`TestHostSupport`](../TestHostSupport) module (not a Broadway module).

Libraries live in [`Package.swift`](../../Package.swift); the app + hosted test
bundles in [`Project.swift`](../../Project.swift) (the shared `unitTests` helper,
`com.stuff.broadway.*` bundle IDs).

## Invariants an agent can't re-derive

- **Broadway's hosted bundles (`BroadwayCoreTests`, `BroadwayUITests`) run in
  the shared `StuffTestHost`** via `TestHostSupport`
  (`show`, `hostKeyWindow`). The host stamps its window with
  `isMainTestHostWindow` and `hostKeyWindow()` selects only that window — don't
  reintroduce a "first key window" or `UIApplication.shared.delegate?.window`
  lookup.

## Testing

Run `./test BroadwayCoreTests`, `./test BroadwayUITests`, or
`./test BroadwayCatalogTests`. The Catalog bundle is currently hosted by the
**BroadwayCatalog** app itself — a deviation from the shared-host convention,
tracked in [`TODOs.md`](TODOs.md). 1:1 test files per the root rules.
