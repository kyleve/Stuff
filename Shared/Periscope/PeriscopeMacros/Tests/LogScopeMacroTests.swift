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

@Test
func scopeRejectsInvalidIdentifiersCasesAndSpanNames() {
    assertMacroExpansion(
        "@LogScope(\"\") enum Scope {}",
        expandedSource: """
        enum Scope {}

        extension Scope: LogScopeDefinition {
        }
        """,
        diagnostics: [
            DiagnosticSpec(
                message: "@LogScope requires a nonempty string-literal scope ID",
                line: 1,
                column: 1,
            ),
        ],
        macros: ["LogScope": LogScopeMacro.self],
    )

    assertMacroExpansion(
        """
        @LogScope("Scope")
        enum Scope {
            case invalid
        }
        """,
        expandedSource: """
        enum Scope {
            case invalid
        }

        extension Scope: LogScopeDefinition {
        }
        """,
        diagnostics: [
            DiagnosticSpec(
                message: "an @LogScope enum cannot declare cases",
                line: 1,
                column: 1,
            ),
        ],
        macros: ["LogScope": LogScopeMacro.self],
    )

    assertMacroExpansion(
        """
        @LogScope("Scope")
        enum Scope {
            struct SpanName {}
        }
        """,
        expandedSource: """
        enum Scope {
            struct SpanName {}
        }

        extension Scope: LogScopeDefinition {
        }
        """,
        diagnostics: [
            DiagnosticSpec(
                message: "SpanName must be a Hashable and Sendable enum",
                line: 3,
                column: 5,
            ),
        ],
        macros: ["LogScope": LogScopeMacro.self],
    )
}
