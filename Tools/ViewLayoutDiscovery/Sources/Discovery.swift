import Foundation
import SwiftParser
import SwiftSyntax

/// Syntax inventory only. The compiler, not this visitor, determines layouts.
struct ViewCandidate: Codable, Equatable {
    let name: String
    let line: Int
    let condition: String
    let generic: Bool
    let kind: String
    let bases: [String]
}

final class ViewDiscovery: SyntaxVisitor {
    private var scopes: [String] = []
    private var genericScopes: [Bool] = []
    private var conditions: [String] = []
    private let locations: SourceLocationConverter
    private(set) var candidates: [ViewCandidate] = []

    init(tree: SourceFileSyntax, path: String) {
        locations = SourceLocationConverter(fileName: path, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    private func enter(
        _ name: String,
        generic: Bool,
        inheritance: InheritanceClauseSyntax?,
        node: some SyntaxProtocol,
        kind: String,
    ) {
        scopes.append(name)
        genericScopes.append(generic)
        let bases = inheritance?.inheritedTypes
            .map { $0.type.trimmedDescription.split(separator: ".").last.map(String.init) ?? "" } ??
            []
        do {
            candidates.append(ViewCandidate(
                name: scopes.joined(separator: "."),
                line: locations.location(for: node.positionAfterSkippingLeadingTrivia).line,
                condition: conditions.joined(separator: " && "),
                generic: genericScopes.contains(true),
                kind: kind,
                bases: bases,
            ))
        }
    }

    private func leave() {
        scopes.removeLast()
        genericScopes.removeLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(
            node.name.text,
            generic: node.genericParameterClause != nil,
            inheritance: node.inheritanceClause,
            node: node,
            kind: "struct",
        )
        return .visitChildren
    }

    override func visitPost(_: StructDeclSyntax) {
        leave()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(
            node.name.text,
            generic: node.genericParameterClause != nil,
            inheritance: node.inheritanceClause,
            node: node,
            kind: "class",
        )
        return .visitChildren
    }

    override func visitPost(_: ClassDeclSyntax) {
        leave()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(
            node.name.text,
            generic: node.genericParameterClause != nil,
            inheritance: node.inheritanceClause,
            node: node,
            kind: "enum",
        )
        return .visitChildren
    }

    override func visitPost(_: EnumDeclSyntax) {
        leave()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(
            node.extendedType.trimmedDescription,
            generic: node.genericWhereClause != nil,
            inheritance: node.inheritanceClause,
            node: node,
            kind: "extension",
        )
        return .visitChildren
    }

    override func visitPost(_: ExtensionDeclSyntax) {
        leave()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(
            node.name.text,
            generic: true,
            inheritance: node.inheritanceClause,
            node: node,
            kind: "protocol",
        )
        return .visitChildren
    }

    override func visitPost(_: ProtocolDeclSyntax) {
        leave()
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let spelling = node.initializer.value.trimmedDescription
        let base = spelling.split(separator: "<").first?.split(separator: ".").last
            .map(String.init) ?? spelling
        candidates.append(ViewCandidate(
            name: (scopes + [node.name.text]).joined(separator: "."),
            line: locations.location(for: node.positionAfterSkippingLeadingTrivia).line,
            condition: conditions.joined(separator: " && "),
            generic: node.genericParameterClause != nil || genericScopes.contains(true),
            kind: "typealias",
            bases: [base],
        ))
        return .skipChildren
    }

    override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
        var preceding: [String] = []
        for clause in node.clauses {
            var terms = preceding.map { "!(\($0))" }
            if let condition = clause.condition?.trimmedDescription {
                terms.append("(\(condition))")
                preceding.append(condition)
            }
            conditions.append(terms.joined(separator: " && "))
            if let elements = clause.elements { walk(elements) }
            conditions.removeLast()
        }
        return .skipChildren
    }
}

func discoverViews(source: String, path: String) throws -> [ViewCandidate] {
    let tree = Parser.parse(source: source)
    guard !tree.hasError else { throw DiscoveryError.invalidSyntax(path) }
    let visitor = ViewDiscovery(tree: tree, path: path)
    visitor.walk(tree)
    return visitor.candidates
}

enum DiscoveryError: Error {
    case invalidSyntax(String)
}
