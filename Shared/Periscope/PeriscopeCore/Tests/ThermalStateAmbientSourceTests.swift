import Foundation
@_spi(Testing) import PeriscopeCore
import Testing

struct ThermalStateAmbientSourceTests {
    @Test func thermalChangeNotificationsLogTheCurrentState() async {
        let sink = CapturingSink()
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
        system.startAmbientSource(ThermalStateAmbientSource())

        NotificationCenter.default.post(
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
        )
        await system.flush()

        let expected = ThermalStateAmbientSource
            .event(for: ProcessInfo.processInfo.thermalState)
        #expect(sink.records.contains { $0.message == expected.message })
    }

    /// A device that launches hot and never cools posts no notification, so
    /// without the baseline the snapshot would have no thermal state for the
    /// whole session.
    @Test func startingLogsTheCurrentStateAsABaseline() async {
        let sink = CapturingSink()
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
        system.startAmbientSource(ThermalStateAmbientSource())
        await system.flush()

        let expected = ThermalStateAmbientSource
            .event(for: ProcessInfo.processInfo.thermalState)
        let baseline = sink.records.first { $0.message == expected.message }
        #expect(baseline != nil)
        #expect(baseline?.ambient?[.thermalState] == expected.value)
    }

    @Test(arguments: [
        (ProcessInfo.ThermalState.nominal, "nominal", LogLevel.info),
        (.fair, "fair", .info),
        (.serious, "serious", .warning),
        (.critical, "critical", .warning),
    ])
    func statesMapToValuesAndLevels(
        state: ProcessInfo.ThermalState,
        value: String,
        level: LogLevel,
    ) {
        let event = ThermalStateAmbientSource.event(for: state)
        #expect(event.value == value)
        #expect(event.level == level)
    }
}
