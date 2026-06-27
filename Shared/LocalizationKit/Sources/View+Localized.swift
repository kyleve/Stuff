import SwiftUI

extension View {
    /// Set the navigation title from a deferred ``LocalizedString``, resolving it
    /// at the point of display.
    ///
    /// The `LocalizedString`-taking modifiers below mirror
    /// ``SwiftUI/Text/init(localized:_:)``: they keep the resolution seam in one
    /// place so a future Environment-driven locale override has a single place to
    /// read the locale from. Prefer them over `someString.localized` at call
    /// sites.
    public func navigationTitle(
        _ title: LocalizedString,
        _ config: LocalizationConfig? = nil,
    ) -> some View {
        navigationTitle(title.localized(config))
    }

    /// Set the accessibility label from a deferred ``LocalizedString``.
    public func accessibilityLabel(
        _ label: LocalizedString,
        _ config: LocalizationConfig? = nil,
    ) -> some View {
        accessibilityLabel(Text(label.localized(config)))
    }

    /// Set the accessibility hint from a deferred ``LocalizedString``.
    public func accessibilityHint(
        _ hint: LocalizedString,
        _ config: LocalizationConfig? = nil,
    ) -> some View {
        accessibilityHint(Text(hint.localized(config)))
    }
}
