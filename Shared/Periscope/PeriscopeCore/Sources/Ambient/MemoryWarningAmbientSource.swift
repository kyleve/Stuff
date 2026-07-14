#if canImport(UIKit)
    import Foundation
    import UIKit

    /// Logs system memory warnings at `.warning` — the classic missing
    /// context when diagnosing a jetsam-adjacent crash.
    public struct MemoryWarningAmbientSource: AmbientEventSource {
        private let tokens = AmbientObserverTokens()

        public init() {}

        public func start(log: Log<AmbientEvent>) {
            let token = NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: nil,
            ) { _ in
                log { AmbientEvent(kind: .memory, value: "warning", level: .warning) }
            }
            tokens.replace(with: [token])
        }

        public func stop() {
            tokens.removeAll()
        }
    }
#endif
