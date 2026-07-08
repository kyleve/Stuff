import Foundation
import PeriscopeCore
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
private struct AppLogs: LogEvent {
    var message: String {
        "app"
    }
}

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

        alerter.stop()
        log.error("while stopped")

        // A fresh alerter only sees records emitted after it starts, so once
        // its sentinel arrives, the stopped alerter demonstrably never
        // delivered "while stopped".
        let restarted = PeriscopeAlerter(system: system, threshold: .warning, handler: handler)
        restarted.start()
        log.error("sentinel")
        let sentinel = await waitUntil {
            handler.records.contains { $0.message == "sentinel" }
        }
        #expect(sentinel)
        #expect(!handler.records.contains { $0.message == "while stopped" })
    }

    @Test func startingTwiceDoesNotDuplicateAlerts() async {
        let alerter = PeriscopeAlerter(system: system, threshold: .warning, handler: handler)
        alerter.start()
        alerter.start()
        let log = Log<AppLogs>(system: system)

        log.error("once")
        let delivered = await waitUntil { !handler.records.isEmpty }
        #expect(delivered)

        // Give a duplicate delivery a chance to land before asserting.
        await Task.yield()
        #expect(handler.records.count == 1)
    }
}
