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
            record.message == "app-lifecycle: \(value)"
        })
    }
}
