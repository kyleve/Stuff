#if canImport(UIKit)
    import Foundation
    import UIKit

    /// Logs system memory warnings at `.warning` — the classic missing
    /// context when diagnosing a jetsam-adjacent crash.
    public final class MemoryWarningAmbientSource: NotificationAmbientSource {
        override public var observedNames: [Notification.Name] {
            [UIApplication.didReceiveMemoryWarningNotification]
        }

        override public func event(for _: Notification) -> AmbientEvent? {
            AmbientEvent(kind: .memory, value: "warning", level: .warning)
        }
    }
#endif
