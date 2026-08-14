@testable import PeriscopeMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@Test
func scopeRequiresEnum() {
    assertMacroExpansion(
        "@LogScope(\"scope\") struct Scope {}",
        expandedSource: "struct Scope {}",
        diagnostics: [
            DiagnosticSpec(message: "@LogScope requires an enum namespace", line: 1, column: 1),
        ],
        macros: ["LogScope": LogScopeMacro.self],
    )
}

@Test
func leadingAcronymBecomesOneWord() {
    #expect(lowerCamelCase("URLLoadFailed") == "urlLoadFailed")
    #expect(lowerCamelCase("GPS") == "gps")
    #expect(lowerCamelCase("Loaded") == "loaded")
}
