@testable import PeriscopeMacros
import SwiftSyntax
import Testing

@Test func fieldDiagnosticsPreserveSourceAndOrder() {
    var diagnostics = FieldDiagnostics()
    let node = TokenSyntax.identifier("field")
    diagnostics.diagnose(node, id: "first", message: "First")
    diagnostics.diagnose(node, id: "second", message: "Second")
    #expect(diagnostics.values.map(\.id) == ["first", "second"])
    #expect(diagnostics.values.map(\.message) == ["First", "Second"])
    #expect(diagnostics.values.allSatisfy { $0.node.description == "field" })
}
