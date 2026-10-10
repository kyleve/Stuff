import SwiftSyntax

/// Field validation runs once per expansion role; only the event role emits diagnostics.
struct FieldDiagnostic {
    let node: Syntax
    let id: String
    let message: String
}

struct FieldDiagnostics {
    var values: [FieldDiagnostic] = []

    mutating func diagnose(_ node: some SyntaxProtocol, id: String, message: String) {
        values.append(FieldDiagnostic(node: Syntax(node), id: id, message: message))
    }
}
