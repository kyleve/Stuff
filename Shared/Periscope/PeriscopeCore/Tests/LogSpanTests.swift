import Foundation
import PeriscopeCore
import Testing

private struct DatabaseLogs: LogEvent {
    enum SpanName: Hashable {
        case saveEvent
        case migration
    }

    var message: String {
        "db"
    }
}

private struct MeasureError: Error {}

struct LogSpanTests {
    let recorder = RecordingRecorder()

    @Test func measureEmitsAPairedBeginAndEnd() throws {
        let log = Log<AppLogs>(recorder: recorder)

        let result = log.measure("save") { 42 }
        #expect(result == 42)

        let records = recorder.records
        #expect(records.count == 2)
        let began = try #require(records.first?.event as? SpanBegan)
        let ended = try #require(records.last?.event as? SpanEnded)
        #expect(began.spanID == ended.spanID)
        #expect(began.name == "save")
        #expect(began.lifetime == .scoped)
        #expect(began.relaunchPolicy == .endsWithProcess)
        #expect(ended.name == "save")
        #expect(ended.exit == .success)
        let duration = try #require(ended.duration)
        #expect(duration >= .zero)
        #expect(records.allSatisfy { $0.scopes == log.scopes.map(\.id) })
    }

    @Test func measureRecordsThrownErrorsAsFailures() throws {
        let log = Log<AppLogs>(recorder: recorder)

        #expect(throws: MeasureError.self) {
            try log.measure("failing") { throw MeasureError() }
        }

