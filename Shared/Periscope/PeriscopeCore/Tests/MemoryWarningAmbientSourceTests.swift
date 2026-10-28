import Foundation
import PeriscopeCore
import Testing
import UIKit

struct MemoryWarningAmbientSourceTests {
    @Test func memoryWarningsLogAtWarningLevel() async {
        let sink = CapturingSink()
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
        system.startAmbientSource(MemoryWarningAmbientSource())

        NotificationCenter.default.post(
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
        )
        await system.flush()

        let record = sink.records.first { $0.message == "memory: pressure=warning" }
        #expect(record?.level == .warning)
    }
}
