@testable import PeriscopeMacros
import SwiftParser
import SwiftSyntax
import Testing

struct SyntaxSupportTests {
    @Test(arguments: [
        "Policy.shareable",
        "LogFieldExposure.shareable",
        "Policy.count",
        "Policy.error",
    ])
    func classificationRequiresAnUnqualifiedCase(source: String) throws {
        #expect(try literalMemberName(from: expression(from: source)) == nil)
        #expect(try literalMemberName(from: expression(from: ".shareable")) == "shareable")
    }

    @Test(arguments: ["LogError", "LogError?", "PeriscopeCore.LogError", "ErrorAlias", "String"])
    func errorRequirementsUseTypeIdentity(type: String) {
        let field = EventField(
            name: "error",
            type: type,
            key: "error",
            exposure: "restricted",
            kind: .errorDetails,
        )
        #expect(field.resolvedExportRequirements
            == ".classified(exposure: .restricted, kind: .errorDetails, valueType: (\(type)).self)")
    }

    @Test(arguments: [
        "sampleCount": "sample_count",
        "sampleID": "sample_id",
        "URLLoadFailed": "url_load_failed",
        "http2Status": "http2_status",
        "URL": "url",
        "aB": "a_b",
        "already_snake": "already_snake",
        "_sample__ID_": "_sample__id_",
        "`default`": "default",
    ])
    func infersASCIIKeys(property: String, expected: String) {
        let arguments = LabeledExprListSyntax([])
        #expect(fieldKey(in: arguments, propertyName: property) == expected)
    }

    @Test(arguments: ["café", "🚀", ""])
    func nonASCIIOrEmptyNamesRequireExplicitKeys(property: String) {
        #expect(fieldKey(in: LabeledExprListSyntax([]), propertyName: property) == nil)
    }

    @Test func explicitKeyOverridesAnyPropertyName() throws {
        let call =
            try #require(
                expression(from: #"LogField("stable_key", exposure: .shareable, kind: .count)"#)
                    .as(FunctionCallExprSyntax.self),
            )
        #expect(fieldKey(in: call.arguments, propertyName: "renamedCount") == "stable_key")
        #expect(fieldKey(in: call.arguments, propertyName: "café") == "stable_key")
    }

    @Test(arguments: EventFieldKind.allCases)
    func semanticKindsHaveExplicitPolicies(kind: EventFieldKind) {
        #expect(kind.policyType.isEmpty == false)
        #expect(kind.isShareable == ["boolean", "count", "limit", "duration", "category", "json"]
            .contains(kind.rawValue))
    }

    @Test func unknownKindsAreNotCoercedToTechnicalState() {
        #expect(EventFieldKind(rawValue: "futureKind") == nil)
    }

    @Test(arguments: [
        #""First\nSecond""#,
        #""Quoted \"value\" and \\path""#,
        #""\t\u{1F680}""#,
        #""\0""#,
        ##"#"Raw \n text"#"##,
        "\"\"\"\n    First\n    Second\n    \"\"\"",
        #""""#,
    ])
    func literalValuesRoundTripThroughGeneratedSource(source: String) throws {
        let expression = try expression(from: source)
        let value = try #require(plainString(from: expression))
        let generated = try self.expression(from: "\"\(escapedStringLiteral(value))\"")
        #expect(plainString(from: generated) == value)
    }

    @Test func escapesDecodeRatherThanPersistAsSourceText() throws {
        #expect(try plainString(from: expression(from: #""First\nSecond""#)) == "First\nSecond")
        #expect(try plainString(from: expression(from: #""Quoted \"value\" and \\path""#))
            == "Quoted \"value\" and \\path")
        #expect(try plainString(from: expression(from: #""\t\u{1F680}""#)) == "\t🚀")
        #expect(try plainString(from: expression(from: ##"#"Raw \n text"#"##)) == #"Raw \n text"#)
    }

    @Test(arguments: [
        #""Value \(value)""#,
        ##"#"Value \#(value)"#"##,
        "someIdentifier",
    ])
    func rejectsInterpolationAndNonliterals(source: String) throws {
        #expect(try plainString(from: expression(from: source)) == nil)
    }

    private func expression(from source: String) throws -> ExprSyntax {
        let parsed = Parser.parse(source: source)
        return try #require(parsed.statements.first?.item.as(ExprSyntax.self))
    }
}
