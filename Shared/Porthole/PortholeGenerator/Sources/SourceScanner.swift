import Foundation
import SwiftParser
import SwiftSyntax

/// Inventories source declarations without evaluating code or assuming that syntax implies
/// callability.
struct SourceScanner {
    func scan(
        moduleName: String,
        files: [SourceFile],
        validateCollisions: Bool = true,
        build: SourceModule.BuildMetadata = .init(configuration: "unknown", toolchain: "unknown"),
    ) throws -> SourceModule {
        var declarations: [SourceDeclaration] = []
        for file in files.sorted(by: { $0.path < $1.path }) {
            let tree = Parser.parse(source: file.content)
            guard !tree.hasError else { throw GeneratorError.invalidSource(path: file.path) }
            let visitor = DeclarationVisitor(moduleName: moduleName, file: file, tree: tree)
            visitor.walk(tree)
            declarations.append(contentsOf: visitor.declarations)
        }
        let possibleCollisions = declarations.filter {
            [.type, .function, .property, .typeAlias].contains($0.kind) && $0.conditions.isEmpty
        }
        for (name, candidates) in Dictionary(grouping: possibleCollisions, by: collisionKey) {
            let paths = Set(candidates.map(\.file))
            if validateCollisions, paths.count > 1, candidates.contains(where: { [
                "private",
                "fileprivate",
            ].contains($0.access) }) {
                throw GeneratorError.collision(name: name, files: paths.sorted())
            }
        }
        return SourceModule(
            name: moduleName,
            files: files,
            declarations: declarations,
            build: build,
        )
    }

    private func collisionKey(_ declaration: SourceDeclaration) -> String {
        let qualified = declaration.owner.map { "\($0).\(declaration.name)" } ?? declaration.name
        if declaration.kind == .function {
            return qualified + "(" + declaration.parameters.map { "\($0.label):\($0.type)" }
                .joined(separator: ",")
                + ")->" + (declaration.resultType ?? "Void")
        }
        return "\(declaration.kind.rawValue):\(qualified)"
    }
}

private final class DeclarationVisitor: SyntaxVisitor {
    private struct Owner {
        let name: String
        let isActor: Bool
        let isMainActor: Bool
        let isReferenceType: Bool
        let unsupportedReason: String?
    }

    let moduleName: String
    let file: SourceFile
    let locations: SourceLocationConverter
    private var owners: [Owner] = []
    private var declarationOccurrences: [String: Int] = [:]
    private(set) var declarations: [SourceDeclaration] = []

