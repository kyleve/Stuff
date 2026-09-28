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
            // `.occurrence`: the app isn't "in a memory warning" afterwards,
            // so this must not stick to every later record's snapshot.
            AmbientEvent(
                kind: .restricted(.technicalState, .memory),
                value: .restricted(.domainValue, ["pressure": .string("warning")]),
                level: .restricted(.technicalState, .warning),
                reporting: .restricted(.technicalState, .occurrence),
            )
        }
    }
#endif
