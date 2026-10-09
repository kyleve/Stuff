#if canImport(UIKit)
    import Foundation
    import UIKit

    /// Logs scene lifecycle transitions — background, foreground, active,
    /// inactive — so error investigations can see what the app was doing.
    public final class AppLifecycleAmbientSource: NotificationAmbientSource {
        private static let values: [Notification.Name: AmbientLog.AppLifecycle.Phase] = [
            UIApplication.didEnterBackgroundNotification: .background,
            UIApplication.willEnterForegroundNotification: .foreground,
            UIApplication.didBecomeActiveNotification: .active,
            UIApplication.willResignActiveNotification: .inactive,
        ]

        override public var observedNames: [Notification.Name] {
            Array(Self.values.keys)
        }

        override public func event(for notification: Notification)
            -> (any AmbientLogEvent & LogEvent)?
        {
            Self.values[notification.name].map {
                AmbientLog.AppLifecycle(phase: .shared(.category, $0))
            }
        }
    }
#endif
