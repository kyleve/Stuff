import Foundation
import PeriscopeCore
import Testing

struct LogExportMetadataTests {
    @Test(arguments: [false, true])
    func categorySchemaSurvivesPersistenceAndRejectsUnknownValues(allowsNil: Bool) throws {
        let schema = LogExportSchema.category(
            allowedValues: ["ready", "failed"],
            allowsNil: allowsNil,
        )
        let metadata = LogExportMetadata(payload: schema)
        let restored = try JSONDecoder().decode(
            LogExportMetadata.self,
            from: JSONEncoder().encode(metadata),
        )
        #expect(restored == metadata)
        let policy = LogExportPolicy(mode: .baseline, enabledControls: [])
        #expect(try restored.filtered(.string("ready"), using: policy) == .string("ready"))
        for invalid: JSONValue in [
            .string("private@example.test"),
            .object(["email": .string("private")]),
            .int(1),
        ] {
            #expect(throws: LogExportSchema.Failure.shapeMismatch) { try restored.filtered(
                invalid,
                using: policy,
            ) }
        }
        if allowsNil {
            #expect(try restored.filtered(.null, using: policy) == .null)
        } else {
            #expect(throws: LogExportSchema.Failure.shapeMismatch) { try restored.filtered(
                .null,
                using: policy,
            ) }
        }
    }

    @Test func structuredErrorsMatchLiveProjectionIncludingNilFields() throws {
        let error = LogError(capturing: NSError(domain: "private-domain", code: 42))
        let raw = try JSONValue.encoding(error)
        let metadata = LogExportMetadata(payload: error.exportDescription.schema)
        let policies: [LogExportPolicy] = [
            .init(mode: .diagnostic, enabledControls: []),
            .init(mode: .diagnostic, enabledControls: [.personalData]),
        ]
        for policy in policies {
            #expect(try metadata.filtered(raw, using: policy) == error.exportedValue(using: policy))
        }
    }

    @Test(arguments: [
        LogExportPolicy(mode: .baseline, enabledControls: []),
        .init(mode: .diagnostic, enabledControls: []),
        .init(mode: .diagnostic, enabledControls: [.location]),
        .init(mode: .diagnostic, enabledControls: [.location, .customerDiagnostics]),
    ])
    func persistedNestedPoliciesMatchLiveProjection(policy: LogExportPolicy) throws {
        let child = LogExportTestLog.Child(
            secret: .restricted(.arbitraryText, .string("never exported")),
            detail: .restricted(.arbitraryText, "custom detail"),
            count: .shared(.count, 3),
        )
        let event = LogExportTestLog.Parent(children: .restricted(
            .domainValue,
            ["items": [child, nil]],
        ))
        let metadata = LogExportMetadata(payload: event.exportDescription.schema)
        let data = try JSONEncoder().encode(metadata)
        #expect(String(decoding: data, as: UTF8.self).contains("never exported") == false)
        let restored = try JSONDecoder().decode(LogExportMetadata.self, from: data)
        #expect(restored == metadata)
        let raw = try JSONValue.encoding(event)
        #expect(try restored.filtered(raw, using: policy) == event.exportedValue(using: policy))
    }

    @Test func unsupportedVersionsFailClosed() throws {
        let metadata = try JSONDecoder().decode(LogExportMetadata.self, from: Data(
            #"{"version":99,"payload":{"type":"value"}}"#.utf8,
        ))
        #expect(throws: LogExportSchema.Failure.unsupportedVersion(99)) {
            try metadata.filtered(
                .string("secret"),
                using: .init(mode: .diagnostic, enabledControls: []),
            )
        }
    }

    @Test func unknownFieldsAreNotApprovedAndArrayShapeMustMatch() throws {
        let policy = LogExportPolicy(mode: .baseline, enabledControls: [])
        let schema = LogExportSchema.object(["count": .value])
        #expect(try schema.filtered(
            .object(["count": .int(1), "unknown": .string("private")]),
            using: policy,
        ) == .object(["count": .int(1)]))
        #expect(throws: LogExportSchema.Failure.shapeMismatch) {
            try LogExportSchema.array([.value]).filtered(.array([.int(1), .int(2)]), using: policy)
        }
    }
}
