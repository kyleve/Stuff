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
        #expect(ended.name == "save")
        #expect(ended.duration >= .zero)
        #expect(records.allSatisfy { $0.scopes == log.scopes.map(\.id) })
    }

    @Test func measureEmitsTheEndEvenWhenTheBodyThrows() throws {
        let log = Log<AppLogs>(recorder: recorder)

        #expect(throws: MeasureError.self) {
            try log.measure("failing") { throw MeasureError() }
        }

        #expect(recorder.records.count == 2)
        #expect(recorder.records.last?.event is SpanEnded)
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
    }

    @Test func typedSpanTokensResolveAgainstTheEventType() throws {
        let log = Log<DatabaseLogs>(recorder: recorder)

        log.measure(.saveEvent) {}

        let began = try #require(recorder.records.first?.event as? SpanBegan)
        #expect(began.name == "saveEvent")
    }

    @Test func beginAndEndPairAcrossRebuiltLoggers() throws {
        let first = Log<AppLogs>(recorder: recorder)(for: "payment-flow")
        first.begin(for: "pay_1")

        // A logger rebuilt from the same path pairs with the open span.
        let second = Log<AppLogs>(recorder: recorder)(for: "payment-flow")
        second.end(for: "pay_1")

        let records = recorder.records
        #expect(records.count == 2)
        let began = try #require(records.first?.event as? SpanBegan)
        let ended = try #require(records.last?.event as? SpanEnded)
        #expect(began.spanID == ended.spanID)
        #expect(ended.name == "pay_1")
        #expect(ended.duration >= .zero)
    }

    @Test func endingWithoutABeginWarnsInsteadOfEmitting() {
        let log = Log<AppLogs>(recorder: recorder)

        log.end(for: "never-began")

        let records = recorder.records
        #expect(records.count == 1)
        #expect(records.first?.level == .warning)
        #expect(records.first?.message.contains("without a matching begin") == true)
    }

    @Test func doubleBeginWarnsAndKeepsTheOriginalSpanOpen() throws {
        let log = Log<AppLogs>(recorder: recorder)

        log.begin(for: "pay_1")
        log.begin(for: "pay_1")
        log.end(for: "pay_1")

        let records = recorder.records
        #expect(records.count == 3)
        #expect(records[1].level == .warning)
        let began = try #require(records[0].event as? SpanBegan)
        let ended = try #require(records[2].event as? SpanEnded)
        #expect(began.spanID == ended.spanID)
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
        let ended = SpanEnded(spanID: span, name: "save", duration: .milliseconds(12))
        let data = try JSONEncoder().encode(ended)
        let decoded = try JSONDecoder().decode(SpanEnded.self, from: data)
        #expect(decoded.spanID == span)
        #expect(decoded.duration == .milliseconds(12))
    }
}
