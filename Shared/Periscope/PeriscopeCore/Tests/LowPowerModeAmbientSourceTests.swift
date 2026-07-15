import Foundation
import PeriscopeCore
import Testing

struct LowPowerModeAmbientSourceTests {
    @Test func powerStateChangesLogTheCurrentMode() async {
        let sink = CapturingSink()
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
        system.startAmbientSource(LowPowerModeAmbientSource())

        NotificationCenter.default.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        await system.flush()

        let expected = ProcessInfo.processInfo.isLowPowerModeEnabled ? "low-power" : "normal"
        #expect(sink.records.contains { $0.message == "power-mode: \(expected)" })
    }
}
