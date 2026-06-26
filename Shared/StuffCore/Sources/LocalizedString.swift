import Foundation

/// Options that influence how a ``LocalizedString`` resolves.
///
/// Today this only carries a `locale`, letting a caller render a string in a
/// locale other than the process default (e.g. a per-view override). It is a
/// value type so it can be threaded through SwiftUI without surprises.
public struct LocalizationConfig: Sendable, Hashable {
    /// The locale to resolve the string against.
    public var locale: Locale

    public init(locale: Locale) {
        self.locale = locale
    }
}

/// A user-facing string that has **not been localized yet**.
///
/// Producers (the per-module `LocalizedStrings` enums) return a
/// `LocalizedString` instead of a `String`, deferring the actual catalog
/// lookup until ``localized(_:)`` is called. Each instance wraps a builder
/// closure that performs a standard `String(localized:bundle:locale:)` lookup —
/// the closure captures any interpolated arguments, so parameterized and
/// pluralized strings need no special machinery here.
///
/// Deferring resolution is what lets a call site override the locale (via
/// ``LocalizationConfig``) at the moment of display rather than at the moment
/// the string is referenced.
public struct LocalizedString {
    private let build: (LocalizationConfig?) -> String

    /// Wrap a builder that resolves the string, optionally honoring an override
    /// config. The builder should perform a `String(localized:)` lookup against
    /// the owning module's catalog (`bundle: .module`).
    public init(_ build: @escaping (LocalizationConfig?) -> String) {
        self.build = build
    }

    /// Resolve the string, optionally overriding the locale via `config`.
    public func localized(_ config: LocalizationConfig? = nil) -> String {
        build(config)
    }

    /// Resolve the string via `localized()` with the default `localized()` arguments.
    public var localized: String {
        localized()
    }
}
