import Foundation
import os
import PeriscopeCore
import Testing

/// A source that logs one event the moment it starts.
private struct ImmediateSource: AmbientEventSource {
    func start(log: Log<AmbientEvent>) {
        log { AmbientEvent(kind: AmbientKind("test-kind"), value: "started") }
    }
}

struct AmbientEventSourceTests {
    let sink = CapturingSink()
    let system: Periscope

    init() {
        system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
    }

    @Test func startedSourcesLogUnderTheAmbientScope() async {
        system.startAmbientSource(ImmediateSource())
        await system.flush()

        #expect(sink.records.count == 1)
        #expect(sink.records.first?.message == "test-kind: started")

        let scope = sink.records.first?.scopes.first
        #expect(scope.flatMap { system.scope(for: $0) }?.name == AmbientEvent.eventName)
    }

    @Test func defaultSourcesStartWithoutIncident() async {
        // Built-in sources observe real system notifications; starting them
        // must at minimum register cleanly and keep the system consumable.
        system.startDefaultAmbientSources()
        let log = Log<AppLogs>(system: system)
        log.info("still logging")
        await system.flush()

        #expect(sink.records.contains { $0.message == "still logging" })
    }
}