        #expect(recorder.records.count == 2)
        let ended = try #require(recorder.records.last?.event as? SpanEnded)
        #expect(ended.exit.mode == .failure)
        #expect(ended.exit.reason?.contains("MeasureError") == true)
        #expect(ended.level == .warning)
    }

    @Test func measureRecordsCancellationAsCancelledNotFailed() throws {
        let log = Log<AppLogs>(recorder: recorder)

        #expect(throws: CancellationError.self) {
            try log.measure("cancelled") { throw CancellationError() }
        }

        let ended = try #require(recorder.records.last?.event as? SpanEnded)
        #expect(ended.exit == .cancelled)
        #expect(ended.level == .info)
    }

    @Test func asyncMeasureTimesAsyncWork() async throws {
        let log = Log<AppLogs>(recorder: recorder)

        let result = await log.measure("async-save") {
            await Task.yield()
            return "done"
        }
        #expect(result == "done")

        let ended = try #require(recorder.records.last?.event as? SpanEnded)
        #expect(ended.name == "async-save")
        #expect(ended.exit == .success)
    }

    @Test func typedSpanTokensResolveAgainstTheEventType() throws {
        let log = Log<DatabaseLogs>(recorder: recorder)

        log.measure(.saveEvent) {}

        let began = try #require(recorder.records.first?.event as? SpanBegan)
        #expect(began.name == "saveEvent")
    }

    @Test func beginAndEndPairAcrossRebuiltLoggers() throws {
        let first = Log<AppLogs>(recorder: recorder)(for: "payment-flow")
        first.begin(for: "pay_1", lifetime: .indefinite)

        // A logger rebuilt from the same path pairs with the open span.
        let second = Log<AppLogs>(recorder: recorder)(for: "payment-flow")
        second.end(for: "pay_1", exit: .success("payment settled"))

        let records = recorder.records
        #expect(records.count == 2)
        let began = try #require(records.first?.event as? SpanBegan)
        let ended = try #require(records.last?.event as? SpanEnded)
        #expect(began.spanID == ended.spanID)
        #expect(began.lifetime == .indefinite)
        #expect(ended.name == "pay_1")
        #expect(ended.exit == .success("payment settled"))
        #expect(ended.duration ?? .zero >= .zero)
    }

    @Test func endRecordsTheGivenExit() throws {
        let log = Log<AppLogs>(recorder: recorder)
        log.begin(for: "pay_1", lifetime: .indefinite)
        log.end(for: "pay_1", exit: .failure("card declined"))

        let ended = try #require(recorder.records.last?.event as? SpanEnded)
        #expect(ended.exit.mode == .failure)
        #expect(ended.exit.reason == "card declined")
        #expect(ended.level == .warning)
    }

    @Test func endingWithoutABeginWarnsInsteadOfEmitting() {
        let log = Log<AppLogs>(recorder: recorder)

        log.end(for: "never-began", exit: .success)

        let records = recorder.records
        #expect(records.count == 1)
        #expect(records.first?.level == .warning)
        #expect(records.first?.message.contains("without a matching begin") == true)
    }

    @Test func rebeginningSupersedesTheOpenSpan() throws {
        let log = Log<AppLogs>(recorder: recorder)

        log.begin(for: "pay_1", lifetime: .indefinite)
        log.begin(for: "pay_1", lifetime: .indefinite)
        log.end(for: "pay_1", exit: .success)

        let records = recorder.records
        #expect(records.count == 4)
        let firstBegan = try #require(records[0].event as? SpanBegan)
        let superseded = try #require(records[1].event as? SpanEnded)
        let secondBegan = try #require(records[2].event as? SpanBegan)
        let ended = try #require(records[3].event as? SpanEnded)

        #expect(superseded.spanID == firstBegan.spanID)
        #expect(superseded.exit == .superseded)
        #expect(superseded.level == .warning)
        #expect(ended.spanID == secondBegan.spanID)
        #expect(ended.exit == .success)
        #expect(secondBegan.spanID != firstBegan.spanID)
    }

    @Test func supersededSpansKeepTheirBeginContext() throws {
        let key = LogTagKey("payment-id")
        let original = Log<AppLogs>(recorder: recorder).tagged(key, "pay_1")
        original.begin(for: "flow", lifetime: .indefinite)

        // Re-begin from an untagged logger on the same scope: the
        // superseded end still carries the original begin's tags.
        let rebeginner = Log<AppLogs>(recorder: recorder)
        rebeginner.begin(for: "flow", lifetime: .indefinite)

        let superseded = try #require(recorder.records.first { record in
            (record.event as? SpanEnded)?.exit == .superseded
        })
        #expect(superseded.tags == [key: "pay_1"])
        #expect(superseded.scopes == original.scopes.map(\.id))
    }

    @Test func recordsExposeTheirSpanID() throws {
        let log = Log<AppLogs>(recorder: recorder)
        log.measure("save") {}
        log.info("not a span")

        let records = recorder.records
        let began = try #require(records[0].event as? SpanBegan)
        #expect(records[0].spanID == began.spanID)
        #expect(records[1].spanID == began.spanID)
        #expect(records[2].spanID == nil)
    }

    @Test func spanEventsRoundTripThroughCodable() throws {
        let span = SpanID()
        let ended = SpanEnded(
            spanID: span,
            name: "save",
            duration: .milliseconds(12),
            exit: .failure("card declined"),
        )
        let data = try JSONEncoder().encode(ended)
        let decoded = try JSONDecoder().decode(SpanEnded.self, from: data)
        #expect(decoded.spanID == span)
        #expect(decoded.duration == .milliseconds(12))
        #expect(decoded.exit == .failure("card declined"))

        let began = SpanBegan(
            spanID: span,
            name: "save",
            lifetime: .bounded(budget: .seconds(30)),
            relaunchPolicy: .survivesRelaunch,
        )
        let beganData = try JSONEncoder().encode(began)
        let decodedBegan = try JSONDecoder().decode(SpanBegan.self, from: beganData)
        #expect(decodedBegan.lifetime == .bounded(budget: .seconds(30)))
        #expect(decodedBegan.relaunchPolicy == .survivesRelaunch)
    }

    @Test func endedMessagesDescribeTheExit() {
        let span = SpanID()
        let failed = SpanEnded(
            spanID: span,
            name: "save",
            duration: .seconds(2),
            exit: .failure("card declined"),
        )
        #expect(failed.message.contains("save failed: card declined"))
        #expect(failed.message.contains("("))

        let orphaned = SpanEnded(spanID: span, name: "save", duration: nil, exit: .orphaned)
        #expect(orphaned.message == "◀ save orphaned")
    }
}
