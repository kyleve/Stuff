# StuffCore

A **scaffold** SPM library reserved for code shared across multiple Stuff apps
(Where today, others later). It ships a placeholder API so the build graph,
hosted test bundle, and module-doc conventions are in place before the first real
shared type lands here.

Nothing in production imports `StuffCore` yet — when shared logic appears (e.g.
cross-app preferences helpers, common identifiers), add it under
[`Sources/`](Sources/) and wire the first consumer in `Package.swift`.

## Installation

`StuffCore` is a local SPM library in this repo (`Shared/StuffCore`). Add it to a
target's dependencies in [`Package.swift`](../../Package.swift):

```swift
.target(name: "YourModule", dependencies: [.target(name: "StuffCore")])
```

## Public API (placeholder)

```swift
public enum StuffCore {
    /// Bumped when the module gains real shared surface area.
    public static let version = 1
}
```

The `version` constant exists only to keep `StuffCoreTests` compiling until a
real API replaces it.

## Testing

`StuffCoreTests` runs in `StuffTestHost` (see [`Project.swift`](../../Project.swift)).
Run it in isolation with:

```bash
mise exec -- tuist test StuffCoreTests --no-selective-testing -- \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
```
