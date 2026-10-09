@testable import PeriscopeMacros
import SwiftParser
import SwiftSyntax
import Testing

struct SyntaxSupportTests {
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
