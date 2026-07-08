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

        let first = try #require(sink.deliveries.first)
        guard case let .scopes(scopes) = first else {
            Issue.record("Expected the scope definition to be delivered first")
            return
        }
        #expect(scopes.contains(log.primaryScope))
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
}
