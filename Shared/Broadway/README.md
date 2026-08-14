# Broadway

Broadway is a SwiftUI + UIKit design-system stack built around `BContext`.
`BContext` is a type-keyed environment carrying the current traits, themes, and a lazily-cached stylesheet set.
It propagates through a UIKit/SwiftUI view hierarchy.
It was merged into Stuff from its own repository (git history preserved).
The shared iOS test host and build scaffolding are Stuff's.

## Modules

- **BroadwayCore** ([BroadwayCore/](BroadwayCore/)) — foundation types: `BContext`, `BTraits`, `BThemes`, `BStylesheets`, `BAccessibility`, plus utilities (`AnyEquatable`, `CopyOnWrite`, `TypeIdentifier`). Foundation + UIKit.
- **BroadwayUI** ([BroadwayUI/](BroadwayUI/)) — UIKit/SwiftUI components that own and propagate `BContext` (`BRootViewController` and its SwiftUI-native counterpart `BRootView` / `.broadwayRoot(themes:)`, `BTraitOverridesViewController`). Depends on BroadwayCore.
- **BroadwayCatalog** ([BroadwayCatalog/](BroadwayCatalog/)) — a showcase app for BroadwayUI components.

UIKit hosting helpers (`show`, `waitFor`, …) for Broadway's hosted Swift Testing bundles live in the shared [`TestHostSupport`](../TestHostSupport) module.

## Build & test

Libraries are declared in the root [`Package.swift`](../../Package.swift).
The Catalog app and hosted test bundles are in [`Project.swift`](../../Project.swift) (bundle IDs `com.stuff.broadway.*`).
Run `./test BroadwayCoreTests`, `./test BroadwayUITests`, or `./test BroadwayCatalogTests`.
