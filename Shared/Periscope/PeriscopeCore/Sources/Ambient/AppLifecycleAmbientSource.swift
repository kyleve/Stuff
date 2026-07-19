#if canImport(UIKit)
    import Foundation
    import UIKit

    /// Logs scene lifecycle transitions — background, foreground, active,
    /// inactive — so error investigations can see what the app was doing.
    public final class AppLifecycleAmbientSource: NotificationAmbientSource {
        private static let values: [Notification.Name: String] = [
            UIApplication.didEnterBackgroundNotification: "background",
            UIApplication.willEnterForegroundNotification: "foreground",
            UIApplication.didBecomeActiveNotification: "active",
            UIApplication.willResignActiveNotification: "inactive",
        ]

        override public var observedNames: [Notification.Name] {
            Array(Self.values.keys)
        }

        override public func event(for notification: Notification) -> AmbientEvent? {
            Self.values[notification.name].map { AmbientEvent(kind: .appLifecycle, value: $0) }
        }
    }
#endif
