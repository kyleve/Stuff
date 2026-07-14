#if canImport(UIKit)
    import Foundation
    import UIKit

    /// Logs scene lifecycle transitions — background, foreground, active,
    /// inactive — so error investigations can see what the app was doing.
    public struct AppLifecycleAmbientSource: AmbientEventSource {
        private let tokens = AmbientObserverTokens()

        public init() {}

        public func start(log: Log<AmbientEvent>) {
            tokens.replace(with: [
                observe(
                    UIApplication.didEnterBackgroundNotification,
                    log: log,
                    value: "background",
                ),
                observe(
                    UIApplication.willEnterForegroundNotification,
                    log: log,
                    value: "foreground",
                ),
                observe(UIApplication.didBecomeActiveNotification, log: log, value: "active"),
                observe(UIApplication.willResignActiveNotification, log: log, value: "inactive"),
            ])
        }

        public func stop() {
            tokens.removeAll()
        }

        private func observe(
            _ name: Notification.Name,
            log: Log<AmbientEvent>,
            value: String,
        ) -> any NSObjectProtocol {
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: nil,
            ) { _ in
                log { AmbientEvent(kind: .appLifecycle, value: value) }
            }
        }
    }
#endif
