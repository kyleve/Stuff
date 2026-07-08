import Foundation
import os
@_spi(Testing) import PeriscopeCore
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

    @Test func slowLiveObserversKeepOnlyTheNewestRecords() async {
        let system = Periscope(
            configuration: Periscope.Configuration(liveBufferCapacity: 3),
            sinks: [sink],
        )
        let log = Log<AppLogs>(system: system)

        // Nothing consumes yet — the buffer must cap at the newest three.
        var iterator = system.liveRecords().makeAsyncIterator()
        for index in 1 ... 5 {
            log.info("\(index)")
        }

        #expect(await iterator.next()?.message == "3")
        #expect(await iterator.next()?.message == "4")
        #expect(await iterator.next()?.message == "5")

        // Once caught up, new records flow through normally.
        log.info("6")
        #expect(await iterator.next()?.message == "6")
    }

    @Test func flushIsSafeWhenNothingIsPending() async {
        let system = makeSystem()
        await system.flush()
        #expect(sink.records.isEmpty)
        #expect(sink.flushCount == 1)
    }

    @Test func interleavedScopesAndRecordsDeliverGroupedInOrder() async throws {
        // Hold the drain so an interleaved backlog accumulates, then verify
        // the single stolen batch reaches the sink as ordered runs.
        let gate = GateSink()
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [gate, sink])
        let root = Log<AppLogs>(system: system)

        root.info("r0")
        let drainBlocked = await waitUntil { gate.batchCount >= 1 }
        try #require(drainBlocked)

        root.info("r1")
        let photos = root(PhotoLogs.self) // defines a scope mid-stream
        photos.info("r2")
        let album = photos(for: "album-1") // and another
        album.info("r3")
        gate.open()
        await system.flush()

        let backlog = sink.deliveries.drop(while: { delivery in
            guard case let .records(records) = delivery else { return true }
            return records.first?.message == "r0"
        })
        let shape = backlog.map { delivery in
            switch delivery {
                case let .scopes(scopes): "scopes(\(scopes.map(\.name).joined(separator: ",")))"
                case let .records(records): "records(\(records.map(\.message).joined(separator: ",")))"
            }
        }
        #expect(shape == [
            "records(r1)",
            "scopes(PhotoLogs)",
            "records(r2)",
            "scopes(album-1)",
            "records(r3)",
        ])
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

    @Test func inspectModeChangesYieldTheCurrentValueThenChangesOnly() async {
        let system = makeSystem()
        system.isInspectModeEnabled = true

        var iterator = system.inspectModeChanges().makeAsyncIterator()
        #expect(await iterator.next() == true)

        system.isInspectModeEnabled = true // redundant — must not yield
        system.isInspectModeEnabled = false
        #expect(await iterator.next() == false)
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

    @Test func redactionNeverRunsForFloorFilteredRecords() async {
        let redactionCount = OSAllocatedUnfairLock(initialState: 0)
        let system = Periscope(
            configuration: Periscope.Configuration(redact: { record in
                redactionCount.withLock { $0 += 1 }
                return record
            }),
            sinks: [sink],
        )
        system.minimumLevel = .warning
        let log = Log<AppLogs>(system: system)

        log.debug("filtered freeform")
        log { AppLogs() } // .info structured event — filtered in record()
        log.warning("admitted")
        await system.flush()

        #expect(redactionCount.withLock { $0 } == 1)
        #expect(sink.records.map(\.message) == ["admitted"])
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

    @Test func errorStormsCoalesceIntoAFewFlushes() async throws {
        // Hold the drain mid-delivery so the whole storm lands while the
        // first auto-flush is still waiting — deterministic coalescing.
        let gate = GateSink()
        let system = Periscope(
            configuration: Periscope.Configuration(),
            sinks: [gate, sink],
        )
        let log = Log<AppLogs>(system: system)

        log.error("e1")
        let drainBlocked = await waitUntil { gate.batchCount >= 1 }
        try #require(drainBlocked)

        for index in 2 ... 50 {
            log.error("e\(index)")
        }
        gate.open()

        let delivered = await waitUntil { sink.records.count == 50 }
        #expect(delivered)
        let settled = await waitUntil { sink.flushCount >= 1 }
        #expect(settled)

        // One flush for the storm, at most one follow-up for records that
        // landed mid-flush — never one per record.
        #expect(sink.flushCount <= 2)
    }

    @Test func autoFlushRecoversAfterSettling() async {
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)

        log.error("first")
        let first = await waitUntil { sink.flushCount >= 1 }
        #expect(first)
        let countAfterFirst = sink.flushCount

        log.error("second")
        let second = await waitUntil { sink.flushCount > countAfterFirst }
        #expect(second)
        #expect(sink.records.map(\.message) == ["first", "second"])
    }

    @Test func recordsBelowTheFlushThresholdDoNotFlushSinks() async {
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)

        log.warning("just a warning")
        let delivered = await waitUntil { sink.records.count == 1 }
        #expect(delivered)
        #expect(sink.flushCount == 0)
    }

    // MARK: Span watchdog

    @Test func sweepExpiresOnlyOverdueBoundedSpans() async throws {
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)
        let now = ContinuousClock().now

        log.begin(for: "overdue", lifetime: .bounded(budget: .seconds(10)))
        log.begin(for: "within-budget", lifetime: .bounded(budget: .seconds(120)))
        log.begin(for: "open-ended", lifetime: .indefinite)

        system.sweepOverdueSpans(now: now + .seconds(60))
        await system.flush()

        let expired = sink.records.compactMap { $0.event as? SpanEnded }
        #expect(expired.count == 1)
        let ended = try #require(expired.first)
        #expect(ended.name == "overdue")
        #expect(ended.exit.mode == .expired)
        #expect(ended.exit.reason?.contains("budget") == true)
        // `now` was captured just before the begin, so the measured age is
        // a hair under the sweep offset — the meaningful bound is the
        // budget it blew through.
        let duration = try #require(ended.duration)
        #expect(duration >= .seconds(10))
    }

    @Test func expiredSpansKeepTheirBeginContext() async throws {
        let system = makeSystem()
        let key = LogTagKey("payment-id")
        let log = Log<AppLogs>(system: system)(for: "checkout").tagged(key, "pay_1")

        log.begin(for: "pay_1", lifetime: .bounded(budget: .seconds(1)))
        system.sweepOverdueSpans(now: ContinuousClock().now + .seconds(5))
        await system.flush()

        let expired = try #require(sink.records.first { record in
            (record.event as? SpanEnded)?.exit.mode == .expired
        })
        #expect(expired.scopes == log.scopes.map(\.id))
        #expect(expired.tags == [key: "pay_1"])
    }

    @Test func expiredSpansFreeTheirKeyForReuse() async {
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)

        log.begin(for: "flow", lifetime: .bounded(budget: .seconds(1)))
        system.sweepOverdueSpans(now: ContinuousClock().now + .seconds(5))

        // A fresh begin after expiry must not read as superseded.
        log.begin(for: "flow", lifetime: .indefinite)
        log.end(for: "flow", exit: .success)
        await system.flush()

        let ends = sink.records.compactMap { $0.event as? SpanEnded }
        #expect(ends.map(\.exit.mode) == [.expired, .success])
    }

    @Test func theWatchdogExpiresSpansOnItsOwn() async {
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)

        log.begin(for: "quick", lifetime: .bounded(budget: .milliseconds(20)))

        let expired = await waitUntil {
            sink.records.contains { record in
                (record.event as? SpanEnded)?.exit.mode == .expired
            }
        }
        #expect(expired)
    }

    // MARK: Drop policy

    @Test func overflowNeverDropsScopeDefinitions() async throws {
        let gate = GateSink()
        let system = Periscope(
            configuration: Periscope.Configuration(pendingBufferCapacity: 3),
            sinks: [gate, sink],
        )
        let log = Log<AppLogs>(system: system)

        log.info("r0")
        let drainBlocked = await waitUntil { gate.batchCount >= 1 }
        try #require(drainBlocked)

        // Interleave fresh scope definitions with enough records to force
        // the drop policy: records may drop, definitions must not.
        var children: [LogScope] = []
        for index in 1 ... 6 {
            let child = log(for: "child-\(index)")
            children.append(child.primaryScope)
            child.info("r\(index)")
        }
        gate.open()
        await system.flush()

        for child in children {
            #expect(sink.definedScopes.contains(child))
        }
        let messages = sink.records.map(\.message)
        #expect(messages.contains("3 log event(s) dropped before delivery"))
        #expect(messages.suffix(3) == ["r4", "r5", "r6"])
        #expect(!messages.contains("r1"))
    }

    @Test(arguments: [0x5EED_0001, 2, 42, 987_654_321] as [UInt64])
    func pipelineSurvivesSeededConcurrentInterleavings(seed: UInt64) async {
        enum FuzzOp: Sendable {
            case emit
            case derive
            case flush
            case addSink(Int)
        }

        // Generate the whole interleaving script up front so a failing seed
        // replays exactly.
        var rng = SeededRandom(seed: seed)
        let taskCount = 4
        let opsPerTask = 60
        let extraSinks = [CapturingSink(), CapturingSink()]
        var scripts: [[FuzzOp]] = []
        var unusedExtraSinks = Array(extraSinks.indices)
        for task in 0 ..< taskCount {
            var script: [FuzzOp] = []
            for _ in 0 ..< opsPerTask {
                switch Int.random(in: 0 ..< 100, using: &rng) {
                    case ..<70:
                        script.append(.emit)
                    case ..<85:
                        script.append(.derive)
                    case ..<95:
                        script.append(.flush)
                    default:
                        // Sinks register once each, from the first task only.
                        if task == 0, !unusedExtraSinks.isEmpty {
                            script.append(.addSink(unusedExtraSinks.removeFirst()))
                        } else {
                            script.append(.emit)
                        }
                }
            }
            scripts.append(script)
        }

        let system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
        let emittedByTask = await withTaskGroup(
            of: (task: Int, emitted: Int).self,
            returning: [Int: Int].self,
        ) { group in
            for (task, script) in scripts.enumerated() {
                group.addTask {
                    var log = Log<AppLogs>(system: system)(for: "task-\(task)")
                    var emitted = 0
                    var derived = 0
                    for op in script {
                        switch op {
                            case .emit:
                                log.info("t\(task)-\(emitted)")
                                emitted += 1
                            case .derive:
                                derived += 1
                                log = log(for: "d\(derived)")
                            case .flush:
                                await system.flush()
                            case let .addSink(index):
                                system.add(sink: extraSinks[index])
                        }
                    }
                    return (task, emitted)
                }
            }
            var counts: [Int: Int] = [:]
            for await result in group {
                counts[result.task] = result.emitted
            }
            return counts
        }
        await system.flush()

        // Nothing lost, nothing duplicated, per-emitter order preserved.
        let messages = sink.records.map(\.message)
        let totalEmitted = emittedByTask.values.reduce(0, +)
        #expect(messages.count == totalEmitted)
        #expect(Set(messages).count == messages.count)
        for (task, emitted) in emittedByTask {
            let expected = (0 ..< emitted).map { "t\(task)-\($0)" }
            #expect(messages.filter { $0.hasPrefix("t\(task)-") } == expected)
        }

        // Every sink — including late-added ones fed by the scope replay —
        // saw each record's scopes defined before the record itself.
        for candidate in [sink] + extraSinks {
            var defined: Set<ScopeID> = []
            for delivery in candidate.deliveries {
                switch delivery {
                    case let .scopes(scopes):
                        defined.formUnion(scopes.map(\.id))
                    case let .records(records):
                        for record in records {
                            #expect(record.scopes.allSatisfy(defined.contains))
                        }
                }
            }
        }
    }

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
