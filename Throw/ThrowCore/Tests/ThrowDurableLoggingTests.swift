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

    @Test func bufferedSessionFailuresReachTheAttachedStoreExactlyOnce() async throws {
        let system = makeSystem()
        let store = try await PeriscopeStore.make(
            storage: .inMemory,
            session: .current(attributes: [:]),
        )
        let starter = PeriscopeThrowDurableLoggingStarter(
            system: system,
            softwareCreditsLoadFailure: nil,
            now: { Date(timeIntervalSince1970: 1_787_594_400) },
            makeStore: { store },
        )
        let launchError = NSError(domain: "com.stuff.throw.launch-test", code: 1)
        let operationError = NSError(domain: "com.stuff.throw.operation-test", code: 2)
        starter.recordColdLaunchFailure(at: .preferences, error: launchError)
        starter.recordPostLaunchFailure(at: .preferencePersistence, error: operationError)

        _ = try await starter.start()
        await system.flush()

        let records = try await store.events(matching: LogQuery())
        let launchRecords = records.filter {
            (try? $0.decode(ThrowSessionLogEvent.self)) == .coldLaunchFailed(
                boundary: .preferences,
            )
        }
        let operationRecords = records.filter {
            (try? $0.decode(ThrowSessionLogEvent.self)) == .postLaunchOperationFailed(
                operation: .preferencePersistence,
            )
        }
        let launchRecord = try #require(launchRecords.first)
        let operationRecord = try #require(operationRecords.first)
        #expect(launchRecords.count == 1)
        #expect(operationRecords.count == 1)
        let launchAttachments = try await store.attachments(forEvent: launchRecord.id)
        let operationAttachments = try await store.attachments(forEvent: operationRecord.id)
        let launchAttachment = try #require(launchAttachments.first)
        let operationAttachment = try #require(operationAttachments.first)
        #expect(launchAttachments.count == 1)
        #expect(operationAttachments.count == 1)
        #expect(launchAttachment.name == "launch-error")
        #expect(operationAttachment.name == "operation-error")
        #expect(launchAttachment.contentType == .json)
        #expect(operationAttachment.contentType == .json)
        let launchPayload = try errorPayload(in: launchAttachment)
        let expectedLaunchPayload = try errorPayload(
            in: .error(launchError, name: "launch-error"),
        )
        let operationPayload = try errorPayload(in: operationAttachment)
        let expectedOperationPayload = try errorPayload(
            in: .error(operationError, name: "operation-error"),
        )
        #expect(launchPayload == expectedLaunchPayload)
        #expect(operationPayload == expectedOperationPayload)
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

    @Test func bufferedLaunchFailureStaysInExistingSinksOnceWhenTheStoreCannotOpen() async throws {
        let sink = CapturingThrowLogSink()
        let system = makeSystem(sinks: [sink])
        let starter = PeriscopeThrowDurableLoggingStarter(
            system: system,
            softwareCreditsLoadFailure: nil,
            now: { Date(timeIntervalSince1970: 1_787_594_400) },
            makeStore: { throw StoreOpenFailure() },
        )
        let launchError = NSError(domain: "com.stuff.throw.launch-test", code: 1)
        starter.recordColdLaunchFailure(at: .preferences, error: launchError)

        do {
            _ = try await starter.start()
            Issue.record("Starting durable logging must throw the store-open error")
        } catch is StoreOpenFailure {
            // The expected store-open failure reached the composition caller.
        } catch {
            Issue.record("Starting durable logging threw an unexpected error: \(error)")
        }
        await system.flush()

        let failures = await sink.records().filter {
            $0.event as? ThrowSessionLogEvent == .coldLaunchFailed(boundary: .preferences)
        }
        let failure = try #require(failures.first)
        #expect(failures.count == 1)
        let attachment = try #require(failure.attachments.first)
        #expect(failure.attachments.count == 1)
        #expect(attachment.name == "launch-error")
        #expect(attachment.contentType == .json)
        let payload = try errorPayload(in: attachment)
        let expectedPayload = try errorPayload(
            in: .error(launchError, name: "launch-error"),
        )
        #expect(payload == expectedPayload)
    }

    private func sessionEvents(in system: Periscope) -> [ThrowSessionLogEvent] {
        system.recentRecords().compactMap { $0.event as? ThrowSessionLogEvent }
    }

    private func errorPayload(in attachment: LogAttachment) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: attachment.data)
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
