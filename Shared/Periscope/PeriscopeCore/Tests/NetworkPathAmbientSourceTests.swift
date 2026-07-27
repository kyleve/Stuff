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
        let log = Log<AmbientEvent>(recorder: system)

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
        let log = Log<AmbientEvent>(recorder: system)

        source.emit("satisfied (wifi)", to: log)
        source.emit("satisfied (wifi)", to: log) // NWPathMonitor churn: dropped
        source.emit("unsatisfied", to: log)

        // Delivery preserves emission order, so once the final emit lands
        // every earlier one has too.
        _ = await waitUntil { networkValues(sink).contains("unsatisfied") }
        #expect(networkValues(sink) == ["satisfied (wifi)", "unsatisfied"])
    }

    @Test func reemitsAValueThatRecursAfterADifferentOne() async {
        // Only *consecutive* duplicates are dropped — genuine flapping
        // (Wi-Fi → cellular → Wi-Fi) must still log.
        let sink = CapturingSink()
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
        let source = NetworkPathAmbientSource()
        let log = Log<AmbientEvent>(recorder: system)

        source.emit("satisfied (wifi)", to: log)
        source.emit("satisfied (cellular)", to: log)
        source.emit("satisfied (wifi)", to: log)
        source.emit("unsatisfied", to: log)

        _ = await waitUntil { networkValues(sink).contains("unsatisfied") }
        #expect(networkValues(sink) == [
            "satisfied (wifi)",
            "satisfied (cellular)",
            "satisfied (wifi)",
            "unsatisfied",
        ])
    }

    @Test func stoppingResetsTheChangeFilter() async {
        // stop() (like a restart) forgets the last description, so current
        // connectivity re-reports rather than being swallowed as a
        // duplicate of the prior run.
        let sink = CapturingSink()
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
        let source = NetworkPathAmbientSource()
        let log = Log<AmbientEvent>(recorder: system)

        source.emit("satisfied (wifi)", to: log)
        source.stop() // clears the last-description filter
        source.emit("satisfied (wifi)", to: log)
        source.emit("unsatisfied", to: log)

        _ = await waitUntil { networkValues(sink).contains("unsatisfied") }
        #expect(networkValues(sink) == [
            "satisfied (wifi)",
            "satisfied (wifi)",
            "unsatisfied",
        ])
    }

    private func networkValues(_ sink: CapturingSink) -> [String] {
        let prefix = "network: "
        return sink.records
            .filter { $0.message.hasPrefix(prefix) }
            .map { String($0.message.dropFirst(prefix.count)) }
    }
}
