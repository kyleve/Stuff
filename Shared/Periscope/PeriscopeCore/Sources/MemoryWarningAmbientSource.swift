#if canImport(UIKit)
    import Foundation
    import UIKit

    /// Logs system memory warnings at `.warning` — the classic missing
    /// context when diagnosing a jetsam-adjacent crash.
    public struct MemoryWarningAmbientSource: AmbientEventSource {
        public init() {}

        public func start(log: Log<AmbientEvent>) {
            _ = NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: nil,
            ) { _ in
                log { AmbientEvent(kind: .memory, value: "warning", level: .warning) }
            }
        }
    }
#endif
