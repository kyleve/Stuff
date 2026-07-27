import Foundation
import os
import PeriscopeCore
import Testing

/// A source that logs one event the moment it starts.
private final class ImmediateSource: AmbientEventSource {
    func start(log: Log<AmbientEvent>) {
        log { AmbientEvent(kind: AmbientKind("test-kind"), value: "started") }
    }

    func stop() {}
}

/// Observes a test-unique notification through `NotificationAmbientSource`,
/// so stop/restart semantics can be asserted without cross-talk from other
/// tests posting process-global system notifications.
private final class NotificationSource: NotificationAmbientSource {
    let name: Notification.Name

    init(name: Notification.Name) {
        self.name = name
        super.init()
    }

    override var observedNames: [Notification.Name] {
        [name]
    }

    override func event(for _: Notification) -> AmbientEvent? {
        AmbientEvent(kind: AmbientKind("test-kind"), value: "fired")
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

    @Test func defaultSourcesStartAndStopWithoutIncident() async {
        // Built-in sources observe real system notifications; starting and
        // stopping them must register and unregister cleanly while the
        // system stays consumable.
        system.startDefaultAmbientSources()
        system.stopAmbientSources()
        let log = Log<AppLogs>(system: system)
        log.info("still logging")
        await system.flush()

        #expect(sink.records.contains { $0.message == "still logging" })
    }

    @Test func stoppedSourcesNoLongerObserve() async {
        let name = Notification.Name("periscope-test-\(UUID().uuidString)")
        system.startAmbientSource(NotificationSource(name: name))

        NotificationCenter.default.post(name: name, object: nil)
        await system.flush()
        #expect(sink.records.count(where: { $0.message == "test-kind: fired" }) == 1)

        system.stopAmbientSources()
        NotificationCenter.default.post(name: name, object: nil)
        await system.flush()
        #expect(sink.records.count(where: { $0.message == "test-kind: fired" }) == 1)
    }

    @Test func restartingASourceReplacesItsObservationInsteadOfDoubling() async {
        let name = Notification.Name("periscope-test-\(UUID().uuidString)")
        let source = NotificationSource(name: name)
        let log = Log<AmbientEvent>(system: system)
        source.start(log: log)
        source.start(log: log)

        NotificationCenter.default.post(name: name, object: nil)
        await system.flush()

        #expect(sink.records.count(where: { $0.message == "test-kind: fired" }) == 1)
        source.stop()
    }
}
