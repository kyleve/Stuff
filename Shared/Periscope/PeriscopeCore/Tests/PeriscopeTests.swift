import Foundation
import PeriscopeCore
import Testing

struct PeriscopeTests {
    let sink = CapturingSink()

    private func makeSystem(recentBufferCapacity: Int = 500) -> Periscope {
        Periscope(
            configuration: Periscope.Configuration(recentBufferCapacity: recentBufferCapacity),
            sinks: [sink],
        )
    }

    @Test func recordsReachSinksInEmissionOrder() async {
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)

        log.info("one")
        log.info("two")
        log.info("three")
        await system.flush()

        #expect(sink.records.map(\.message) == ["one", "two", "three"])
        #expect(sink.flushCount == 1)
    }

    @Test func scopeDefinitionsArriveBeforeRecords() async throws {
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)

        log.info("hello")
        await system.flush()

        let deliveries = sink.deliveries
        let scopeIndex = try #require(deliveries.firstIndex { delivery in
            guard case let .scopes(scopes) = delivery else { return false }
            return scopes.contains(log.primaryScope)
        })
        let recordIndex = try #require(deliveries.firstIndex { delivery in
            guard case let .records(records) = delivery else { return false }
            return records.contains { $0.message == "hello" }
        })
        #expect(scopeIndex < recordIndex)
    }

    @Test func rootLoggerDefinesItsScopeInTheSystem() {
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)
        #expect(system.scope(for: log.primaryScope.id) == log.primaryScope)
    }

    @Test func lateAddedSinkGetsTheScopeRegistryReplayed() async {
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)
        log.info("before")
        await system.flush()

        let late = CapturingSink()
        system.add(sink: late)
        await system.flush()

        #expect(late.definedScopes.contains(log.primaryScope))
        #expect(late.records.isEmpty)
    }

    @Test func replayedScopesAreIdempotentForExistingSinks() async {
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)
        await system.flush()

        system.add(sink: CapturingSink())
        await system.flush()

        // The original sink sees the definition again; contract is
        // idempotence per scope ID, not exactly-once delivery.
        #expect(sink.definedScopes.count(where: { $0 == log.primaryScope }) >= 1)
    }

    @Test func recentBufferKeepsOnlyTheNewestRecords() async {
        let system = makeSystem(recentBufferCapacity: 3)
        let log = Log<AppLogs>(system: system)

        for index in 1 ... 5 {
            log.info("\(index)")
        }
        await system.flush()

        #expect(system.recentRecords().map(\.message) == ["3", "4", "5"])
        #expect(sink.records.count == 5)
    }

    @Test func liveRecordsYieldsEachNewRecord() async {
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)

        var iterator = system.liveRecords().makeAsyncIterator()
        log.info("one")
        log.warning("two")

        #expect(await iterator.next()?.message == "one")
        #expect(await iterator.next()?.message == "two")
    }

    @Test func flushIsSafeWhenNothingIsPending() async {
        let system = makeSystem()
        await system.flush()
        #expect(sink.records.isEmpty)
        #expect(sink.flushCount == 1)
    }

    @Test func recordsEmittedDuringADrainStillArrive() async {
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)

        for index in 1 ... 100 {
            log.info("\(index)")
        }
        await system.flush()

        #expect(sink.records.count == 100)
        #expect(sink.records.map(\.message) == (1 ... 100).map(String.init))
    }

    @Test func inspectModeFlagRoundTrips() {
        let system = makeSystem()
        #expect(!system.isInspectModeEnabled)
        system.isInspectModeEnabled = true
        #expect(system.isInspectModeEnabled)
        system.isInspectModeEnabled = false
        #expect(!system.isInspectModeEnabled)
    }

    // MARK: Level floors

    @Test func globalFloorDiscardsRecordsBelowIt() async {
        let system = makeSystem()
        system.minimumLevel = .warning
        let log = Log<AppLogs>(system: system)

        log.debug("quiet")
        log.info("quiet")
        log.warning("loud")
        log { AppLogs() } // AppLogs is .info — below the floor.
        await system.flush()

        #expect(sink.records.map(\.message) == ["loud"])
        #expect(system.recentRecords().map(\.message) == ["loud"])
    }

    @Test func subtreeFloorOverridesTheGlobalFloor() async {
        let system = makeSystem()
        system.minimumLevel = .error
        let root = Log<AppLogs>(system: system)
        let photos = root(PhotoLogs.self)
        system.setMinimumLevel(.debug, forSubtree: photos.primaryScope.id)

        root.info("root info")
        photos.debug("photos debug")
        photos(for: "album-1").debug("album debug")
        await system.flush()

        #expect(sink.records.map(\.message) == ["photos debug", "album debug"])
    }

    @Test func nearestSubtreeOverrideWins() async {
        let system = makeSystem()
        let root = Log<AppLogs>(system: system)
        let photos = root(PhotoLogs.self)
        let album = photos(for: "album-1")
        system.setMinimumLevel(.error, forSubtree: photos.primaryScope.id)
        system.setMinimumLevel(.debug, forSubtree: album.primaryScope.id)

        photos.info("blocked")
        album.debug("allowed")
        await system.flush()

        #expect(sink.records.map(\.message) == ["allowed"])
    }

    @Test func clearingASubtreeOverrideRestoresTheGlobalFloor() {
        let system = makeSystem()
        let root = Log<AppLogs>(system: system)
        system.setMinimumLevel(.error, forSubtree: root.primaryScope.id)
        #expect(!system.shouldRecord(level: .info, scopes: [root.primaryScope.id]))

        system.setMinimumLevel(nil, forSubtree: root.primaryScope.id)
        #expect(system.shouldRecord(level: .info, scopes: [root.primaryScope.id]))
    }

    @Test func linkedRecordsPassWhenAnyScopeAdmitsThem() async {
        let system = makeSystem()
        system.minimumLevel = .debug
        let model = Log<PhotoLogs>(system: system)
        let ui = Log<AppLogs>(system: system)
        system.setMinimumLevel(.error, forSubtree: model.primaryScope.id)

        (model + ui).info("visible via the UI scope")
        model.info("blocked")
        await system.flush()

        #expect(sink.records.map(\.message) == ["visible via the UI scope"])
    }

    @Test func filteredFreeformLoggingSkipsMessageRendering() {
        let system = makeSystem()
        system.minimumLevel = .warning
        let log = Log<AppLogs>(system: system)

        var rendered = false
        func render() -> String {
            rendered = true
            return "expensive"
        }

        log.debug(render())
        #expect(!rendered)

        log.error(render())
        #expect(rendered)
    }

    // MARK: Redaction

    @Test func redactionTransformsRecordsBeforeAnyDelivery() async {
        let system = Periscope(
            configuration: Periscope.Configuration(redact: { record in
                LogRecord(
                    id: record.id,
                    date: record.date,
                    event: Message(level: record.level, "[redacted]"),
                    scopes: record.scopes,
                )
            }),
            sinks: [sink],
        )
        let log = Log<AppLogs>(system: system)

        log.info("card number 4242")
        await system.flush()

        #expect(sink.records.map(\.message) == ["[redacted]"])
        #expect(system.recentRecords().map(\.message) == ["[redacted]"])
    }

    @Test func redactionCanSuppressARecordEntirely() async {
        let system = Periscope(
            configuration: Periscope.Configuration(redact: { record in
                record.message.contains("secret") ? nil : record
            }),
            sinks: [sink],
        )
        let log = Log<AppLogs>(system: system)

        log.info("secret token")
        log.info("fine")
        await system.flush()

        #expect(sink.records.map(\.message) == ["fine"])
    }

    // MARK: Flush policy

    @Test func recordsAtTheFlushThresholdTriggerAnAutomaticFlush() async {
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)

        log.error("boom")

        let flushed = await waitUntil { sink.flushCount >= 1 }
        #expect(flushed)
        #expect(sink.records.map(\.message) == ["boom"])
    }

    @Test func recordsBelowTheFlushThresholdDoNotFlushSinks() async {
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)

        log.warning("just a warning")
        let delivered = await waitUntil { sink.records.count == 1 }
        #expect(delivered)
        #expect(sink.flushCount == 0)
    }

    // MARK: Drop policy

    @Test func overflowingThePendingQueueDropsOldestAndReportsTheGap() async throws {
        let gate = GateSink()
        let system = Periscope(
            configuration: Periscope.Configuration(pendingBufferCapacity: 3),
            sinks: [gate, sink],
        )
        let log = Log<AppLogs>(system: system)

        log.info("r0")
        let drainBlocked = await waitUntil { gate.batchCount >= 1 }
        try #require(drainBlocked)

        for index in 1 ... 5 {
            log.info("r\(index)")
        }
        gate.open()
        await system.flush()

        let messages = sink.records.map(\.message)
        #expect(messages.first == "r0")
        #expect(messages.contains("2 log event(s) dropped before delivery"))
        #expect(messages.suffix(3) == ["r3", "r4", "r5"])
        #expect(!messages.contains("r1"))
        #expect(!messages.contains("r2"))

        let report = try #require(
            sink.records.first { $0.eventName == Periscope.DroppedEvents.eventName },
        )
        #expect(report.level == .warning)
        #expect(report.scopes == [system.systemScope.id])
    }
}
