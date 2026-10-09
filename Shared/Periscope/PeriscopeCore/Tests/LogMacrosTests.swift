import PeriscopeCore
import Testing

@LogScope("macro-fixture")
private enum MacroFixtureLog {
    @LogEvent("counted", message: "Counted")
    struct Counted {
        @LogField("count", exposure: .shareable, kind: .count)
        var count: Int
    }

    @LogEvent("required-fields", message: "Required fields")
    struct RequiredFields {
        @LogField("fields", exposure: .shareable, kind: .count)
        var fields: Int
    }

    @LogEvent("optional-fields", message: "Optional fields")
    struct OptionalFields {
        @LogField("fields", exposure: .shareable, kind: .count)
        var fields: Int?

        @LogField("value", exposure: .shareable, kind: .boolean)
        var value: Bool?
    }
}

struct LogMacrosTests {
    @Test func generatedProjectionDoesNotShadowRequiredFields() throws {
        let recorder = RecordingRecorder()
        let log = Log<MacroFixtureLog>(recorder: recorder)
        log.requiredFields(fields: .shared(.count, 7))

        let event = try #require(recorder.records.first?.event as? MacroFixtureLog.RequiredFields)
        #expect(event.fields == 7)
        #expect(event.classifiedFields == [
            .shareable(key: LogFieldKey("fields"), kind: .count, value: .int(7)),
        ])
    }

    @Test(arguments: [nil, 7] as [Int?])
    func generatedProjectionDoesNotShadowOptionalFields(fields: Int?) throws {
        let recorder = RecordingRecorder()
        let log = Log<MacroFixtureLog>(recorder: recorder)
        log.optionalFields(fields: .shared(.count, fields), value: .shared(.boolean, true))

        let event = try #require(recorder.records.first?.event as? MacroFixtureLog.OptionalFields)
        var expected: [ClassifiedLogField] = []
        if let fields {
            expected.append(.shareable(
                key: LogFieldKey("fields"),
                kind: .count,
                value: .int(fields),
            ))
        }
        expected.append(.shareable(key: LogFieldKey("value"), kind: .boolean, value: .bool(true)))
        #expect(event.fields == fields)
        #expect(event.classifiedFields == expected)
    }

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