    init(moduleName: String, file: SourceFile, tree: SourceFileSyntax) {
        self.moduleName = moduleName
        self.file = file
        locations = SourceLocationConverter(fileName: file.path, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        enterType(
            node,
            name: node.name.text,
            modifiers: node.modifiers,
            attributes: node.attributes,
            generic: node.genericParameterClause != nil,
            isActor: false,
            isReference: false,
            conformances: node.inheritanceClause?.inheritedTypes
                .map(\.type.trimmedDescription) ?? [],
        )
    }

    override func visitPost(_: StructDeclSyntax) {
        owners.removeLast()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        enterType(
            node,
            name: node.name.text,
            modifiers: node.modifiers,
            attributes: node.attributes,
            generic: node.genericParameterClause != nil,
            isActor: false,
            isReference: true,
            conformances: node.inheritanceClause?.inheritedTypes
                .map(\.type.trimmedDescription) ?? [],
        )
    }

    override func visitPost(_: ClassDeclSyntax) {
        owners.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        enterType(
            node,
            name: node.name.text,
            modifiers: node.modifiers,
            attributes: node.attributes,
            generic: node.genericParameterClause != nil,
            isActor: true,
            isReference: true,
            conformances: node.inheritanceClause?.inheritedTypes
                .map(\.type.trimmedDescription) ?? [],
        )
    }

    override func visitPost(_: ActorDeclSyntax) {
        owners.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        enterType(
            node,
            name: node.name.text,
            modifiers: node.modifiers,
            attributes: node.attributes,
            generic: node.genericParameterClause != nil,
            isActor: false,
            isReference: false,
            conformances: node.inheritanceClause?.inheritedTypes
                .map(\.type.trimmedDescription) ?? [],
        )
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        // This generated operation is distinct from the source cases and from user accessors.
        // Its receiver is the concrete enum value; inspecting it never constructs another case.
        add(
            node,
            name: "$inspect",
            kind: .enumerationInspection,
            signature: "Inspect the active enum case and its associated values",
            modifiers: node.modifiers,
            attributes: node.attributes,
            result: "PortholeValue",
        )
        owners.removeLast()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        enterType(
            node,
            name: node.name.text,
            modifiers: node.modifiers,
            attributes: node.attributes,
            generic: true,
            isActor: false,
            isReference: false,
            conformances: node.inheritanceClause?.inheritedTypes
                .map(\.type.trimmedDescription) ?? [],
            reason: "Protocol requirements need a concrete receiver type.",
        )
    }

    override func visitPost(_: ProtocolDeclSyntax) {
        owners.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.extendedType.trimmedDescription
        add(
            node,
            name: name,
            kind: .typeExtension,
            signature: "extension \(name)",
            modifiers: node.modifiers,
            attributes: node.attributes,
            result: name,
            conformances: node.inheritanceClause?.inheritedTypes
                .map(\.type.trimmedDescription) ?? [],
        )
        owners.append(Owner(
            name: name,
            isActor: false,
            isMainActor: attributeNames(node.attributes).contains("MainActor"),
            isReferenceType: false,
            unsupportedReason: node
                .genericWhereClause == nil ? nil :
                "Constrained extension requires a concrete generic binding.",
        ))
        return .visitChildren
    }

    override func visitPost(_: ExtensionDeclSyntax) {
        owners.removeLast()
    }

    override func visit(_: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        // Closure-local declarations, including #Preview state, are not module APIs.
        .skipChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let parameters = functionParameters(node.signature.parameterClause.parameters)
        let reason = unsupported(
            parameters: parameters,
            generic: node.genericParameterClause != nil,
        )
            ??
            (node.modifiers
                .contains(where: { $0.name.text == "mutating" }) ?
                "Mutating value methods require a write-back handle." : nil)
            ??
            (node.name
                .tokenKind == .identifier(node.name.text) ? nil :
                "Operator invocation is not generated.")
        add(
            node,
            name: node.name.text,
            kind: .function,
            signature: node.signature.trimmedDescription,
            modifiers: node.modifiers,
            attributes: node.attributes,
            parameters: parameters,
            result: node.signature.returnClause?.type.trimmedDescription ?? "Void",
            isAsync: node.signature.effectSpecifiers?.asyncSpecifier != nil,
            isThrowing: node.signature.effectSpecifiers?.throwsClause != nil,
            reason: reason,
        )
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let parameters = functionParameters(node.signature.parameterClause.parameters)
        add(
            node,
            name: "init",
            kind: .initializer,
            signature: node.signature.trimmedDescription,
            modifiers: node.modifiers,
            attributes: node.attributes,
            parameters: parameters,
            result: owners.last?.name,
            isAsync: node.signature.effectSpecifiers?.asyncSpecifier != nil,
            isThrowing: node.signature.effectSpecifiers?.throwsClause != nil,
            reason: unsupported(parameters: parameters, generic: node.genericParameterClause != nil)
                ??
                (node
                    .optionalMark == nil ? nil :
                    "Failable initializers are discoverable but not invoked."),
        )
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self)
            else { continue }
            let result = binding.typeAnnotation?.type
                .trimmedDescription ?? inferredLiteralType(binding.initializer?.value)
            let accessors: [AccessorDeclSyntax] = if case let .accessors(list)? = binding
                .accessorBlock?.accessors
            {
                Array(list)
            } else { [] }
            let getter = accessors.first { $0.accessorSpecifier.text == "get" }
            let isMutable = node.bindingSpecifier.text == "var"
                && (binding.accessorBlock == nil || accessors.contains {
                    ["set", "_modify", "didSet", "willSet"].contains($0.accessorSpecifier.text)
                })
            add(
                node,
                name: identifier.identifier.text,
                kind: .property,
                signature: "\(identifier.identifier.text): \(result ?? "<inferred>")",
                modifiers: node.modifiers,
                attributes: node.attributes,
                result: result,
                isAsync: getter?.effectSpecifiers?.asyncSpecifier != nil,
                isThrowing: getter?.effectSpecifiers?.throwsClause != nil,
                isMutable: isMutable,
                reason: result == nil ? "Inferred property type needs compiler semantic metadata." :
                    nil,
                isStoredProperty: binding.accessorBlock == nil && node.attributes.isEmpty
                    && owners.last != nil && !node.modifiers.contains {
                        ["lazy", "static", "class"].contains($0.name.text)
                    },
            )
            if isMutable, let result {
                add(
                    node,
                    name: identifier.identifier.text,
                    kind: .propertySetter,
                    signature: "set \(identifier.identifier.text): \(result)",
                    modifiers: node.modifiers,
                    attributes: node.attributes,
                    parameters: [.init(
                        label: "value",
                        name: "value",
                        type: result,
                        defaultValue: nil,
                    )],
                    result: "Void",
                    isMutable: true,
                )
            }
        }
        return .skipChildren
    }

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        for element in node.elements {
            let parameters = enumParameters(element.parameterClause?.parameters)
            let reason = parameters.compactMap { parameter in
                unsupported(parameters: [parameter], generic: false).map {
                    "Associated value '\(parameter.name)' (\(parameter.type)): \($0)"
                }
            }.first
            add(
                node,
                name: element.name.text.replacingOccurrences(of: "`", with: ""),
                kind: .enumerationCase,
                signature: element.trimmedDescription,
                modifiers: node.modifiers,
                attributes: node.attributes,
                parameters: parameters,
                result: owners.last?.name,
                reason: reason,
            )
        }
        return .skipChildren
    }

    private func enumParameters(
        _ parameters: EnumCaseParameterListSyntax?,
    ) -> [SourceDeclaration.Parameter] {
        guard let parameters else { return [] }
        let labels = parameters.map {
            $0.firstName?.text.replacingOccurrences(of: "`", with: "") ?? "_"
        }
        let labelCounts = Dictionary(grouping: labels.filter { $0 != "_" }, by: { $0 })
            .mapValues(\.count)
        var usedKeys = Set(labelCounts.keys)
        return parameters.enumerated().map { index, parameter in
            let label = labels[index]
            let key: String
            if labelCounts[label] == 1 { key = label }
            else {
                var candidate = "argument\(index)"
                while usedKeys.contains(candidate) {
                    candidate += "_"
                }
                usedKeys.insert(candidate)
                key = candidate
            }
            let modifiers = parameter.modifiers.map(\.trimmedDescription).joined(separator: " ")
            return SourceDeclaration.Parameter(
                label: label,
                name: key,
                type: (modifiers.isEmpty ? "" : modifiers + " ") + parameter.type
                    .trimmedDescription,
                defaultValue: parameter.defaultValue?.value.trimmedDescription,
            )
        }
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        add(
            node,
            name: node.name.text,
            kind: .typeAlias,
            signature: node.trimmedDescription,
            modifiers: node.modifiers,
            attributes: node.attributes,
            result: node.initializer.value.trimmedDescription,
            reason: "A type alias is descriptive metadata.",
        )
        return .skipChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        add(
            node,
            name: "subscript",
            kind: .subscriptDeclaration,
            signature: node.parameterClause.trimmedDescription + node.returnClause
                .trimmedDescription,
            modifiers: node.modifiers,
            attributes: node.attributes,
            parameters: functionParameters(node.parameterClause.parameters),
            result: node.returnClause.type.trimmedDescription,
            reason: "Subscripts require a dedicated index and write-back binding.",
        )
        return .skipChildren
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        add(
            node,
            name: "deinit",
            kind: .deinitializer,
            signature: "deinit",
            modifiers: node.modifiers,
            attributes: node.attributes,
            reason: "Object lifetime is owned by Swift and the scope registry.",
        )
        return .skipChildren
    }

    private func enterType(
        _ node: some DeclSyntaxProtocol,
        name: String,
        modifiers: DeclModifierListSyntax,
        attributes: AttributeListSyntax,
        generic: Bool,
        isActor: Bool,
        isReference: Bool,
        conformances: [String],
        reason: String? = nil,
    ) -> SyntaxVisitorContinueKind {
        let qualified = owners.last.map { "\($0.name).\(name)" } ?? name
        let unsupportedReason = reason ??
            (generic ? "Generic type requires a concrete specialization." : nil) ??
            (conformances.contains(where: { ["~Copyable", "~Escapable"].contains($0) }) ?
                "Noncopyable or nonescapable types cannot use retained value handles." : nil) ??
            owners.last?
            .unsupportedReason
        // A nested nominal type does not inherit its enclosing type's global actor.
        let isMainActor = attributeNames(attributes).contains("MainActor")
        add(
            node,
            name: name,
            kind: .type,
            signature: qualified,
            modifiers: modifiers,
            attributes: attributes,
            result: qualified,
            reason: unsupportedReason,
            declaredActor: isActor,
            declaredMainActor: isMainActor,
            declaredReference: isReference,
            declaredProtocol: node.is(ProtocolDeclSyntax.self),
            conformances: conformances,
        )
        owners.append(Owner(
            name: qualified,
            isActor: isActor,
            isMainActor: isMainActor,
            isReferenceType: isReference,
            unsupportedReason: unsupportedReason,
        ))
        return .visitChildren
    }

    private func functionParameters(
        _ parameters: FunctionParameterListSyntax,
    ) -> [SourceDeclaration.Parameter] {
        let labels = parameters.map { $0.firstName.text.replacingOccurrences(of: "`", with: "") }
        let localNames = parameters.map {
            ($0.secondName?.text ?? $0.firstName.text).replacingOccurrences(of: "`", with: "")
        }
        let labelCounts = Dictionary(grouping: labels.filter { $0 != "_" }, by: { $0 })
            .mapValues(\.count)
        let reservedLabels = Set(labelCounts.filter { $0.value == 1 }.keys)
        let fallbackNames = labels.indices.compactMap { index -> String? in
            guard labelCounts[labels[index]] != 1, localNames[index] != "_" else { return nil }
            return localNames[index]
        }
        let nameCounts = Dictionary(grouping: fallbackNames, by: { $0 }).mapValues(\.count)
        let fixedKeys = labels.indices.map { index -> String? in
            if labelCounts[labels[index]] == 1 { return labels[index] }
            let name = localNames[index]
            if nameCounts[name] == 1, !reservedLabels.contains(name) { return name }
            return nil
        }
        var usedKeys = Set(fixedKeys.compactMap(\.self))
        return parameters.enumerated().map { index, parameter in
            let name: String
            if let fixedKey = fixedKeys[index] { name = fixedKey }
            else {
                var candidate = "argument\(index)"
                while usedKeys.contains(candidate) {
                    candidate += "_"
                }
                usedKeys.insert(candidate)
                name = candidate
            }
            return SourceDeclaration.Parameter(
                label: labels[index],
                name: name,
                type: parameter.type.trimmedDescription + (parameter.ellipsis == nil ? "" : "..."),
                defaultValue: parameter.defaultValue?.value.trimmedDescription,
            )
        }
    }

    private func inferredLiteralType(_ expression: ExprSyntax?) -> String? {
        guard let expression else { return nil }
        if expression.is(IntegerLiteralExprSyntax.self) { return "Int" }
        if expression.is(FloatLiteralExprSyntax.self) { return "Double" }
        if expression.is(StringLiteralExprSyntax.self) { return "String" }
        if expression.is(BooleanLiteralExprSyntax.self) { return "Bool" }
        if let prefix = expression.as(PrefixOperatorExprSyntax.self) {
            return inferredLiteralType(prefix.expression)
        }
        return nil
    }

    private func unsupported(parameters: [SourceDeclaration.Parameter], generic: Bool) -> String? {
        if generic { return "Generic function requires a concrete specialization." }
        if parameters
            .contains(where: { $0.type.contains("->") })
        {
            return "Closure parameters require an executable callback binding."
        }
        if parameters
            .contains(where: { $0.type.contains("inout ") })
        {
            return "Inout arguments require a write-back handle."
        }
        if parameters
            .contains(where: { $0.type.contains("...") })
        {
            return "Variadic parameters are not generated."
        }
        if parameters
            .contains(where: {
                $0.type.contains("some ") || $0.type.contains("borrowing ") || $0.type
                    .contains("consuming ")
            })
        {
            return "Opaque or ownership-qualified parameters require a specialized binding."
        }
        return nil
    }

    private func add(
        _ node: some DeclSyntaxProtocol,
        name: String,
        kind: SourceDeclaration.Kind,
        signature: String,
        modifiers: DeclModifierListSyntax,
        attributes: AttributeListSyntax,
        parameters: [SourceDeclaration.Parameter] = [],
        result: String? = nil,
        isAsync: Bool = false,
        isThrowing: Bool = false,
        isMutable: Bool = false,
        reason: String? = nil,
        declaredActor: Bool? = nil,
        declaredMainActor: Bool? = nil,
        declaredReference: Bool? = nil,
        declaredProtocol: Bool = false,
        conformances: [String] = [],
        isStoredProperty: Bool = false,
    ) {
        let access = modifiers.map(\.name.text).first(where: { [
            "open",
            "public",
            "package",
            "internal",
            "fileprivate",
            "private",
        ].contains($0) }) ?? "internal"
        let owner = owners.last
        let attributeNames = attributeNames(attributes)
        let isNonisolated = modifiers.contains { $0.name.text == "nonisolated" }
        let line = locations.location(for: node.positionAfterSkippingLeadingTrivia).line
        let qualified = owner.map { "\($0.name).\(name)" } ?? name
        let baseID = "\(moduleName):\(file.path):\(qualified):\(kind.rawValue):\(signature)"
        // Separate repeated extensions and requirement/default pairs without tying identity to
        // line numbers. Unrelated source edits do not change an occurrence's identity.
        let occurrence = declarationOccurrences[baseID, default: 0] + 1
        declarationOccurrences[baseID] = occurrence
        let declarationID = occurrence == 1 ? baseID : "\(baseID):occurrence:\(occurrence)"
        declarations.append(SourceDeclaration(
            declarationID: declarationID,
            name: name,
            owner: owner?.name,
            kind: kind,
            signature: signature,
            file: file.path,
            line: line,
            documentation: node.leadingTrivia.description
                .trimmingCharacters(in: .whitespacesAndNewlines),
            access: access,
            conditions: conditions(of: Syntax(node)),
            attributes: attributeNames,
            parameters: parameters,
            resultType: result,
            isStatic: modifiers
                .contains(where: { ["static", "class"].contains($0.name.text) }) || kind ==
                .initializer || kind == .enumerationCase || owner == nil,
            isAsync: isAsync,
            isThrowing: isThrowing,
            isMutable: isMutable,
            isStoredProperty: isStoredProperty,
            isActor: declaredActor ?? (owner?.isActor == true),
            isMainActor: declaredMainActor ??
                (attributeNames.contains("MainActor") || owner?.isMainActor == true),
            isNonisolated: isNonisolated,
            isReferenceType: declaredReference ?? (owner?.isReferenceType == true),
            isProtocol: declaredProtocol,
            conformances: conformances,
            unsupportedReason: reason ?? owner?.unsupportedReason,
        ))
    }

    private func attributeNames(_ attributes: AttributeListSyntax) -> [String] {
        attributes.compactMap { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription }
    }

    private func conditions(of node: Syntax) -> [String] {
        var result: [String] = []
        var current = node.parent
        while let ancestor = current {
            if let clause = ancestor.as(IfConfigClauseSyntax.self),
               let declaration = ancestor.parent?.parent?.as(IfConfigDeclSyntax.self)
            {
                var previous: [String] = []
                for candidate in declaration.clauses {
                    if candidate.id == clause.id {
                        var terms = previous.map { "!(\($0))" }
                        if let condition = clause
                            .condition { terms.append("(\(condition.trimmedDescription))") }
                        if !terms.isEmpty { result.append(terms.joined(separator: " && ")) }
                        break
                    }
                    if let condition = candidate
                        .condition { previous.append(condition.trimmedDescription) }
                }
            }
            current = ancestor.parent
        }
        return result.reversed()
    }
}
