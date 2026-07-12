# Broadway

Broadway is a SwiftUI + UIKit design-system stack built around `BContext` — a
type-keyed environment carrying the current traits, themes, and a lazily-cached
stylesheet set that propagates through a UIKit/SwiftUI view hierarchy. It was
merged into Stuff from its own repository (git history preserved); the shared
iOS test host and build scaffolding are Stuff's.

## Modules

- **BroadwayCore** ([BroadwayCore/](BroadwayCore/)) — foundation types:
  `BContext`, `BTraits`, `BThemes`, `BStylesheets`, `BAccessibility`, plus
  utilities (`AnyEquatable`, `CopyOnWrite`, `TypeIdentifier`). Foundation + UIKit.
- **BroadwayUI** ([BroadwayUI/](BroadwayUI/)) — UIKit/SwiftUI components that
  own and propagate `BContext` (`BRootViewController` and its SwiftUI-native
  counterpart `BRootView` / `.broadwayRoot(themes:)`,
  `BTraitOverridesViewController`). Depends on BroadwayCore.
- **BroadwayTesting** ([BroadwayTesting/](BroadwayTesting/)) — UIKit test
  helpers (`show`, `waitFor`, ...) for hosted Swift Testing bundles.
- **BroadwayCatalog** ([BroadwayCatalog/](BroadwayCatalog/)) — a showcase app
  for BroadwayUI components.

## Build & test

Libraries are declared in the root [`Package.swift`](../../Package.swift); the
Catalog app and hosted test bundles in [`Project.swift`](../../Project.swift)
(bundle IDs `com.stuff.broadway.*`). Run e.g. `tuist test BroadwayCoreTests`,
`tuist test BroadwayUITests`, or `tuist test BroadwayCatalogTests`.
