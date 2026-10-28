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

        let enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        #expect(sink.records.contains { $0.message == "power-mode: low-power=\(enabled)" })
    }

    /// A session that runs entirely in (or out of) Low Power Mode never
    /// posts a transition, so the baseline is the only way the snapshot
    /// learns the power mode at all.
    @Test func startingLogsTheCurrentModeAsABaseline() async {
        let sink = CapturingSink()
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
        system.startAmbientSource(LowPowerModeAmbientSource())
        await system.flush()

        let enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        let baseline = sink.records.first { $0.message == "power-mode: low-power=\(enabled)" }
        #expect(baseline != nil)
        #expect(baseline?.ambient?[.powerMode] == ["low-power": .bool(enabled)])
    }
}
