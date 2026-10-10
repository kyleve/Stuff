import Foundation
import PeriscopeCore
import Testing

struct LogFieldProjectionTests {
    @Test func compilerResolvesAliasesOptionalsAndCustomSeverity() throws {
        let event = ProjectionTestLog.Aliases(
            count: .shared(.count, 3),
            category: .shared(.category, nil),
            json: .shared(.json, nil),
            boolean: .shared(.boolean, true),
        )
        #expect(event.level == ProjectionTestValues.error)
        #expect(event.classifiedFields == [
            .shareable(key: .init("count"), kind: .count, value: .int(3)),
            .shareable(key: .init("boolean"), kind: .boolean, value: .bool(true)),
        ])
        let policy = LogExportPolicy(mode: .baseline, enabledControls: [])
        #expect(try event.exportedValue(using: policy) == .object([
            "count": .int(3),
            "category": .null,
            "json": .null,
            "boolean": .bool(true),
        ]))
        // Compiles the generated proxy in the event's lexical scope.
        let log = Log<ProjectionTestLog>(system: Periscope(configuration: .init(), sinks: []))
        log.aliases(
            count: .shared(.count, 1),
            category: .shared(.category, .ready),
            json: .shared(.json, .null),
            boolean: .shared(.boolean, false),
        )
        log.logField(value: .restricted(.identifier, "sample"))
    }

    @Test func frameworkWrapperNameCannotBeShadowedByAnEvent() {
        let event = ProjectionTestLog.LogField(value: .restricted(.identifier, "sample"))
        #expect(event.value == "sample")
        #expect(event.classifiedFields == [.restricted(key: .init("value"), kind: .identifier)])
    }

    @Test func scalarProjectionsPreserveRepresentations() {
        let key = LogFieldKey("value")
        #expect(LogFieldProjection.limit(4, key: key) == .shareable(
            key: key,
            kind: .limit,
            value: .int(4),
        ))
        #expect(LogFieldProjection.duration(.seconds(2), key: key) == .shareable(
            key: key,
            kind: .duration,
            value: .double(2000),
        ))
        #expect(LogFieldProjection.json(.object(["ok": .bool(true)]), key: key)
            == .shareable(key: key, kind: .json, value: .json(.object(["ok": .bool(true)]))))
        #expect(LogFieldProjection.count(nil, key: key) == nil)
        #expect(LogFieldProjection.category(ProjectionTestValues.Category.ready, key: key)
            == .shareable(key: key, kind: .category, value: .string("ready")))
    }

    @Test func categoryMutationAndDecodeCannotWidenFilteredExports() throws {
        var event = ProjectionTestLog.Open(category: .shared(.category, .init(rawValue: "ready")))
        event.category.rawValue = "private@example.test"
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(ProjectionTestLog.Open.self, from: data)
        let policy = LogExportPolicy(mode: .baseline, enabledControls: [])
        #expect(throws: LogExportSchema.Failure.shapeMismatch) {
            try decoded.exportedValue(using: policy)
        }
        let metadata = LogExportMetadata(payload: decoded.exportDescription.schema)
        #expect(throws: LogExportSchema.Failure.shapeMismatch) {
            try metadata.filtered(JSONValue.encoding(decoded), using: policy)
        }
    }

    @Test func customCategoryEncodingCannotExportExtraData() throws {
        let event = ProjectionTestLog.Object(category: .shared(.category, .init(rawValue: "ready")))
        #expect(event.classifiedFields == [.shareable(
            key: .init("category"),
            kind: .category,
            value: .string("ready"),
        )])
        let raw = try JSONValue.encoding(event)
        let metadata = try JSONDecoder().decode(
            LogExportMetadata.self,
            from: JSONEncoder()
                .encode(LogExportMetadata(payload: event
                        .exportDescription.schema)),
        )
        for mode: LogExportPolicy.Mode in [.baseline, .diagnostic] {
            let policy = LogExportPolicy(mode: mode, enabledControls: [.personalData])
            #expect(throws: LogExportSchema.Failure.shapeMismatch) {
                try event.exportedValue(using: policy)
            }
            #expect(throws: LogExportSchema.Failure.shapeMismatch) { try metadata.filtered(
                raw,
                using: policy,
            ) }
        }
    }
}
