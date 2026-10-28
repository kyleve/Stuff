import Foundation
@_spi(Testing) import PeriscopeCore
@testable import PeriscopeTools
import Testing

@MainActor
private final class CapturingAlertHandler: PeriscopeAlertHandler {
    private(set) var records: [LogRecord] = []

    func handle(_ record: LogRecord) {
        records.append(record)
    }
}

/// A fixture event for alerter routing.
@LogScope("AppLogs")
private enum AppLogs {}

@MainActor
struct PeriscopeAlerterTests {
    let system = Periscope(configuration: Periscope.Configuration(), sinks: [])
    private let handler = CapturingAlertHandler()

    @Test func routesRecordsAtOrAboveTheThreshold() async {
        let alerter = PeriscopeAlerter(system: system, threshold: .warning, handler: handler)
        alerter.start()
        let log = Log<AppLogs>(system: system)

        log.info("quiet")
        log.warning("toast me")
        log.error("toast me too")

        let delivered = await waitUntil { handler.records.count == 2 }
        #expect(delivered)
        #expect(handler.records.map(\.message) == ["toast me", "toast me too"])
        #expect(handler.records.allSatisfy { $0.level >= .warning })
    }

    @Test func onlyRecordsEmittedAfterStartAlert() async {
        let log = Log<AppLogs>(system: system)
        log.error("before start")

        let alerter = PeriscopeAlerter(system: system, threshold: .warning, handler: handler)
        alerter.start()
        log.error("after start")

        let delivered = await waitUntil { !handler.records.isEmpty }
        #expect(delivered)
        #expect(handler.records.map(\.message) == ["after start"])
    }

    @Test func stopEndsAlerting() async {
        let alerter = PeriscopeAlerter(system: system, threshold: .warning, handler: handler)
        alerter.start()
        let log = Log<AppLogs>(system: system)

        log.error("first")
        let first = await waitUntil { handler.records.count == 1 }
        #expect(first)

        // Once the observer is unregistered, an emission provably cannot
        // reach the handler — no sentinel race.
        alerter.stop()
        let unsubscribed = await waitUntil { system.liveObserverCount == 0 }
        #expect(unsubscribed)

        log.error("while stopped")
        #expect(handler.records.map(\.message) == ["first"])
    }

    @Test func startingTwiceDoesNotDuplicateSubscriptions() async {
        let alerter = PeriscopeAlerter(system: system, threshold: .warning, handler: handler)
        alerter.start()
        alerter.start()

        // One observer means one delivery stream — asserted directly
        // instead of racing a duplicate delivery against the expectation.
        #expect(system.liveObserverCount == 1)

        let log = Log<AppLogs>(system: system)
        log.error("once")
        log.error("sentinel")
        let delivered = await waitUntil {
            handler.records.contains { $0.message == "sentinel" }
        }
        #expect(delivered)
        #expect(handler.records.map(\.message) == ["once", "sentinel"])
    }
}
