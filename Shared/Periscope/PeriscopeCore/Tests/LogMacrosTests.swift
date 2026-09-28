import PeriscopeCore
import Testing

@LogScope("macro-fixture")
private enum MacroFixtureLog {
    @LogEvent("counted", message: "Counted")
    struct Counted {
        @LogField("count", exposure: .shareable, kind: .count)
        var count: Int
    }
}

struct LogMacrosTests {
    @Test func generatedMethodRecordsTheClassifiedEvent() throws {
        let recorder = RecordingRecorder()
        let log = Log<MacroFixtureLog>(recorder: recorder)

        log.counted(count: .shared(.count, 3))

        let event = try #require(recorder.records.first?.event as? MacroFixtureLog.Counted)
        #expect(event.count == 3)
        #expect(event.classifiedFields == [
            .shareable(key: LogFieldKey("count"), kind: .count, value: .int(3)),
        ])
    }
}
