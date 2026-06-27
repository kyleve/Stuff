import LocalizationKit

extension LocalizedString {
    /// A LifecycleKit catalog string — delegates to ``LocalizedString/catalog(_:_:bundle:)``
    /// with `bundle: .module`.
    static func module(
        _ key: StaticString,
        _ defaultValue: String.LocalizationValue,
    ) -> LocalizedString {
        .catalog(key, defaultValue, bundle: .module)
    }

    static func module(
        _ key: StaticString,
        _ defaultValue: @Sendable @escaping (LocalizationConfig?) -> String.LocalizationValue,
    ) -> LocalizedString {
        .catalog(key, bundle: .module, defaultValue)
    }
}
