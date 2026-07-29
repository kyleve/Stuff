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

    @Test func removedSinkReceivesNothingFurther() async {
        let system = makeSystem()
        let detachable = CapturingSink()
        let token = system.add(sink: detachable)
        let log = Log<AppLogs>(system: system)

        log.info("before")
        await system.remove(token)
        log.info("after")
        await system.flush()

        #expect(detachable.records.map(\.message) == ["before"])
        // The sink that stayed keeps receiving, so the removal detached one
        // registration rather than stalling the pipeline.
        #expect(sink.records.map(\.message) == ["before", "after"])
    }

    @Test func removalDeliversAndFlushesWhatTheSinkWasOwed() async {
        let system = makeSystem()
        let detachable = CapturingSink()
        let token = system.add(sink: detachable)

        Log<AppLogs>(system: system).info("owed")
        // No flush first: removal alone must drain the pending record into the
        // sink and flush it, since nothing else can once it's detached.
        await system.remove(token)

        #expect(detachable.records.map(\.message) == ["owed"])
        #expect(detachable.flushCount == 1)
    }

    @Test func removingTheSameTokenTwiceIsANoOp() async {
        let system = makeSystem()
        let detachable = CapturingSink()
        let token = system.add(sink: detachable)

        await system.remove(token)
        await system.remove(token)
        Log<AppLogs>(system: system).info("after")
        await system.flush()

        #expect(detachable.records.isEmpty)
        #expect(detachable.flushCount == 1)
        #expect(sink.records.map(\.message) == ["after"])
    }

    @Test func removalDetachesOnlyItsOwnRegistrationOfAnIdenticalSink() async {
        let system = makeSystem()
        // Two registrations of one sink value: the token, not the sink, is
        // the identity being removed.
        let twice = CapturingSink()
        let first = system.add(sink: twice)
        system.add(sink: twice)

        await system.remove(first)
        Log<AppLogs>(system: system).info("still delivered")
        await system.flush()

        #expect(twice.records.map(\.message) == ["still delivered"])
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

    @Test func beganRecordsReachLiveObserversAndTheRecentBuffer() async {
        // begin(for:) buffers its began through beginSpan, bypassing
        // record(_:) — the live-stream and recent-buffer side effects must
        // not drift between the two paths.
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)

        var iterator = system.liveRecords().makeAsyncIterator()
        log.begin(for: "checkout", lifetime: .indefinite)

        let live = await iterator.next()
        #expect(live?.event is SpanBegan)
        #expect(system.recentRecords().contains { $0.event is SpanBegan })
        log.end(for: "checkout", exit: .success)
    }

    @Test func liveObserversSeeSpanLifecyclesInBufferedOrder() async {
        // A re-begin closes the prior span as superseded; the live stream
        // must replay the exact buffered order — began, began, superseded
        // end, end — never an end ahead of its began.
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)

        var iterator = system.liveRecords().makeAsyncIterator()
        log.begin(for: "checkout", lifetime: .indefinite)
        log.begin(for: "checkout", lifetime: .indefinite)
        log.end(for: "checkout", exit: .success)

        let first = await iterator.next()
        let second = await iterator.next()
        let third = await iterator.next()
        let fourth = await iterator.next()
        #expect(first?.event is SpanBegan)
        #expect(second?.event is SpanBegan)
        #expect((third?.spanExit)?.mode == .superseded)
        #expect(third?.spanID == first?.spanID)
        #expect((fourth?.spanExit)?.mode == .success)
        #expect(fourth?.spanID == second?.spanID)
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

    @Test func inspectModeStreamsConvergeUnderConcurrentWriters() async {
        let system = makeSystem()
        var iterator = system.inspectModeChanges().makeAsyncIterator()
        #expect(await iterator.next() == false)

        // Hammer the flag from two tasks, then make one final authoritative
        // write. In-lock yields mean the newest buffered value is always
        // the flag's final state — an out-of-order yield would strand the
        // subscriber on the losing value.
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for _ in 0 ..< 200 {
                    system.isInspectModeEnabled = true
                }
            }
            group.addTask {
                for _ in 0 ..< 200 {
                    system.isInspectModeEnabled = false
                }
            }
            await group.waitForAll()
        }
        system.isInspectModeEnabled = true

        // Nothing consumed during the storm, so bufferingNewest(1) holds
        // exactly one value: with in-lock yields it must be the final one.
        #expect(await iterator.next() == true)
        #expect(system.isInspectModeEnabled)
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

    // MARK: Span pairs and floors

    @Test func spanEndsBypassFloorsRaisedMidSpan() async {
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)

        log.begin(for: "pay_1", lifetime: .indefinite)
        system.minimumLevel = .fault
        log.end(for: "pay_1", exit: .success) // .info — would normally floor
        await system.flush()

        let ends = sink.records.compactMap { $0.event as? SpanEnded }
        #expect(ends.map(\.exit.mode) == [.success])
    }

    @Test func flooredBeginsSilenceTheWholeSpan() async {
        let system = makeSystem()
        system.minimumLevel = .fault
        let log = Log<AppLogs>(system: system)

        log.begin(for: "hidden", lifetime: .indefinite)
        system.minimumLevel = nil // even reopening the floors mid-span
        log.end(for: "hidden", exit: .failure("boom"))
        await system.flush()

        // Neither half emitted — floors hid the span entirely, never a
        // dangling end. (No "without a matching begin" warning either: the
        // span was tracked, just silent.)
        #expect(sink.records.isEmpty)
    }

    @Test func expiredEndsFollowTheirBeganAcrossFloorChanges() async {
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)

        log.begin(for: "recorded", lifetime: .bounded(budget: .seconds(1)))
        system.minimumLevel = .fault
        log.begin(for: "hidden", lifetime: .bounded(budget: .seconds(1)))

        system.sweepOverdueSpans(now: ContinuousClock().now + .seconds(5))
        await system.flush()

        let ends = sink.records.compactMap { $0.event as? SpanEnded }
        #expect(ends.map(\.name) == ["recorded"])
        #expect(ends.first?.exit.mode == .expired)
    }

    @Test func supersededEndsFollowTheirBegan() async {
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)

        log.begin(for: "flow", lifetime: .indefinite)
        system.minimumLevel = .fault
        log.begin(for: "flow", lifetime: .indefinite) // supersedes silently-visible pair

        await system.flush()

        // The first span's began was recorded, so its superseded end is
        // too; the second began is floored and its whole span stays silent.
        let ends = sink.records.compactMap { $0.event as? SpanEnded }
        #expect(ends.map(\.exit.mode) == [.superseded])
        #expect(sink.records.compactMap { $0.event as? SpanBegan }.count == 1)
    }

    @Test func measureEndsBypassFloorsRaisedMidBody() async {
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)

        log.measure("save") {
            system.minimumLevel = .fault
        }
        await system.flush()

        let ends = sink.records.compactMap { $0.event as? SpanEnded }
        #expect(ends.map(\.exit.mode) == [.success])
    }

    @Test func flooredMeasuresAreFullySilentIncludingOverdue() async {
        let system = makeSystem()
        system.minimumLevel = .fault
        let log = Log<AppLogs>(system: system)

        await log.measure("hidden", budget: .milliseconds(5)) {
            // Outlast the budget so a non-suppressed sentinel would fire.
            try? await Task.sleep(for: .milliseconds(30))
        }
        await system.flush()

        #expect(sink.records.isEmpty)
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

    @Test func redactionCannotSplitSpanPairs() async throws {
        // The hook tries to suppress every span record. Suppression is
        // transform-only for pairs: a stripped copy records instead —
        // tags and attachments dropped, the exit reason blanked — so
        // redaction can never strand half of a span.
        let key = LogTagKey("payment-id")
        let system = Periscope(
            configuration: Periscope.Configuration(redact: { record in
                record.spanID == nil ? record : nil
            }),
            sinks: [sink],
        )
        let log = Log<AppLogs>(system: system).tagged(key, "pay_1")

        log.begin(for: "checkout", lifetime: .indefinite)
        log.end(for: "checkout", exit: .failure("card 4242 declined"))
        await system.flush()

        let began = try #require(sink.records.first { $0.event is SpanBegan })
        let ended = try #require(sink.records.first { $0.event is SpanEnded })
        #expect(began.tags.isEmpty)
        #expect(ended.tags.isEmpty)
        #expect(ended.spanID == began.spanID)
        #expect(ended.spanExit?.mode == .failure)
        #expect(ended.spanExit?.reason == nil)
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
        #expect(expired.tags == [LogTag(key: key, value: "pay_1")])
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

    @Test func openSpansSnapshotTracksLifecycleLongestRunningFirst() {
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)
        #expect(system.openSpans().isEmpty)

        log.begin(for: "first", lifetime: .indefinite)
        log.begin(for: "second", lifetime: .bounded(budget: .seconds(60)))
        #expect(system.openSpans().map(\.name) == ["first", "second"])

        log.end(for: "first", exit: .success)
        #expect(system.openSpans().map(\.name) == ["second"])

        system.sweepOverdueSpans(now: ContinuousClock().now + .seconds(120))
        #expect(system.openSpans().isEmpty)
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

    @Test func anEarlierDeadlineWakesTheWatchdogSooner() async {
        let system = makeSystem()
        let log = Log<AppLogs>(system: system)

        // The watchdog is already asleep until the 30s deadline when the
        // 20ms span opens — only a respawn with the earlier wake time can
        // expire it within this test's budget.
        log.begin(for: "slow", lifetime: .bounded(budget: .seconds(30)))
        log.begin(for: "quick", lifetime: .bounded(budget: .milliseconds(20)))

        let expired = await waitUntil {
            sink.records.contains { record in
                guard let ended = record.event as? SpanEnded else { return false }
                return ended.name == "quick" && ended.exit.mode == .expired
            }
        }
        #expect(expired)
    }

    @Test func theWatchdogDoesNotKeepDeadSystemsAlive() async {
        weak var weakSystem: Periscope?
        do {
            let system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
            weakSystem = system
            let log = Log<AppLogs>(system: system)
            log.begin(for: "long", lifetime: .bounded(budget: .seconds(120)))
            // Let the drain retire so its (short-lived) strong capture ends.
            await system.flush()
        }

        // The watchdog sleeps until the 120s deadline; holding the system
        // strongly through that sleep would fail this within the budget.
        let released = await waitUntil { weakSystem == nil }
        #expect(released)
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

    @Test func customEventsCanOptIntoDropProtection() async throws {
        struct AuditEvent: LogEvent {
            static let isProtectedFromDropping = true
            var message: String {
                "audit-entry"
            }
        }

        let gate = GateSink()
        let system = Periscope(
            configuration: Periscope.Configuration(pendingBufferCapacity: 3),
            sinks: [gate, sink],
        )
        let log = Log<AppLogs>(system: system)

        log.info("r0")
        let drainBlocked = await waitUntil { gate.batchCount >= 1 }
        try #require(drainBlocked)

        log(AuditEvent.self) { AuditEvent() }
        for index in 1 ... 5 {
            log.info("r\(index)")
        }
        gate.open()
        await system.flush()

        let messages = sink.records.map(\.message)
        #expect(messages.contains("audit-entry"))
        #expect(!messages.contains("r1"))
    }

    @Test func overflowNeverSplitsSpanPairs() async throws {
        let gate = GateSink()
        let system = Periscope(
            configuration: Periscope.Configuration(pendingBufferCapacity: 3),
            sinks: [gate, sink],
        )
        let log = Log<AppLogs>(system: system)

        log.info("r0")
        let drainBlocked = await waitUntil { gate.batchCount >= 1 }
        try #require(drainBlocked)

        // A complete span pair queues first; the freeform flood behind it
        // overflows the queue. Only the freeform records may drop.
        log.begin(for: "checkout", lifetime: .indefinite)
        log.end(for: "checkout", exit: .success)
        for index in 1 ... 4 {
            log.info("r\(index)")
        }
        gate.open()
        await system.flush()

        let messages = sink.records.map(\.message)
        #expect(messages.contains("▶ checkout"))
        #expect(messages.contains { $0.hasPrefix("◀ checkout succeeded") })
        #expect(messages.contains("3 log event(s) dropped before delivery"))
        #expect(messages.contains("r4"))
        #expect(!messages.contains("r1"))
    }

    @Test(arguments: [0xBEA7_0001, 11, 4242, 555_555_555] as [UInt64])
    func spanLifecyclesSurviveSeededConcurrentInterleavings(seed: UInt64) async {
        enum FuzzOp: Sendable {
            case emit(levelIndex: Int)
            case begin(key: Int)
            case end(key: Int)
            case setFloor(index: Int)
            case flush
        }

        let levels = 4
        let floors: [LogLevel?] = [nil, .info, .warning, .fault]
        let keyCount = 3
        let taskCount = 4
        let opsPerTask = 60

        // Generate the whole interleaving script up front so a failing seed
        // replays exactly.
        var rng = SeededRandom(seed: seed)
        var scripts: [[FuzzOp]] = []
        for _ in 0 ..< taskCount {
            var script: [FuzzOp] = []
            for _ in 0 ..< opsPerTask {
                switch Int.random(in: 0 ..< 100, using: &rng) {
                    case ..<40:
                        script.append(.emit(levelIndex: Int.random(in: 0 ..< levels, using: &rng)))
                    case ..<60:
                        script.append(.begin(key: Int.random(in: 0 ..< keyCount, using: &rng)))
                    case ..<75:
                        script.append(.end(key: Int.random(in: 0 ..< keyCount, using: &rng)))
                    case ..<92:
                        script.append(.setFloor(index: Int.random(
                            in: 0 ..< floors.count,
                            using: &rng,
                        )))
                    default:
                        script.append(.flush)
                }
            }
            scripts.append(script)
        }

        // A small pending queue adds drop pressure under load: drops only
        // ever remove freeform records (oldest first, order preserved) —
        // never a span half, which stays assertable below.
        let system = Periscope(
            configuration: Periscope.Configuration(pendingBufferCapacity: 16),
            sinks: [sink],
        )
        await withTaskGroup(of: Void.self) { group in
            for (task, script) in scripts.enumerated() {
                group.addTask {
                    // Freeform emits go through a per-task child scope so
                    // per-emitter order is checkable; span keys stay on the
                    // shared root scope so begins collide — and supersede —
                    // across tasks.
                    let rootLog = Log<AppLogs>(system: system)
                    let taskLog = rootLog(for: "task-\(task)")
                    var emitted = 0
                    for op in script {
                        switch op {
                            case let .emit(levelIndex):
                                let text = "t\(task)-\(emitted)"
                                switch levelIndex {
                                    case 0: taskLog.debug(text)
                                    case 1: taskLog.info(text)
                                    case 2: taskLog.warning(text)
                                    default: taskLog.error(text)
                                }
                                emitted += 1
                            case let .begin(key):
                                rootLog.begin(for: "k\(key)", lifetime: .indefinite)
                            case let .end(key):
                                rootLog.end(for: "k\(key)", exit: .success)
                            case let .setFloor(index):
                                system.minimumLevel = floors[index]
                            case .flush:
                                await system.flush()
                        }
                    }
                }
            }
        }

        // Close whatever the scripts left open, then drain.
        let rootLog = Log<AppLogs>(system: system)
        for key in 0 ..< keyCount {
            rootLog.end(for: "k\(key)", exit: .success)
        }
        await system.flush()
        #expect(system.openSpans().isEmpty)

        // Floors and drops only *remove*: each task's delivered freeform
        // messages stay in emission order (strictly increasing suffixes,
        // no duplicates), whatever the floor or queue was doing.
        let messages = sink.records.map(\.message)
        for task in 0 ..< taskCount {
            let prefix = "t\(task)-"
            let delivered = messages
                .filter { $0.hasPrefix(prefix) }
                .compactMap { Int($0.dropFirst(prefix.count)) }
            #expect(delivered == delivered.sorted())
            #expect(Set(delivered).count == delivered.count)
        }

        // Span pairs never dangle across floor changes or supersession:
        // every span the sink saw is exactly a began *then* its ended —
        // a floored begin silences the whole pair instead, and
        // registration + began land atomically (`beginSpan`) so no
        // interleaving delivers an end first.
        var lifecycles: [SpanID: [LogRecord]] = [:]
        for record in sink.records {
            guard let span = record.spanID else { continue }
            lifecycles[span, default: []].append(record)
        }
        for (span, records) in lifecycles {
            #expect(records.count == 2, "span \(span) should be a began/ended pair")
            #expect(records.first?.event is SpanBegan)
            #expect(records.last?.event is SpanEnded)
        }

        // Scope definitions still precede every record that references them.
        var defined: Set<ScopeID> = []
        for delivery in sink.deliveries {
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

    // MARK: Ambient state

    @Test func recordsCarryNoAmbientStateBeforeAnySourceReports() async {
        let system = makeSystem()
        Log<AppLogs>(system: system).info("first")
        await system.flush()

        #expect(sink.records.first?.ambient == nil)
    }

    @Test func ambientStateStampsOntoEverySubsequentRecord() async throws {
        let system = makeSystem()
        let ambient = Log<AmbientEvent>(system: system)
        ambient { AmbientEvent(kind: .network, value: "satisfied") }
        Log<AppLogs>(system: system).info("after")
        await system.flush()

        let record = try #require(sink.records.first { $0.message == "after" })
        #expect(record.ambient?[.network] == "satisfied")
    }

    /// The ambient event must carry the state it *announces*, not the one it
    /// replaced — otherwise the event and its own snapshot disagree.
    @Test func anAmbientEventCarriesTheStateItAnnounces() async {
        let system = makeSystem()
        let ambient = Log<AmbientEvent>(system: system)
        ambient { AmbientEvent(kind: .thermalState, value: "nominal") }
        ambient { AmbientEvent(kind: .thermalState, value: "serious") }
        await system.flush()

        let changes = sink.records.filter { $0.eventName == AmbientEvent.eventName }
        #expect(changes.map { $0.ambient?[.thermalState] } == ["nominal", "serious"])
    }

    @Test func momentaryAmbientEventsDoNotStickToLaterRecords() async throws {
        let system = makeSystem()
        let ambient = Log<AmbientEvent>(system: system)
        ambient { AmbientEvent(kind: .network, value: "satisfied") }
        ambient {
            AmbientEvent(
                kind: .memory,
                value: "warning",
                level: .warning,
                reporting: .occurrence,
            )
        }
        Log<AppLogs>(system: system).info("after")
        await system.flush()

        let record = try #require(sink.records.first { $0.message == "after" })
        #expect(record.ambient?[.memory] == nil)
        #expect(record.ambient?[.network] == "satisfied")
    }

    /// Re-reporting the current value must not mint a new snapshot identity,
    /// or the store would write a row per repeat instead of per state.
    @Test func unchangedAmbientStateReusesOneSnapshotIdentity() async {
        let system = makeSystem()
        let ambient = Log<AmbientEvent>(system: system)
        let log = Log<AppLogs>(system: system)
        ambient { AmbientEvent(kind: .network, value: "satisfied") }
        log.info("one")
        ambient { AmbientEvent(kind: .network, value: "satisfied") }
        log.info("two")
        await system.flush()

        let ids = sink.records.compactMap(\.ambient?.id)
        #expect(ids.count == 4)
        #expect(Set(ids).count == 1)
    }

    @Test func spanRecordsCarryAmbientState() async {
        let system = makeSystem()
        let ambient = Log<AmbientEvent>(system: system)
        ambient { AmbientEvent(kind: .powerMode, value: "low-power") }
        Log<AppLogs>(system: system).measure("work") {}
        await system.flush()

        let spans = sink.records.filter { $0.spanID != nil }
        #expect(spans.count == 2)
        #expect(spans.allSatisfy { $0.ambient?[.powerMode] == "low-power" })
    }

    /// The drop report is synthesized during the drain and never passes
    /// through the buffer path, so it needs its own stamp — a gap in the
    /// history should still say what the system was doing.
    @Test func theDropReportCarriesAmbientState() async throws {
        let gate = GateSink()
        let system = Periscope(
            configuration: Periscope.Configuration(pendingBufferCapacity: 3),
            sinks: [gate, sink],
        )
        let log = Log<AppLogs>(system: system)
        let ambient = Log<AmbientEvent>(system: system)
        ambient { AmbientEvent(kind: .network, value: "unsatisfied") }

        log.info("r0")
        let drainBlocked = await waitUntil { gate.batchCount >= 1 }
        try #require(drainBlocked)
        for index in 1 ... 5 {
            log.info("r\(index)")
        }
        gate.open()
        await system.flush()

        let report = try #require(
            sink.records.first { $0.eventName == Periscope.DroppedEvents.eventName },
        )
        #expect(report.ambient?[.network] == "unsatisfied")
    }

    @Test func liveObserversSeeTheStampedRecord() async throws {
        let system = makeSystem()
        let ambient = Log<AmbientEvent>(system: system)
        ambient { AmbientEvent(kind: .network, value: "satisfied") }
        let records = system.liveRecords()

        Log<AppLogs>(system: system).info("live")

        let first = try #require(await records.first { _ in true })
        #expect(first.ambient?[.network] == "satisfied")
    }

    /// Floors are routing, not scrubbing: an ambient event they discard
    /// still folds into the running snapshot, or every later record would
    /// carry the state the discarded event replaced.
    @Test func flooredAmbientEventsStillFoldIntoTheSnapshot() async throws {
        let system = makeSystem()
        let ambient = Log<AmbientEvent>(system: system)
        ambient { AmbientEvent(kind: .network, value: "satisfied") }
        system.minimumLevel = .warning

        ambient { AmbientEvent(kind: .network, value: "unsatisfied") } // .info — floored
        Log<AppLogs>(system: system).warning("after")
        await system.flush()

        let record = try #require(sink.records.first { $0.message == "after" })
        #expect(record.ambient?[.network] == "unsatisfied")
        // The floor still discarded the event itself.
        #expect(!sink.records.contains { $0.eventName == AmbientEvent.eventName
                && $0.message.contains("unsatisfied")
        })
    }

    /// Suppression is content scrubbing: the snapshot must neither smear
    /// the suppressed value across later records nor keep claiming the
    /// stale previous one — it forgets the kind.
    @Test func redactionSuppressedAmbientEventsClearTheirKind() async throws {
        let system = Periscope(
            configuration: Periscope.Configuration(redact: { record in
                record.message.contains("secret") ? nil : record
            }),
            sinks: [sink],
        )
        let ambient = Log<AmbientEvent>(system: system)
        ambient { AmbientEvent(kind: .network, value: "wifi-public") }
        ambient { AmbientEvent(kind: .thermalState, value: "nominal") }

        ambient { AmbientEvent(kind: .network, value: "wifi-secret") } // suppressed
        Log<AppLogs>(system: system).info("after")
        await system.flush()

        let record = try #require(sink.records.first { $0.message == "after" })
        #expect(record.ambient?[.network] == nil)
        #expect(record.ambient?[.thermalState] == "nominal")
    }
}
