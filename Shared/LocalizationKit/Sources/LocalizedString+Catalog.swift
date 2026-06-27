import Foundation

extension LocalizedString {
    /// A catalog string: looks `key` up in `bundle`, falling back to
    /// `defaultValue`, and honors an optional locale override at resolution
    /// time.
    ///
    /// Each module wraps this in a thin `.module(_:_:)` factory that passes
    /// `bundle: .module`. The key stays a `StaticString` literal on purpose:
    /// that's the overload of `String(localized:)` that resolves plural
    /// `variations`, and it keeps both Xcode's catalog extraction and the repo's
    /// `./localize` script able to read every key statically.
    public static func catalog(
        _ key: StaticString,
        _ defaultValue: String.LocalizationValue,
        bundle: Bundle,
    ) -> LocalizedString {
        LocalizedString {
            String(
                localized: key,
                defaultValue: defaultValue,
                bundle: bundle,
                locale: $0?.locale ?? .current,
            )
        }
    }

    /// Same as ``catalog(_:_:bundle:)``, but the default value is built from the
    /// resolution config so a composed string can thread the locale override
    /// into a nested `.localized($0)`.
    public static func catalog(
        _ key: StaticString,
        bundle: Bundle,
        _ defaultValue: @Sendable @escaping (LocalizationConfig?) -> String.LocalizationValue,
    ) -> LocalizedString {
        LocalizedString {
            String(
                localized: key,
                defaultValue: defaultValue($0),
                bundle: bundle,
                locale: $0?.locale ?? .current,
            )
        }
    }
}
