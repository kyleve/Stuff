@_spi(Testing) import PeriscopeCore
import Testing

struct NetworkPathAmbientSourceTests {
    @Test func reportsTheInitialPathOnStart() async {
        let sink = CapturingSink()
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
        system.startAmbientSource(NetworkPathAmbientSource())

        // NWPathMonitor always delivers the current path shortly after
        // starting; wait for that first update rather than a fixed delay.
        let delivered = await waitUntil {
            sink.records.contains { $0.message.hasPrefix("network: ") }
        }
        #expect(delivered)
    }

    @Test func restartingCancelsThePriorMonitorAndKeepsReporting() async {
        let sink = CapturingSink()
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
        let source = NetworkPathAmbientSource()
        let log = Log<AmbientLog>(recorder: system)

        source.start(log: log)
        source.start(log: log) // replaces (and cancels) the first monitor

        let delivered = await waitUntil {
            sink.records.contains { $0.message.hasPrefix("network: ") }
        }
        #expect(delivered)
    }

    @Test func dropsConsecutiveDuplicateDescriptions() async {
        let sink = CapturingSink()
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
        let source = NetworkPathAmbientSource()
        let log = Log<AmbientLog>(recorder: system)

        source.emit(wifi, to: log)
        source.emit(wifi, to: log) // NWPathMonitor churn: dropped
        source.emit(offline, to: log)

        // Delivery preserves emission order, so once the final emit lands
        // every earlier one has too.
        _ = await waitUntil { networkValues(sink).contains(offline) }
        #expect(networkValues(sink) == [wifi, offline])
    }

    @Test func reemitsAValueThatRecursAfterADifferentOne() async {
        // Only *consecutive* duplicates are dropped — genuine flapping
        // (Wi-Fi → cellular → Wi-Fi) must still log.
        let sink = CapturingSink()
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
        let source = NetworkPathAmbientSource()
        let log = Log<AmbientLog>(recorder: system)

        source.emit(wifi, to: log)
        source.emit(cellular, to: log)
        source.emit(wifi, to: log)
        source.emit(offline, to: log)

        _ = await waitUntil { networkValues(sink).contains(offline) }
        #expect(networkValues(sink) == [wifi, cellular, wifi, offline])
    }

    @Test func stoppingResetsTheChangeFilter() async {
        // stop() (like a restart) forgets the last value, so current
        // connectivity re-reports rather than being swallowed as a
        // duplicate of the prior run.
        let sink = CapturingSink()
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
        let source = NetworkPathAmbientSource()
        let log = Log<AmbientLog>(recorder: system)

        source.emit(wifi, to: log)
        source.stop() // clears the last-value filter
        source.emit(wifi, to: log)
        source.emit(offline, to: log)

        _ = await waitUntil { networkValues(sink).contains(offline) }
        #expect(networkValues(sink) == [wifi, wifi, offline])
    }

    private var wifi: [String: AmbientValue] {
        ["status": "satisfied", "interfaces": "wifi"]
    }

    private var cellular: [String: AmbientValue] {
        ["status": "satisfied", "interfaces": "cellular"]
    }

    private var offline: [String: AmbientValue] {
        ["status": "unsatisfied"]
    }

    private func networkValues(_ sink: CapturingSink) -> [[String: AmbientValue]] {
        sink.records
            .compactMap { $0.event as? AmbientEvent }
            .filter { $0.kind == .network }
            .map(\.value)
    }
}
