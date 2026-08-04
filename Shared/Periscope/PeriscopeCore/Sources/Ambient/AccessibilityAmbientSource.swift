#if canImport(UIKit)
    import Foundation
    import UIKit

    /// Logs which accessibility settings are enabled: one summary event at
    /// start (the state any of the session's events can be read against),
    /// then the refreshed summary on every toggle — VoiceOver, Switch
    /// Control, Reduce Motion, and friends often explain "it behaves
    /// differently for this user".
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
                emit(Self.summaryEvent())
            }
        }

        override public func receive(_: Notification) {
            // A toggle re-reports the *full* summary, not the one setting
            // that changed: the event's value is what folds into the
            // ambient snapshot under `.accessibility`, so a single-setting
            // delta would replace the complete state every later record is
            // stamped with. Selector delivery isn't guaranteed on the main
            // thread; hop there to read the main-isolated state.
            Task { @MainActor in
                emit(Self.summaryEvent())
            }
        }

        /// Every observed setting's current state as one value — the shape
        /// both the baseline and change events report, so the snapshot
        /// always carries the complete picture.
        @MainActor
        private static func summaryEvent() -> AmbientEvent {
            AmbientEvent(
                kind: .accessibility,
                value: Dictionary(
                    uniqueKeysWithValues: settings
                        .map { ($0.name, AmbientValue.bool($0.isEnabled())) },
                ),
            )
        }
    }
#endif
