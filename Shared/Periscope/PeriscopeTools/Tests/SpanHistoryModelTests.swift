import Foundation
@_spi(Testing) import PeriscopeCore
@testable import PeriscopeTools
import Testing

@MainActor
struct SpanHistoryModelTests {
    /// Closed spans group by kind; each summary carries its instance count and
    /// its ended events, and the kinds order busiest-first (name breaks ties).
    @Test func groupsClosedSpansByKindOrderedByCount() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        await store.write([
            spanEnded(SpanID(), name: "save", at: date(0), duration: .seconds(1), scope: root.id),
            spanEnded(SpanID(), name: "save", at: date(1), duration: .seconds(2), scope: root.id),
            spanEnded(SpanID(), name: "save", at: date(2), duration: .seconds(3), scope: root.id),
            spanEnded(SpanID(), name: "load", at: date(3), duration: .seconds(1), scope: root.id),
        ])

        let model = SpanHistoryModel(store: store)
        await model.load()

        guard case let .loaded(summaries) = model.state else {
            Issue.record("Expected loaded summaries, got \(model.state)")
            return
        }
        #expect(summaries.map(\.kind.text) == ["save", "load"])
        #expect(summaries.map(\.count) == [3, 1])
        // The drill-in list is newest first.
        let save = try #require(summaries.first)
        #expect(save.events.map(\.date) == [date(2), date(1), date(0)])
    }

    /// The p50/p90/p95/p99 use the nearest-rank method over the recorded
    /// durations, so each reported value is an actual observed sample.
    @Test func computesNearestRankPercentiles() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        // Ten instances with durations 1...10 seconds.
        for second in 1 ... 10 {
            await store.write([
                spanEnded(
                    SpanID(),
                    name: "work",
                    at: date(TimeInterval(second)),
                    duration: .seconds(second),
                    scope: root.id,
                ),
            ])
        }

        let model = SpanHistoryModel(store: store)
        await model.load()

        guard case let .loaded(summaries) = model.state else {
            Issue.record("Expected loaded summaries, got \(model.state)")
            return
        }
        let percentiles = try #require(summaries.first?.percentiles)
        #expect(percentiles.p50 == .seconds(5))
        #expect(percentiles.p90 == .seconds(9))
        #expect(percentiles.p95 == .seconds(10))
        #expect(percentiles.p99 == .seconds(10))
    }

    /// A kind whose instances never recorded a duration (all orphaned) still
    /// counts its instances but reports no percentiles rather than inventing 0.
    @Test func countsOrphanedInstancesButReportsNoPercentiles() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        let orphan = SpanID()
        await store.write([
            LogRecord(
                date: date(0),
                event: SpanEnded(
                    spanID: orphan,
                    name: "lost",
                    duration: nil,
                    exit: SpanExit(mode: .orphaned, reason: nil),
                ),
                scopes: [root.id],
            ),
        ])

        let model = SpanHistoryModel(store: store)
        await model.load()

        guard case let .loaded(summaries) = model.state else {
            Issue.record("Expected loaded summaries, got \(model.state)")
            return
        }
        let lost = try #require(summaries.first)
        #expect(lost.count == 1)
        #expect(lost.percentiles == nil)
    }

    /// A kind with a mix of measured and orphaned instances counts all of them
    /// but draws percentiles only from the ones with a duration.
    @Test func percentilesIgnoreDurationlessInstances() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        await store.write([
            spanEnded(SpanID(), name: "mixed", at: date(0), duration: .seconds(2), scope: root.id),
            LogRecord(
                date: date(1),
                event: SpanEnded(
                    spanID: SpanID(),
                    name: "mixed",
                    duration: nil,
                    exit: SpanExit(mode: .orphaned, reason: nil),
                ),
                scopes: [root.id],
            ),
        ])

        let model = SpanHistoryModel(store: store)
        await model.load()

        guard case let .loaded(summaries) = model.state else {
            Issue.record("Expected loaded summaries, got \(model.state)")
            return
        }
        let mixed = try #require(summaries.first)
        #expect(mixed.count == 2)
        #expect(mixed.percentiles?.p50 == .seconds(2))
    }

    /// Only closed spans (ends) appear — a lone `SpanBegan` contributes nothing.
    @Test func ignoresOpenSpans() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        await store.write([
            spanBegan(SpanID(), name: "open", at: date(0), scope: root.id),
        ])

        let model = SpanHistoryModel(store: store)
        await model.load()

        guard case let .loaded(summaries) = model.state else {
            Issue.record("Expected loaded summaries, got \(model.state)")
            return
        }
        #expect(summaries.isEmpty)
    }

    @Test func loadsEmptyWhenNoSpansRecorded() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        await store.write([makeRecord("not a span", date: date(0), scopes: [root.id])])

        let model = SpanHistoryModel(store: store)
        await model.load()

        guard case let .loaded(summaries) = model.state else {
            Issue.record("Expected loaded (empty) summaries, got \(model.state)")
            return
        }
        #expect(summaries.isEmpty)
    }

    @Test func liveRefreshesWhenTheStoreCommits() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        let model = SpanHistoryModel(store: store)

        let running = Task { await model.run() }
        defer { running.cancel() }

        _ = await waitUntil {
            if case .loaded = model.state { return true }
            return false
        }

        await store.write([
            spanEnded(SpanID(), name: "late", at: date(0), duration: .seconds(1), scope: root.id),
        ])

        let shown = await waitUntil {
            guard case let .loaded(summaries) = model.state else { return false }
            return summaries.map(\.kind.text) == ["late"]
        }
        #expect(shown)
    }

    /// Ends arriving in a later commit fold into the accumulated summaries via
    /// the incremental `afterSequence` fetch, without re-reading the whole store.
    @Test func accumulatesEndsAcrossCommits() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        let model = SpanHistoryModel(store: store)

        let running = Task { await model.run() }
        defer { running.cancel() }

        await store.write([
            spanEnded(SpanID(), name: "job", at: date(0), duration: .seconds(1), scope: root.id),
        ])
        let first = await waitUntil {
            guard case let .loaded(summaries) = model.state else { return false }
            return summaries.first?.count == 1
        }
        #expect(first)

        await store.write([
            spanEnded(SpanID(), name: "job", at: date(1), duration: .seconds(3), scope: root.id),
        ])
        let second = await waitUntil {
            guard case let .loaded(summaries) = model.state else { return false }
            return summaries.first?.count == 2
        }
        #expect(second)
    }

    /// Restarting `run()` re-loads over ends already accumulated, but the
    /// sequence-filtered merge is idempotent: an instance isn't counted twice.
    @Test func restartingRunDoesNotDoubleCount() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        let model = SpanHistoryModel(store: store)

        let first = Task { await model.run() }
        await store.write([
            spanEnded(SpanID(), name: "a", at: date(0), duration: .seconds(1), scope: root.id),
        ])
        _ = await waitUntil {
            guard case let .loaded(summaries) = model.state else { return false }
            return summaries.first?.count == 1
        }
        first.cancel()

        let second = Task { await model.run() }
        defer { second.cancel() }
        await store.write([
            spanEnded(SpanID(), name: "a", at: date(1), duration: .seconds(2), scope: root.id),
        ])

        let total = await waitUntil {
            guard case let .loaded(summaries) = model.state else { return false }
            return summaries.count == 1 && summaries.first?.count == 2
        }
        #expect(total)
    }

    // MARK: - Unreadable payloads

    /// An end whose payload won't decode still counts, grouped under a name
    /// recovered from its message — and marked as recovered, so the bucket
    /// doesn't read as a span kind the code declares.
    @Test func groupsAnUnreadableEndUnderARecoveredName() {
        let summaries = SpanHistoryModel.summaries(from: [
            storedSpanEvent(
                eventName: SpanEnded.eventName,
                spanID: SpanID(),
                message: "◀ save",
                at: date(0),
                payload: unreadablePayload,
                exitMode: .success,
            ),
        ])

        #expect(summaries.map(\.kind) == [.recovered("save")])
        #expect(summaries.first?.count == 1)
        // No duration survived the corrupt payload, so there is nothing to
        // compute percentiles from — reporting zero would invent a measurement.
        #expect(summaries.first?.percentiles == nil)
    }

    /// The recovered name matches the real kind's name here, and the buckets
    /// still don't merge: a row whose payload is corrupt can't be presented as
    /// another instance of a kind that decoded fine.
    @Test func aRecoveredBucketStaysSeparateFromTheRecordedKind() throws {
        let summaries = try SpanHistoryModel.summaries(from: [
            storedSpanEnded(
                SpanID(),
                name: "save",
                at: date(0),
                duration: .seconds(1),
                exit: .success,
            ),
            storedSpanEvent(
                eventName: SpanEnded.eventName,
                spanID: SpanID(),
                message: "◀ save",
                at: date(1),
                payload: unreadablePayload,
                exitMode: .success,
            ),
        ])

        #expect(summaries.count == 2)
        #expect(Set(summaries.map(\.kind)) == [.recorded("save"), .recovered("save")])
    }

    // MARK: - Build scoping

    /// Two sessions at different optimization levels, each with one recorded
    /// `save` — the shape the scopes exist to separate. `current` is the
    /// unoptimized one, since it's started last.
    private func makeTwoBuildStore() async throws -> (
        store: PeriscopeStore,
        root: LogScope,
        optimizedSession: LogSession
    ) {
        let (store, root, _, _) = try await makeSeededStore(
            sessionAttributes: [.optimizationLevel: "-O"],
        )
        let optimized = try #require(await store.currentSession)
        await store.write([
            spanEnded(SpanID(), name: "save", at: date(0), duration: .seconds(1), scope: root.id),
        ])

        try await store.startSession(makeSession(attributes: [.optimizationLevel: "-Onone"]))
        await store.write([
            spanEnded(SpanID(), name: "save", at: date(1), duration: .seconds(9), scope: root.id),
        ])
        return (store, root, optimized)
    }

    @Test func poolsEveryBuildByDefault() async throws {
        let (store, _, _) = try await makeTwoBuildStore()
        let model = SpanHistoryModel(store: store)
        await model.load()

        #expect(model.scope == .all)
        guard case let .loaded(summaries) = model.state else {
            Issue.record("Expected loaded summaries, got \(model.state)")
            return
        }
        #expect(summaries.first?.count == 2)
    }

    /// Narrowing to this session drops the other build's durations, so the
    /// percentiles describe one build rather than an average of two.
    @Test func narrowingToThisSessionExcludesEarlierSessions() async throws {
        let (store, _, _) = try await makeTwoBuildStore()
        let model = SpanHistoryModel(store: store)
        await model.load()

        model.scope = .currentSession

        guard case let .loaded(summaries) = model.state else {
            Issue.record("Expected loaded summaries, got \(model.state)")
            return
        }
        #expect(summaries.first?.count == 1)
        #expect(summaries.first?.percentiles?.p50 == .seconds(9))
    }

    @Test func narrowingToTheSameOptimizationLevelExcludesOtherLevels() async throws {
        let (store, _, _) = try await makeTwoBuildStore()
        let model = SpanHistoryModel(store: store)
        await model.load()

        model.scope = .sameOptimizationLevel

        guard case let .loaded(summaries) = model.state else {
            Issue.record("Expected loaded summaries, got \(model.state)")
            return
        }
        #expect(summaries.first?.percentiles?.p50 == .seconds(9))
    }

    /// A third session at the level already selected joins the reading, which is
    /// the point of scoping by level rather than by session.
    @Test func sameOptimizationLevelSpansSessionsAtThatLevel() async throws {
        let (store, root, _) = try await makeTwoBuildStore()
        try await store.startSession(makeSession(attributes: [.optimizationLevel: "-Onone"]))
        await store.write([
            spanEnded(SpanID(), name: "save", at: date(2), duration: .seconds(7), scope: root.id),
        ])

        let model = SpanHistoryModel(store: store)
        await model.load()
        model.scope = .sameOptimizationLevel

        guard case let .loaded(summaries) = model.state else {
            Issue.record("Expected loaded summaries, got \(model.state)")
            return
        }
        #expect(summaries.first?.count == 2)
    }

    /// Re-scoping filters the ends already accumulated rather than refetching,
    /// so a span written after the load doesn't appear until the next load —
    /// which is how this pins "filter, not fetch" without a read counter.
    @Test func rescopingFiltersAccumulatedEndsRatherThanRefetching() async throws {
        let (store, root, _) = try await makeTwoBuildStore()
        let model = SpanHistoryModel(store: store)
        await model.load()
        await store.write([
            spanEnded(SpanID(), name: "save", at: date(3), duration: .seconds(4), scope: root.id),
        ])

        model.scope = .currentSession

        guard case let .loaded(scoped) = model.state else {
            Issue.record("Expected loaded summaries, got \(model.state)")
            return
        }
        #expect(scoped.first?.count == 1)

        // The next load picks the unseen end up, so it was never lost.
        await model.load()
        guard case let .loaded(reloaded) = model.state else {
            Issue.record("Expected loaded summaries, got \(model.state)")
            return
        }
        #expect(reloaded.first?.count == 2)
    }

    @Test func rescopingToTheSameScopeIsANoOp() async throws {
        let (store, _, _) = try await makeTwoBuildStore()
        let model = SpanHistoryModel(store: store)
        await model.load()
        guard case let .loaded(before) = model.state else {
            Issue.record("Expected loaded summaries, got \(model.state)")
            return
        }

        model.scope = .all

        guard case let .loaded(after) = model.state else {
            Issue.record("Expected loaded summaries, got \(model.state)")
            return
        }
        #expect(before.map(\.count) == after.map(\.count))
    }

    @Test func offersOnlyTheScopesTheSessionsCanSupport() async throws {
        // The seeded session names no optimization level, so it can't be
        // compared to others by one.
        let (store, _, _, _) = try await makeSeededStore()
        let model = SpanHistoryModel(store: store)
        await model.load()
        #expect(model.availableScopes == [.all, .currentSession])

        let (levelled, _, _) = try await makeTwoBuildStore()
        let levelledModel = SpanHistoryModel(store: levelled)
        await levelledModel.load()
        #expect(levelledModel.availableScopes == SpanHistoryScope.allCases)
    }

    @Test func summarizesWhatTheActiveScopeCovers() async throws {
        let (store, _, _) = try await makeTwoBuildStore()
        let model = SpanHistoryModel(store: store)
        await model.load()
        #expect(model.scopeSummary == "All builds · 2 sessions")

        model.scope = .currentSession
        #expect(model.scopeSummary == "This session only")

        model.scope = .sameOptimizationLevel
        #expect(model.scopeSummary == "Built at -Onone · 1 session")
    }
}

struct SpanDurationPercentilesTests {
    @Test func returnsNilForNoDurations() {
        #expect(SpanDurationPercentiles(durations: []) == nil)
    }

    /// A single sample is every percentile.
    @Test func singleSampleFillsEveryPercentile() throws {
        let percentiles = try #require(SpanDurationPercentiles(durations: [.seconds(7)]))
        #expect(percentiles.p50 == .seconds(7))
        #expect(percentiles.p90 == .seconds(7))
        #expect(percentiles.p95 == .seconds(7))
        #expect(percentiles.p99 == .seconds(7))
    }

    /// Nearest-rank is order-independent and always returns an observed sample.
    @Test func sortsBeforeRanking() throws {
        let durations: [Duration] = [.seconds(10), .seconds(3), .seconds(1), .seconds(7)]
        let percentiles = try #require(SpanDurationPercentiles(durations: durations))
        // Sorted: 1, 3, 7, 10. Ranks: p50→ceil(2)=2→3s, p90→ceil(3.6)=4→10s.
        #expect(percentiles.p50 == .seconds(3))
        #expect(percentiles.p90 == .seconds(10))
    }
}
