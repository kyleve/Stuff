// Parse the grouped tests using the SwiftSyntax shipped with the selected Xcode.
import Foundation
import SwiftParser
import SwiftSyntax

private final class SuiteVisitor: SyntaxVisitor {
    var suites: Set<String> = []

    override func visit(_ attribute: AttributeSyntax) -> SyntaxVisitorContinueKind {
        guard ["Test", "Testing.Test"].contains(attribute.attributeName.trimmedDescription)
        else { return .skipChildren }

        // Xcode's case identifier starts with the outer Swift type, even for nested
        // suites and custom display names. Test code can also live in an extension.
        var parent = attribute.parent
        var suite: String?
        var function: FunctionDeclSyntax?
        while let ancestor = parent {
            if let declaration = ancestor.as(FunctionDeclSyntax.self) {
                function = declaration
            } else if let extended = ancestor.as(ExtensionDeclSyntax.self) {
                suite = extended.extendedType.firstToken(viewMode: .sourceAccurate)?.text
            } else if ancestor.isProtocol(DeclGroupSyntax.self),
                      let named = ancestor.asProtocol(NamedDeclSyntax.self)
            {
                suite = named.name.text
            }
            parent = ancestor.parent
        }
        if let suite {
            suites.insert(suite)
        } else if let function {
            // File-scope Swift Testing cases have no suite in the Xcode identifier.
            let labels = function.signature.parameterClause.parameters
                .map { $0.firstName.text + ":" }.joined()
            suites.insert("\(function.name.text)(\(labels))")
        }
        return .skipChildren
    }
}

let files = try JSONDecoder().decode(
    [String: [String]].self,
    from: FileHandle.standardInput.readDataToEndOfFile(),
)
var inventory: [String: [String]] = [:]
for (module, paths) in files {
    let visitor = SuiteVisitor(viewMode: .sourceAccurate)
    for path in paths {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        visitor.walk(Parser.parse(source: source))
    }
    inventory[module] = visitor.suites.sorted()
}

try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(inventory))
