import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

struct PeriscopeMacroDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    init(_ id: String, _ message: String, severity: DiagnosticSeverity = .error) {
        self.message = message
        diagnosticID = MessageID(domain: "PeriscopeMacros", id: id)
        self.severity = severity
    }
}

extension MacroExpansionContext {
    func diagnose(_ node: some SyntaxProtocol, id: String, message: String) {
        diagnose(Diagnostic(node: Syntax(node), message: PeriscopeMacroDiagnostic(id, message)))
    }
}
