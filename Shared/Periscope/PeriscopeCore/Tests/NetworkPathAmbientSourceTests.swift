import Foundation
import PeriscopeCore
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
}
