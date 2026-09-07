import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct PeriscopePlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        LogEventMacro.self,
        LogScopeMacro.self,
    ]
}
