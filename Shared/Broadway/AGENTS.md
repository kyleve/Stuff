# Broadway – Module Group Shape

Broadway is a design-system stack centered on `BContext`. It is a type-keyed environment (traits, themes, lazily-cached stylesheets) that flows through a UIKit and SwiftUI view hierarchy. See [`README.md`](README.md).

Read the root [`AGENTS.md`](../../AGENTS.md) first. That file owns build, formatting, and global conventions.

## Modules & dependencies

- **BroadwayCore** — foundation types (Foundation and UIKit). No sibling deps.
- **BroadwayUI** — components (SwiftUI and UIKit). Depends on BroadwayCore.
- **BroadwayCatalog** — showcase app. Depends on BroadwayUI and SFSafeSymbols.

UIKit hosting helpers for Broadway's hosted test bundles live in the shared [`TestHostSupport`](../TestHostSupport) module, not in a Broadway module.

Libraries live in [`Package.swift`](../../Package.swift). The app and hosted test bundles live in [`Project.swift`](../../Project.swift) (the shared `unitTests` helper, `com.stuff.broadway.*` bundle IDs).

## Invariants an agent can't re-derive

- **Run Broadway's hosted bundles in the shared `StuffTestHost`.** `BroadwayCoreTests` and `BroadwayUITests` use `TestHostSupport` (`show`, `hostKeyWindow`). The host stamps its window with `isMainTestHostWindow`. `hostKeyWindow()` selects only that window. Do not reintroduce a "first key window" or `UIApplication.shared.delegate?.window` lookup.

## Testing

Run `./test BroadwayCoreTests`, `./test BroadwayUITests`, or `./test BroadwayCatalogTests`. The Catalog bundle is currently hosted by the **BroadwayCatalog** app itself. That deviates from the shared-host convention. Track it in [`TODOs.md`](TODOs.md). Use 1:1 test files per the root rules.
