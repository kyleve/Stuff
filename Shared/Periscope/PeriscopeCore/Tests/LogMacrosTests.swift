import Foundation
import PeriscopeCore
import Testing

@LogScope("macro-fixture")
private enum MacroFixtureLog {
    @LogEvent("inferred", message: "Inferred")
    struct Inferred {
        @LogField(exposure: .shareable, kind: .count)
        var sampleCount: Int

        @LogField(exposure: .shareable, kind: .count)
        var http2Status: Int?

        @LogField(exposure: .restricted, kind: .identifier)
        var sampleID: String?

        @LogField(exposure: .shareable, kind: .boolean)
        var `default`: Bool
    }

    @LogEvent("renamed", message: "Renamed")
    struct Renamed {
        @LogField("sample_count", exposure: .shareable, kind: .count)
        var numberOfSamples: Int

        @LogField("http2_status", exposure: .shareable, kind: .count)
        var status: Int?

        @LogField("sample_id", exposure: .restricted, kind: .identifier)
        var identifier: String?

        @LogField("default", exposure: .shareable, kind: .boolean)
        var isDefault: Bool
    }

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

@LogScope("literal\u{2D}fixture")
private enum LiteralFixtureLog {
    @LogEvent("esc\u{61}ped", message: "First\n\"Second\"\t\\path 🚀")
    struct Escaped {
        @LogField("stable\u{5F}key", exposure: .shareable, kind: .count)
        var count: Int
    }

    @LogEvent("raw", message: #"Raw \n text"#)
    struct Raw {}

    @LogEvent("multiline", message: """
    First
    Second
    """)
    struct Multiline {}
}

struct LogMacrosTests {
    @Test(arguments: [nil, 7] as [Int?])
    func inferredKeysMatchExplicitKeysAfterRenaming(optionalCount: Int?) throws {
        let recorder = RecordingRecorder()
        let log = Log<MacroFixtureLog>(recorder: recorder)
        log.inferred(
            sampleCount: .shared(.count, 3),
            http2Status: .shared(.count, optionalCount),
            sampleID: .restricted(.identifier, nil),
            default: .shared(.boolean, true),
        )
        let inferred = try #require(recorder.records.first?.event as? MacroFixtureLog.Inferred)
        let renamed = MacroFixtureLog.Renamed(
            numberOfSamples: .shared(.count, 3),
            status: .shared(.count, optionalCount),
            identifier: .restricted(.identifier, nil),
            isDefault: .shared(.boolean, true),
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(inferred)
        #expect(try data == (encoder.encode(renamed)))
        let decoded = try JSONDecoder().decode(MacroFixtureLog.Inferred.self, from: data)
        #expect(decoded.sampleCount == 3)
        #expect(decoded.http2Status == optionalCount)
        #expect(decoded.sampleID == nil)
        #expect(decoded.default == true)
        var expected: [ClassifiedLogField] = [
            .shareable(key: LogFieldKey("sample_count"), kind: .count, value: .int(3)),
        ]
        if let optionalCount {
            expected.append(.shareable(
                key: LogFieldKey("http2_status"),
                kind: .count,
                value: .int(optionalCount),
            ))
        }
        expected.append(.restricted(key: LogFieldKey("sample_id"), kind: .identifier))
        expected.append(.shareable(key: LogFieldKey("default"), kind: .boolean, value: .bool(true)))
        #expect(inferred.classifiedFields == expected)
        #expect(renamed.classifiedFields == expected)
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == .object([
            "sample_count": .int(3),
            "http2_status": optionalCount.map(JSONValue.int) ?? .null,
            "sample_id": .null,
            "default": .bool(true),
        ]))
    }

    @Test func generatedLiteralValuesPreserveDecodedText() throws {
        let recorder = RecordingRecorder()
        let log = Log<LiteralFixtureLog>(recorder: recorder)
        log.escaped(count: .shared(.count, 3))
        let event = try #require(recorder.records.first?.event as? LiteralFixtureLog.Escaped)

        #expect(LiteralFixtureLog.scopeName == "literal-fixture")
        #expect(LiteralFixtureLog.Escaped.eventName == "literal-fixture.escaped")
        #expect(event.message == "First\n\"Second\"\t\\path 🚀")
        #expect(event.classifiedFields == [
            .shareable(key: LogFieldKey("stable_key"), kind: .count, value: .int(3)),
        ])
        let payload = try JSONDecoder().decode(
            [String: Int].self,
            from: JSONEncoder().encode(event),
        )
        #expect(payload == ["stable_key": 3])
        #expect(LiteralFixtureLog.Raw().message == #"Raw \n text"#)
        #expect(LiteralFixtureLog.Multiline().message == "First\nSecond")
    }

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
