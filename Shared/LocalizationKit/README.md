# LocalizationKit

SwiftUI-capable SPM library for deferred, catalog-backed localization. It owns
the framework-level tooling; each app module keeps its own `LocalizedStrings`
enum and `Localizable.xcstrings` catalog.

## Key types

- **`LocalizedString`** — a user-facing string that hasn't been localized yet.
  It wraps a `@Sendable` builder closure and resolves lazily when you call
  `.localized(_:)`. Per-module `LocalizedStrings` enums return these instead of
  `String`, deferring the catalog lookup to the point of display so a call site
  can override the locale. It's `Sendable`, so producers can cache each string
  in a `static let` and pass it across isolation boundaries.
- **`LocalizationConfig`** — a small value type (today just a `Locale`) passed
  to `.localized(config)` to render against a locale other than the process
  default.
- **`LocalizedString.catalog(_:_:bundle:)`** — the generic factory that performs
  a `String(localized:bundle:locale:)` lookup. Each module wraps it in a thin
  `.module(_:_:)` that passes `bundle: .module`.
- **`Text(localized:)`** and **`View` overloads** of `navigationTitle`,
  `accessibilityLabel`, and `accessibilityHint` — resolve a `LocalizedString`
  at the point of display.

## Quick start

```swift
import LocalizationKit

// In each module's LocalizedString+Module.swift:
extension LocalizedString {
    static func module(_ key: StaticString, _ value: String.LocalizationValue) -> LocalizedString {
        .catalog(key, value, bundle: .module)
    }
}

// In LocalizedStrings.swift:
static let greeting: LocalizedString = .module("greeting", "Hello")

// At a SwiftUI call site (with dot-syntax accessors on LocalizedString):
Text(localized: .primary.emptyDescription)
.navigationTitle(.settings.title)

// Where a plain String is needed:
Button(LocalizedStrings.Common.done.localized) { … }
```

Add shared types under [`Sources/`](Sources/) and wire consumers in
[`Package.swift`](../../Package.swift). Run tests with
`tuist test LocalizationKitTests`.
