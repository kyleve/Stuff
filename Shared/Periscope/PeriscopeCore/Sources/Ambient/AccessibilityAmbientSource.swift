#if canImport(UIKit)
    import Foundation
    import UIKit

    /// Logs which accessibility settings are enabled: one summary event at
    /// start (the state any of the session's events can be read against),
    /// then a change event per toggle — VoiceOver, Switch Control, Reduce
    /// Motion, and friends often explain "it behaves differently for this
    /// user".
    public struct AccessibilityAmbientSource: AmbientEventSource {
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

        private let tokens = AmbientObserverTokens()

        public init() {}

        public func start(log: Log<AmbientEvent>) {
            tokens.replace(with: Self.settings.map { setting in
                NotificationCenter.default.addObserver(
                    forName: setting.notification,
                    object: nil,
                    queue: .main,
                ) { _ in
                    MainActor.assumeIsolated {
                        let state = setting.isEnabled() ? "on" : "off"
                        log {
                            AmbientEvent(kind: .accessibility, value: "\(setting.name): \(state)")
                        }
                    }
                }
            })
            Task { @MainActor in
                let enabled = Self.settings.filter { $0.isEnabled() }.map(\.name)
                let summary = enabled.isEmpty
                    ? "none enabled"
                    : "enabled: \(enabled.joined(separator: ", "))"
                log { AmbientEvent(kind: .accessibility, value: summary) }
            }
        }

        public func stop() {
            tokens.removeAll()
        }
    }
#endif
