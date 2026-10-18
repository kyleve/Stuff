import Foundation
import SwiftParser
import SwiftSyntax

/// Syntactic evidence supplements the compiler index; it never resolves a symbol by name.
struct SourceFacts: Codable, Equatable {
    var captures: [String]
    var risks: [String]
    var declarations: [String]
    var shape: [String]

    static func read(_ source: String) -> Self {
        let tree = Parser.parse(source: source)
        let visitor = FactsVisitor(viewMode: .sourceAccurate)
        visitor.walk(tree)
        var risks = visitor.risks
        if tree.hasError { risks.insert("syntax-errors") }
        return Self(
            captures: visitor.captures.sorted(),
            risks: risks.sorted(),
            declarations: visitor.declarations.sorted(),
            shape: visitor.shape.sorted(),
        )
    }
}

private final class FactsVisitor: SyntaxVisitor {
    var captures: Set<String> = []
    var risks: Set<String> = []
    var declarations: Set<String> = []
    var shape: Set<String> = []

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if node.calledExpression.trimmedDescription == "assertSnapshots",
           let argument = node.arguments.first(where: { $0.label?.text == "of" }),
           let expression = argument.expression.as(MemberAccessExprSyntax.self),
           expression.declName.baseName.text == "self",
           let base = expression.base
        {
            captures.insert(base.trimmedDescription)
        }
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        declarations.insert(node.name.text)
        shape.insert(node.with(\.memberBlock.members, []).trimmedDescription)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        declarations.insert(node.name.text)
        shape.insert(node.with(\.memberBlock.members, []).trimmedDescription)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        declarations.insert(node.name.text)
        shape.insert(node.with(\.memberBlock.members, []).trimmedDescription)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        shape.insert(node.with(\.memberBlock.members, []).trimmedDescription)
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        shape.insert(node.with(\.memberBlock.members, []).trimmedDescription)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        shape.insert(node.with(\.body, nil).trimmedDescription)
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        shape.insert(node.with(\.body, nil).trimmedDescription)
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        shape.insert(node.with(\.accessorBlock, nil).trimmedDescription)
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let bindings = PatternBindingListSyntax(node.bindings.map {
            $0.with(\.initializer, nil).with(\.accessorBlock, nil)
        })
        shape.insert(node.with(\.bindings, bindings).trimmedDescription)
        return .visitChildren
    }

    override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
        // Metadata is pinned to Debug. A DEBUG guard has the same branch in both builds.
        // Other compiler conditions need a wider configuration model before narrowing.
        if node.clauses
            .contains(where: { $0.condition.map { $0.trimmedDescription != "DEBUG" } ?? false })
        {
            risks.insert("conditional-compilation")
        }
        return .visitChildren
    }

    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        if !["Preview", "filePath", "fileID", "line", "column", "function"]
            .contains(node.macroName.text)
        {
            risks.insert("macro-expansion")
        }
        return .visitChildren
    }

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        if node.attributeName.trimmedDescription == "Observable" {
            risks.insert("macro-generated-storage")
        }
        return .visitChildren
    }

    override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
        let dynamicNames: Set = [
            "objc",
            "dynamic",
            "dynamicMemberLookup",
            "NSClassFromString",
            "NSSelectorFromString",
            "Selector",
            "NotificationCenter",
            "Mirror",
            "unsafeBitCast",
            "perform",
        ]
        if dynamicNames.contains(token.text) { risks.insert("dynamic-behavior") }
        if ["EnvironmentKey", "EnvironmentValues", "UITraitBridgedEnvironmentKey"]
            .contains(token.text)
        {
            risks.insert("environment-infrastructure")
        }
        return .visitChildren
    }
}
