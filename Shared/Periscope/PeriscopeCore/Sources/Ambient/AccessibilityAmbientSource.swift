#if canImport(UIKit)
    import Foundation
    import UIKit

    /// Logs which accessibility settings are enabled: one summary event at
    /// start (the state any of the session's events can be read against),
    /// then a change event per toggle — VoiceOver, Switch Control, Reduce
    /// Motion, and friends often explain "it behaves differently for this
    /// user".
    public final class AccessibilityAmbientSource: NotificationAmbientSource {
        /// One observed setting: display name, change notification, and
        /// current-state accessor (UIAccessibility statics are main-actor).
        private struct Setting {
            let name: String
            let notification: Notification.Name
            let isEnabled: @MainActor @Sendable () -> Bool
        }

        private static let settings: [Setting] = [
            Setting(
                name: "voiceover",
                notification: UIAccessibility.voiceOverStatusDidChangeNotification,
                isEnabled: { UIAccessibility.isVoiceOverRunning },
            ),
            Setting(
                name: "switch-control",
                notification: UIAccessibility.switchControlStatusDidChangeNotification,
                isEnabled: { UIAccessibility.isSwitchControlRunning },
            ),
            Setting(
                name: "reduce-motion",
                notification: UIAccessibility.reduceMotionStatusDidChangeNotification,
                isEnabled: { UIAccessibility.isReduceMotionEnabled },
            ),
            Setting(
                name: "reduce-transparency",
                notification: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
                isEnabled: { UIAccessibility.isReduceTransparencyEnabled },
            ),
            Setting(
                name: "bold-text",
                notification: UIAccessibility.boldTextStatusDidChangeNotification,
                isEnabled: { UIAccessibility.isBoldTextEnabled },
            ),
            Setting(
                name: "darker-colors",
                notification: UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
                isEnabled: { UIAccessibility.isDarkerSystemColorsEnabled },
            ),
            Setting(
                name: "invert-colors",
                notification: UIAccessibility.invertColorsStatusDidChangeNotification,
                isEnabled: { UIAccessibility.isInvertColorsEnabled },
            ),
            Setting(
                name: "grayscale",
                notification: UIAccessibility.grayscaleStatusDidChangeNotification,
                isEnabled: { UIAccessibility.isGrayscaleEnabled },
            ),
        ]

        override public var observedNames: [Notification.Name] {
            Self.settings.map(\.notification)
        }

        override public func started() {
            // Reads run on the main actor (UIAccessibility statics are
            // main-isolated); logging is async, so a hop is fine.
            Task { @MainActor in
                let enabled = Self.settings.filter { $0.isEnabled() }.map(\.name)
                let summary = enabled.isEmpty
                    ? "none enabled"
                    : "enabled: \(enabled.joined(separator: ", "))"
                emit(AmbientEvent(kind: .accessibility, value: summary))
            }
        }

        override public func receive(_ notification: Notification) {
            // Selector delivery isn't guaranteed on the main thread; hop
            // there to read the main-isolated UIAccessibility state.
            // Capture only the name — `Notification` isn't `Sendable`.
            let name = notification.name
            Task { @MainActor in
                guard let setting = Self.settings.first(where: { $0.notification == name })
                else { return }
                let state = setting.isEnabled() ? "on" : "off"
                emit(AmbientEvent(kind: .accessibility, value: "\(setting.name): \(state)"))
            }
        }
    }
#endif
