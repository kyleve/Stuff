import Foundation
import StuffCore

extension LocalizedString {
    /// A WhereUI catalog string: looks `key` up in WhereUI's bundle, falling back
    /// to `defaultValue`, and honors an optional locale override at resolution
    /// time.
    ///
    /// This is the building block for ``LocalizedStrings`` — it bakes in
    /// `bundle: .module` and the `locale` plumbing so each member is just a `key`
    /// plus its English default. The key stays a `StaticString` literal on
    /// purpose: that's the overload of `String(localized:)` that resolves plural
    /// `variations`, and it keeps both Xcode's catalog extraction and the repo's
    /// `./localize` script able to read every key statically.
    ///
    /// Members that branch on a count pick between two `.module` keys; members
    /// that compose another string use the closure overload below.
    static func module(
        _ key: StaticString,
        _ defaultValue: String.LocalizationValue,
    ) -> LocalizedString {
        LocalizedString {
            String(
                localized: key,
                defaultValue: defaultValue,
                bundle: .module,
                locale: $0?.locale ?? .current,
            )
        }
    }

    /// Same as ``module(_:_:)``, but the default value is built from the
    /// resolution config so a composed string can thread the locale override
    /// into a nested `.localized($0)`.
    static func module(
        _ key: StaticString,
        _ defaultValue: @Sendable @escaping (LocalizationConfig?) -> String.LocalizationValue,
    ) -> LocalizedString {
        LocalizedString {
            String(
                localized: key,
                defaultValue: defaultValue($0),
                bundle: .module,
                locale: $0?.locale ?? .current,
            )
        }
    }
}
