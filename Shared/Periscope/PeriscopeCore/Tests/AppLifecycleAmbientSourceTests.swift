import Foundation
import PeriscopeCore
import Testing
import UIKit

struct AppLifecycleAmbientSourceTests {
    let sink = CapturingSink()
    let system: Periscope

    init() {
        system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
        system.startAmbientSource(AppLifecycleAmbientSource())
    }

    @Test(arguments: [
        (UIApplication.didEnterBackgroundNotification, "background"),
        (UIApplication.willEnterForegroundNotification, "foreground"),
        (UIApplication.didBecomeActiveNotification, "active"),
        (UIApplication.willResignActiveNotification, "inactive"),
    ])
    func lifecycleNotificationsLogTransitions(
        name: Notification.Name,
        value: String,
    ) async {
        NotificationCenter.default.post(name: name, object: nil)
        await system.flush()

        #expect(sink.records.contains { record in
            record.message == "app-lifecycle: phase=\(value)"
        })
    }

    /// Deliberately *no* startup baseline, unlike the thermal and power
    /// sources. Reading `UIApplication.applicationState` at launch reports
    /// `.background` even for a user tap under the UIScene lifecycle — the
    /// same trap `LifecycleReason.undetermined` exists to avoid — so a
    /// baseline would stamp a confidently wrong value onto every early
    /// record. The first real transition fills it in honestly.
    @Test func startingDoesNotFabricateALaunchState() async {
        await system.flush()

        #expect(!sink.records.contains { $0.message.hasPrefix("app-lifecycle:") })
    }
}
