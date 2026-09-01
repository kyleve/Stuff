import Foundation
@_spi(Testing) import PeriscopeCore
import Testing
@_spi(Testing) @testable import ThrowCore

struct ThrowDurableLoggingTests {
    @Test func starterAttachesBeforeItReportsReadyAndPrunesHistory() async throws {
        let now = Date(timeIntervalSince1970: 1_787_594_400)
        let system = Periscope(
            configuration: .init(
                recentBufferCapacity: 20,
                pendingBufferCapacity: 20,
                liveBufferCapacity: 20,
                flushThreshold: .error,
                redact: nil,
            ),
            sinks: [],
        )
        let starter = PeriscopeThrowDurableLoggingStarter(
            system: system,
            storage: .inMemory,
            softwareCreditsLoadFailure: nil,
            now: { now },
        )

        let loggingSession = try await starter.start()
        await system.flush()
        #expect(sessionEvents(in: system) == [.durableLoggingReady])

        await loggingSession.pruneHistory()
        await system.flush()
        #expect(sessionEvents(in: system) == [
            .durableLoggingReady,
            .durableLoggingHistoryPruned(
                expiredEventCount: 0,
                overflowEventCount: 0,
            ),
        ])
    }

    @Test func deferredCreditsFailureReachesTheAttachedStore() async throws {
        let system = makeSystem()
        let store = try await PeriscopeStore.make(
            storage: .inMemory,
            session: .current(attributes: [:]),
        )
        let failure = ThrowSoftwareCreditsLoadFailure(
            error: NSError(domain: "com.stuff.throw.attribution-test", code: 42),
        )
        let starter = PeriscopeThrowDurableLoggingStarter(
            system: system,
            softwareCreditsLoadFailure: failure,
            now: { Date(timeIntervalSince1970: 1_787_594_400) },
            makeStore: { store },
        )

        _ = try await starter.start()
        await system.flush()

        let storedEvents = try await store.events(matching: LogQuery())
        let storedEvent = try #require(storedEvents.first {
            (try? $0.decode(ThrowSessionLogEvent.self)) == .softwareCreditsLoadFailed
        })
        #expect(try await store.attachments(forEvent: storedEvent.id) == [failure.attachment])
    }

    @Test func deferredCreditsFailureReachesExistingSinksWhenTheStoreCannotOpen() async throws {
        let sink = CapturingThrowLogSink()
        let system = makeSystem(sinks: [sink])
        let failure = ThrowSoftwareCreditsLoadFailure(
            error: NSError(domain: "com.stuff.throw.attribution-test", code: 42),
        )
        let starter = PeriscopeThrowDurableLoggingStarter(
            system: system,
            softwareCreditsLoadFailure: failure,
            now: { Date(timeIntervalSince1970: 1_787_594_400) },
            makeStore: { throw StoreOpenFailure() },
        )

        do {
            _ = try await starter.start()
            Issue.record("Starting durable logging must throw the store-open error")
        } catch is StoreOpenFailure {
            // The expected store-open failure reached the composition caller.
        } catch {
            Issue.record("Starting durable logging threw an unexpected error: \(error)")
        }
        await system.flush()

        let records = await sink.records()
        let record = try #require(records.first {
            $0.event as? ThrowSessionLogEvent == .softwareCreditsLoadFailed
        })
        #expect(record.attachments == [failure.attachment])
    }

    private func sessionEvents(in system: Periscope) -> [ThrowSessionLogEvent] {
        system.recentRecords().compactMap { $0.event as? ThrowSessionLogEvent }
    }

    private func makeSystem(sinks: [any LogSink] = []) -> Periscope {
        Periscope(
            configuration: .init(
                recentBufferCapacity: 20,
                pendingBufferCapacity: 20,
                liveBufferCapacity: 20,
                flushThreshold: .error,
                redact: nil,
            ),
            sinks: sinks,
        )
    }
}

private struct StoreOpenFailure: Error {}

private actor CapturingThrowLogSink: LogSink {
    private var capturedRecords: [LogRecord] = []

    func defineScopes(_: [LogScope]) async {}

    func write(_ records: [LogRecord]) async {
        capturedRecords.append(contentsOf: records)
    }

    func flush() async {}

    func records() -> [LogRecord] {
        capturedRecords
    }
}
