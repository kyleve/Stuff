import Foundation
import PeriscopeCore
import Testing

struct LogExportableTests {
    @Test func exportOverrideCannotPromoteRestrictedFieldsToBaseline() throws {
        let event = LogExportTestLog.Restricted(count: .restricted(.count, 7))
        #expect(try event
            .exportedValue(using: .init(mode: .baseline, enabledControls: [])) == .object([:]))
        #expect(try event
            .exportedValue(using: .init(mode: .diagnostic, enabledControls: [])) ==
            .object(["count": .int(7)]))
    }

    @Test func deniedValuesAreNotEncoded() throws {
        let field = LogExportField(
            .init("invalid"),
            value: JSONValue.double(.nan),
            requirements: .never,
        )
        let policy = LogExportPolicy(
            mode: .diagnostic,
            enabledControls: [.personalData, .customerDiagnostics],
        )
        #expect(try field.exportedValue(using: policy) == nil)
        #expect(try LogExportField.object([field], using: policy) == .object([:]))
    }

    @Test func approvedEncodingFailurePropagates() {
        let field = LogExportField(
            .init("invalid"),
            value: JSONValue.double(.nan),
            requirements: .diagnostic(requiring: []),
        )
        #expect(throws: EncodingError.self) {
            try field.exportedValue(using: .init(mode: .diagnostic, enabledControls: []))
        }
    }

    @Test func macroAndContainersPreserveNestedRestrictions() throws {
        let child = LogExportTestLog.Child(
            secret: .restricted(.arbitraryText, .double(.nan)),
            detail: .restricted(.arbitraryText, "custom"),
            count: .shared(.count, 3),
        )
        let parent = LogExportTestLog.Parent(children: .restricted(
            .domainValue,
            ["items": [child, nil]],
        ))
        let denied = LogExportPolicy(mode: .diagnostic, enabledControls: [.customerDiagnostics])
        #expect(try parent.exportedValue(using: denied) == .object([:]))
        let partial = LogExportPolicy(mode: .diagnostic, enabledControls: [.location])
        #expect(try parent.exportedValue(using: partial) == .object([
            "children": .object(["items": .array([.object(["count": .int(3)]), .null])]),
        ]))
        let complete = LogExportPolicy(
            mode: .diagnostic,
            enabledControls: [.location, .customerDiagnostics],
        )
        #expect(try parent.exportedValue(using: complete) == .object([
            "children": .object(["items": .array([
                .object(["count": .int(3), "detail": .string("custom")]),
                .null,
            ])]),
        ]))
    }

    @Test func localPayloadRetainsNeverExportedData() throws {
        let child = LogExportTestLog.Child(
            secret: .restricted(.arbitraryText, .string("local secret")),
            detail: .restricted(.arbitraryText, "custom"),
            count: .shared(.count, 3),
        )
        let data = try JSONEncoder().encode(child)
        let decoded = try JSONDecoder().decode(LogExportTestLog.Child.self, from: data)
        #expect(decoded.secret == .string("local secret"))
        #expect(try decoded
            .exportedValue(using: .init(mode: .baseline, enabledControls: [])) ==
            .object(["count": .int(3)]))
    }
}
