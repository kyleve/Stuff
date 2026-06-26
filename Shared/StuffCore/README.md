# StuffCore

Foundation-only SPM library for code shared across Stuff apps. It currently
hosts the localization primitives every module builds its strings on:

- **`LocalizedString`** — a user-facing string that hasn't been localized yet.
  It wraps a builder closure (`(LocalizationConfig?) -> String`) and resolves
  lazily when you call `.localized(_:)`. Per-module `LocalizedStrings` enums
  return these instead of `String`, deferring the catalog lookup to the point
  of display so a call site can override the locale.
- **`LocalizationConfig`** — a small value type (today just a `Locale`) passed
  to `.localized(config)` to render against a locale other than the process
  default.

## Quick start

```swift
import StuffCore

// A producer (usually a generated-by-convention LocalizedStrings enum):
let greeting = LocalizedString { config in
    String(
        localized: "greeting",
        defaultValue: "Hello",
        bundle: .module,
        locale: config?.locale ?? .current,
    )
}

greeting.localized()                                          // "Hello"
greeting.localized(LocalizationConfig(locale: .init(identifier: "fr")))
```

Because the closure captures any interpolated arguments and defers to the
standard `String(localized:)` lookup, parameterized and pluralized strings need
no extra machinery here — the catalog (`Localizable.xcstrings`) owns the plural
variations.

Add shared types under [`Sources/`](Sources/) and wire consumers in
[`Package.swift`](../../Package.swift). Run tests with `tuist test StuffCoreTests`.
