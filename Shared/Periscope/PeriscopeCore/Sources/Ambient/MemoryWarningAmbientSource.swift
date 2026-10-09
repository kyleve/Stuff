#if canImport(UIKit)
    import Foundation
    import UIKit

    /// Logs system memory warnings at `.warning` — the classic missing
    /// context when diagnosing a jetsam-adjacent crash.
    public final class MemoryWarningAmbientSource: NotificationAmbientSource {
        override public var observedNames: [Notification.Name] {
            [UIApplication.didReceiveMemoryWarningNotification]
        }

        override public func event(for _: Notification) -> (any AmbientLogEvent & LogEvent)? {
            // `.occurrence`: the app isn't "in a memory warning" afterwards,
            // so this must not stick to every later record's snapshot.
            AmbientLog.MemoryWarning()
        }
    }
#endif
