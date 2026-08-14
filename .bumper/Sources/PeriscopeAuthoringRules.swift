import BumperBowlingCore
import SwiftSyntax

let periscopeAuthoringRules = RuleSet {
    eventMacroRule
    scopeMacroRule
    manualEventConformanceRule
    manualScopeConformanceRule
    legacyRemoteAPIRule
    logFieldPlacementRule
}

private let eventMacroRule = Rules.files(
    "periscope.structured_events_use_macro",
    severity: .error,
    summary: "Every event nested in a Periscope scope uses @LogEvent.",
) { file in
    SyntaxQuery<StructDeclSyntax>()
        .filter { match in
            guard let parent = nearestNominalParent(of: match.node)?.as(EnumDeclSyntax.self) else {
                return false
            }
            return hasAttribute("LogScope", in: parent.attributes)
                && !hasAttribute("LogEvent", in: match.node.attributes)
        }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "A structured Periscope event does not use @LogEvent.",
                evidence: ViolationEvidence(
                    observed: match.node.name.text,
                    expectation: "a direct @LogEvent struct in its @LogScope namespace",
                ),
            )
        }
}

private let scopeMacroRule = Rules.files(
    "periscope.event_namespaces_use_macro",
    severity: .error,
    summary: "Every namespace containing @LogEvent declarations uses @LogScope.",
) { file in
    SyntaxQuery<EnumDeclSyntax>()
        .filter { match in
            !hasAttribute("LogScope", in: match.node.attributes)
                && match.node.memberBlock.members.contains { member in
                    guard let event = member.decl.as(StructDeclSyntax.self) else { return false }
                    return hasAttribute("LogEvent", in: event.attributes)
                }
        }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "A Periscope event namespace does not use @LogScope.",
                evidence: ViolationEvidence(
                    observed: match.node.name.text,
                    expectation: "an @LogScope namespace enum",
                ),
            )
        }
}

private let manualEventConformanceRule = manualConformanceRule(
    protocolName: "LogEvent",
    id: "periscope.manual_event_conformance",
    summary: "Repository event declarations do not conform to LogEvent manually.",
)

private let manualScopeConformanceRule = manualConformanceRule(
    protocolName: "LogScopeDefinition",
    id: "periscope.manual_scope_conformance",
    summary: "Repository scope declarations do not conform to LogScopeDefinition manually.",
)

private let legacyRemoteIdentifiers: Set<String> = [
    "remoteMessage",
    "remoteFields",
    "RemoteLogField",
    "RemoteLogFieldKey",
    "RemoteLogFieldValue",
    "RemoteLogCategory",
]

private let legacyRemoteAPIRule = Rules.files(
    "periscope.legacy_remote_api",
    severity: .error,
    summary: "Legacy Periscope remote-field APIs stay removed.",
) { file in
    SyntaxQuery<TokenSyntax>()
        .filter { legacyRemoteIdentifiers.contains($0.node.text) }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "Repository code uses a removed Periscope remote API.",
                evidence: ViolationEvidence(
                    observed: match.node.text,
                    expectation: "@LogField classification and classifiedFields",
                ),
            )
        }
}

private let logFieldPlacementRule = Rules.files(
    "periscope.log_field_placement",
    severity: .error,
    summary: "@LogField appears only on properties of direct @LogEvent structs.",
) { file in
    SyntaxQuery<AttributeSyntax>()
        .filter { match in
            guard attributeBaseName(match.node) == "LogField" else { return false }
            guard let event = nearestAncestor(of: match.node, as: StructDeclSyntax.self),
                  hasAttribute("LogEvent", in: event.attributes),
                  nearestNominalParent(of: event)?.is(EnumDeclSyntax.self) == true
            else {
                return true
            }
            return false
        }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "@LogField is outside a direct @LogEvent struct.",
                evidence: ViolationEvidence(
                    observed: match.node.trimmedDescription,
                    expectation: "a stored property in a direct @LogEvent struct",
                ),
            )
        }
}

private func manualConformanceRule(
    protocolName: String,
    id: String,
    summary: String,
) -> SyntaxRule {
    Rules.files(id, severity: .error, summary: summary) { file in
        SyntaxQuery<InheritedTypeSyntax>()
            .filter { match in
                match.node.type.trimmedDescription == protocolName
                    && inheritanceDecl(of: match.node) != nil
            }
            .matches(in: file)
            .map { match in
                match.failure(
                    message: "Repository code conforms to \(protocolName) manually.",
                    evidence: ViolationEvidence(
                        observed: match.node.trimmedDescription,
                        expectation: protocolName == "LogEvent" ? "@LogEvent" : "@LogScope",
                    ),
                )
            }
    }
}

private func inheritanceDecl(of node: InheritedTypeSyntax) -> DeclSyntax? {
    var ancestor = Syntax(node).parent
    while let current = ancestor {
        if current.is(AssociatedTypeDeclSyntax.self)
            || current.is(TypeAliasDeclSyntax.self)
            || current.is(FunctionDeclSyntax.self)
            || current.is(VariableDeclSyntax.self)
        {
            return nil
        }
        if current.is(StructDeclSyntax.self)
            || current.is(EnumDeclSyntax.self)
            || current.is(ClassDeclSyntax.self)
            || current.is(ActorDeclSyntax.self)
            || current.is(ProtocolDeclSyntax.self)
            || current.is(ExtensionDeclSyntax.self)
        {
            return current.as(DeclSyntax.self)
        }
        ancestor = current.parent
    }
    return nil
}

private func hasAttribute(_ name: String, in attributes: AttributeListSyntax) -> Bool {
    attributes.contains { element in
        guard let attribute = element.as(AttributeSyntax.self) else { return false }
        return attributeBaseName(attribute) == name
    }
}

private func attributeBaseName(_ attribute: AttributeSyntax) -> String {
    attribute.attributeName.trimmedDescription.split(separator: ".").last.map(String.init) ?? ""
}

private func nearestNominalParent(of node: some SyntaxProtocol) -> DeclSyntax? {
    var ancestor = Syntax(node).parent
    while let current = ancestor {
        if current.is(StructDeclSyntax.self)
            || current.is(EnumDeclSyntax.self)
            || current.is(ClassDeclSyntax.self)
            || current.is(ActorDeclSyntax.self)
            || current.is(ProtocolDeclSyntax.self)
            || current.is(ExtensionDeclSyntax.self)
        {
            return current.as(DeclSyntax.self)
        }
        ancestor = current.parent
    }
    return nil
}

private func nearestAncestor<Node: SyntaxProtocol>(
    of node: some SyntaxProtocol,
    as _: Node.Type,
) -> Node? {
    var ancestor = Syntax(node).parent
    while let current = ancestor {
        if let match = current.as(Node.self) {
            return match
        }
        ancestor = current.parent
    }
    return nil
}
