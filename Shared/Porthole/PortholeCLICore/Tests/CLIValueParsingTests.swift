import Foundation
@testable import PortholeCLICore
import PortholeCore
import Testing

struct CLIValueParsingTests {
    @Test func parsesConnectorSlashMember() throws {
        let ref = try CLIValueParsing.parseRef("where/year-report")
        #expect(ref == ParsedRef(connector: "where", member: "year-report"))
        #expect(ref.actionRef == PortholeActionRef(connector: "where", action: "year-report"))
        #expect(ref.dataSourceRef == PortholeDataSourceRef(
            connector: "where",
            source: "year-report",
        ))
    }

    @Test func rejectsMalformedRefs() {
        #expect(throws: CLIParsingError.self) { try CLIValueParsing.parseRef("noslash") }
        #expect(throws: CLIParsingError.self) { try CLIValueParsing.parseRef("a/b/c") }
        #expect(throws: CLIParsingError.self) { try CLIValueParsing.parseRef("/b") }
        #expect(throws: CLIParsingError.self) { try CLIValueParsing.parseRef("a/") }
    }

    @Test func parsesScalarsWithTypeInference() {
        #expect(CLIValueParsing.parseScalar("true") == .bool(true))
        #expect(CLIValueParsing.parseScalar("false") == .bool(false))
        #expect(CLIValueParsing.parseScalar("42") == .int(42))
        #expect(CLIValueParsing.parseScalar("-7") == .int(-7))
        #expect(CLIValueParsing.parseScalar("1.5") == .double(1.5))
        #expect(CLIValueParsing.parseScalar("hello") == .string("hello"))
        // A bare integer-looking string stays int; a version-like token is a string.
        #expect(CLIValueParsing.parseScalar("1.2.3") == .string("1.2.3"))
    }

    @Test func parsesKeyValueParameters() throws {
        let (key, value) = try CLIValueParsing.parseParameter("year=2026")
        #expect(key == "year")
        #expect(value == .int(2026))
        // Values may contain '='.
        let (k2, v2) = try CLIValueParsing.parseParameter("note=a=b")
        #expect(k2 == "note")
        #expect(v2 == .string("a=b"))
    }

    @Test func rejectsMalformedParameters() {
        #expect(throws: CLIParsingError.self) { try CLIValueParsing.parseParameter("noequals") }
        #expect(throws: CLIParsingError.self) { try CLIValueParsing.parseParameter("=value") }
    }

    @Test func buildsParametersMergingJSONAndParams() throws {
        let value = try CLIValueParsing.buildParameters(
            json: #"{"a": 1, "b": "x"}"#,
            params: ["b=override", "c=true"],
        )
        #expect(value["a"]?.intValue == 1)
        #expect(value["b"]?.stringValue == "override")
        #expect(value["c"]?.boolValue == true)
    }

    @Test func buildParametersRejectsNonObjectJSON() {
        #expect(throws: CLIParsingError.self) {
            _ = try CLIValueParsing.buildParameters(json: "[1,2,3]", params: [])
        }
    }
}
