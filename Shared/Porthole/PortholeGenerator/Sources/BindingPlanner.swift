import Foundation

/// Conservative isolation/type analysis decides which inventoried APIs can get a real compiled
/// thunk.
struct BindingPlanner {
    struct Binding {
        let declaration: SourceDeclaration
        let receiverType: String?
        let isActor: Bool
        let isMainActor: Bool
        let unsupportedReason: String?
    }

    let module: SourceModule
    let dependencyModules: [SourceModule]
    private let typesByName: [String: [SourceDeclaration]]
    private let enumTypeNames: Set<String>

    init(module: SourceModule, dependencyModules: [SourceModule]) {
        self.module = module
        self.dependencyModules = dependencyModules
        let nominalTypes = (module.declarations + dependencyModules.flatMap(\.declarations))
            .filter { [.type, .typeExtension].contains($0.kind) }
        typesByName = Dictionary(grouping: nominalTypes, by: { $0.resultType ?? $0.name })
        enumTypeNames = Set((module.declarations + dependencyModules.flatMap(\.declarations))
            .filter { [.enumerationCase, .enumerationInspection].contains($0.kind) }
            .compactMap(\.owner))
    }

    func plan(_ declaration: SourceDeclaration) -> Binding {
        let owner = declaration.owner.flatMap { typesByName[$0]?.first { $0.kind == .type } }
        let receiver = declaration.isStatic ? nil : declaration.owner
            .map { owner?.isProtocol == true ? "any \($0)" : $0 }
        let isActor = !declaration.isNonisolated && (declaration.isActor || owner?.isActor == true)
        // Case construction creates a new value. Keep non-Sendable payloads and results in
        // MainActor boxes without claiming that the enum itself has global actor isolation.
        let boxesEnumValues = declaration.kind == .enumerationCase &&
            (declaration.parameters.map(\.type) + [declaration.resultType ?? "Void"])
            .contains { !isSendable($0, relativeTo: declaration.owner) }
        let boxesEnumReceiver = !declaration.isAsync && receiver.map {
            enumTypeNames.contains($0) && !isSendable($0, relativeTo: declaration.owner)
        } == true
        let isMainActor = boxesEnumValues || boxesEnumReceiver || !declaration.isNonisolated &&
            (declaration.isMainActor || owner.map { isMainActorType($0) } == true ||
                (!declaration.isAsync && hasMainActorContainer(owner)))
        var reason = declaration.unsupportedReason ?? owner?.unsupportedReason ??
            unsupportedOwnerReason(of: declaration)
        if owner?.isProtocol == true, isMainActor, !declaration.isStatic,
           reason == "Protocol requirements need a concrete receiver type."
        {
            reason = nil
        }
        if owner?.isProtocol == true,
           (declaration.parameters.map(\.type) + [declaration.resultType ?? "Void"])
           .contains(where: {
               $0.range(of: "\\bSelf\\b", options: .regularExpression) != nil
           })
        {
            reason = "Protocol Self requirements need a concrete receiver type."
        }
        if ![
            .function,
            .initializer,
            .property,
            .propertySetter,
            .enumerationCase,
            .enumerationInspection,
        ]
        .contains(declaration.kind) {
            reason = reason ?? "This declaration is descriptive metadata."
        }
        if declaration.attributes.contains("available") || owner?.attributes
            .contains("available") == true
        {
            reason = reason ?? "Availability-constrained declarations require a runtime availability adapter."
        }
        if let receiver, !isTransferable(
            receiver,
            relativeTo: declaration.owner,
            onMainActor: isMainActor,
        ) {
            reason = reason ?? "The receiver has no statically known Sendable or actor isolation boundary."
        }
        for parameter in declaration.parameters where !isTransferable(
            parameter.type,
            relativeTo: declaration.owner,
            onMainActor: isMainActor,
        ) {
            reason = reason ?? "Argument '\(parameter.name)' has no statically known Sendable representation (\(parameter.type))."
        }
        if declaration.kind == .enumerationInspection {
            let cases = enumCases(for: declaration)
            if cases
                .isEmpty { reason = reason ?? "This enum has no source-declared cases to inspect." }
            for enumCase in cases {
                if let caseReason = enumCase.unsupportedReason {
                    reason = reason ?? "Enum case '\(enumCase.name)': \(caseReason)"
                }
                if enumCase.attributes.contains("available") {
                    reason = reason ?? "Enum case '\(enumCase.name)' requires a runtime availability adapter."
                }
                for payload in enumCase.parameters where !isTransferable(
                    payload.type,
                    relativeTo: declaration.owner,
                    onMainActor: isMainActor,
                ) {
                    reason = reason ?? "Enum case '\(enumCase.name)' associated value '\(payload.name)' has no statically known Sendable or actor isolation boundary (\(payload.type))."
                }
            }
        } else if let result = declaration.resultType, !isTransferable(
            result,
            relativeTo: declaration.owner,
            onMainActor: isMainActor,
        ) {
            reason = reason ?? "The result has no statically known Sendable representation (\(result))."
        }
        if declaration.kind == .propertySetter, !declaration.isStatic,
           !isActor,
           !(isMainActor &&
               (owner?.isReferenceType == true || owner?.conformances
                   .contains("AnyObject") == true))
        {
            reason = reason ?? "Property mutation requires an actor-owned reference or a value write-back handle."
        }
        return Binding(
            declaration: declaration,
            receiverType: receiver,
            isActor: isActor,
            isMainActor: isMainActor,
            unsupportedReason: reason,
        )
    }

    func enumCases(for declaration: SourceDeclaration) -> [SourceDeclaration] {
        module.declarations.filter {
            $0.kind == .enumerationCase && $0.owner == declaration.owner &&
                $0.file == declaration.file && $0.conditions.starts(with: declaration.conditions)
        }
    }

    func hasKnownStoredGetter(_ declaration: SourceDeclaration) -> Bool {
        isOrdinaryStoredGetter(declaration) && !resultSerializationRequiresApproval(declaration)
    }

    func isSynchronousActorConstant(_ declaration: SourceDeclaration) -> Bool {
        declaration.kind == .property && !declaration.isMutable &&
            isOrdinaryStoredGetter(declaration) &&
            isSendable(declaration.resultType ?? "Void", relativeTo: declaration.owner)
    }

    func resultSerializationRequiresApproval(_ declaration: SourceDeclaration) -> Bool {
        guard isOrdinaryStoredGetter(declaration),
              let result = declaration.resultType else { return false }
        return isKnownEncodable(result, relativeTo: declaration.owner) && !hasSystemEncoder(result)
    }

    private func isOrdinaryStoredGetter(_ declaration: SourceDeclaration) -> Bool {
        guard declaration.isStoredProperty else { return false }
        let owner = declaration.owner.flatMap { typesByName[$0]?.first { $0.kind == .type } }
        return owner?.attributes.allSatisfy { ["MainActor", "available"].contains($0) } != false
    }

    func isSendable(_ rawType: String, relativeTo owner: String?) -> Bool {
        let type = rawType.trimmingCharacters(in: .whitespacesAndNewlines)
        if type == "Self", let owner { return isSendable(owner, relativeTo: nil) }
        if type.hasSuffix("?") { return isSendable(String(type.dropLast()), relativeTo: owner) }
        if type.hasPrefix("[") && type.hasSuffix("]") {
            let inner = String(type.dropFirst().dropLast())
            return splitTopLevel(inner, separator: ":").allSatisfy { isSendable(
                $0,
                relativeTo: owner,
            ) }
        }
        if [
            "Void",
            "()",
            "Bool",
            "String",
            "Substring",
            "Character",
            "Int",
            "Int8",
            "Int16",
            "Int32",
            "Int64",
            "UInt",
            "UInt8",
            "UInt16",
            "UInt32",
            "UInt64",
            "Float",
            "Double",
            "Decimal",
            "Date",
            "Data",
            "URL",
            "UUID",
            "Duration",
            "TimeInterval",
            "Calendar",
            "TimeZone",
            "Locale",
        ].contains(type) { return true }
        if let start = type.firstIndex(of: "<"), type.hasSuffix(">") {
            let generic = String(type[..<start])
            if ["Array", "Set", "Dictionary", "Optional", "Result", "Range", "ClosedRange"]
                .contains(generic)
            {
                return splitTopLevel(
                    String(type[type.index(after: start) ..< type.index(before: type.endIndex)]),
                    separator: ",",
                )
                .allSatisfy { isSendable($0, relativeTo: owner) }
            }
            return false
        }
        let lookup = type.hasPrefix("any ") ? String(type.dropFirst(4)) : type
        let unqualified = lookup
            .hasPrefix(module.name + ".") ? String(lookup.dropFirst(module.name.count + 1)) : lookup
        let candidates = typesByName[qualifiedName(unqualified, owner: owner)] ?? []
        return candidates.contains { declaration in
            guard unsupportedOwnerReason(of: declaration) == nil else { return false }
            return declaration
                .isActor || (declaration.kind == .type && declaration.isMainActor &&
                    !declaration.isNonisolated && !declaration.isProtocol) || declaration
                .conformances.contains {
                    ["Sendable", "@unchecked Sendable", "Swift.Sendable"].contains($0)
                }
        }
    }

    func isTransferable(_ rawType: String, relativeTo owner: String?, onMainActor: Bool) -> Bool {
        if isSendable(rawType, relativeTo: owner) { return true }
        guard onMainActor else { return false }
        let type = rawType.trimmingCharacters(in: .whitespacesAndNewlines)
        if type.hasSuffix("?") { return isTransferable(
            String(type.dropLast()),
            relativeTo: owner,
            onMainActor: true,
        ) }
        if type.hasPrefix("["), type.hasSuffix("]") {
            return splitTopLevel(String(type.dropFirst().dropLast()), separator: ":").allSatisfy {
                isTransferable($0, relativeTo: owner, onMainActor: true)
            }
        }
        if let start = type.firstIndex(of: "<"), type.hasSuffix(">") {
            guard ["Array", "Set", "Dictionary", "Optional"].contains(String(type[..<start]))
            else { return false }
            return splitTopLevel(
                String(type[type.index(after: start) ..< type.index(before: type.endIndex)]),
                separator: ",",
            ).allSatisfy {
                isTransferable($0, relativeTo: owner, onMainActor: true)
            }
        }
        let lookup = type.hasPrefix("any ") ? String(type.dropFirst(4)) : type
        return (typesByName[qualifiedName(lookup, owner: owner)] ?? []).contains {
            guard unsupportedOwnerReason(of: $0) == nil else { return false }
            if $0.isProtocol { return isMainActorType($0) }
            return $0.kind == .type && $0.unsupportedReason == nil
        }
    }

    private func unsupportedOwnerReason(of declaration: SourceDeclaration) -> String? {
        var name = declaration.kind == .typeExtension ? declaration.resultType : declaration.owner
        while let candidate = name {
            if let reason = typesByName[candidate]?
                .first(where: { $0.kind == .type && $0.unsupportedReason != nil })?
                .unsupportedReason
            {
                return "Enclosing type '\(candidate)': \(reason)"
            }
            // An extension can introduce a nominal type outside its parent's lexical body.
            // Walk every qualified ancestor before allowing references to that type.
            name = candidate.lastIndex(of: ".").map { String(candidate[..<$0]) }
        }
        return nil
    }

    private func isMainActorType(
        _ declaration: SourceDeclaration,
        visited: Set<String> = [],
    ) -> Bool {
        guard !declaration.isNonisolated, !visited.contains(declaration.declarationID)
        else { return false }
        if declaration.isMainActor { return true }
        let visited = visited.union([declaration.declarationID])
        return declaration.conformances.contains { inherited in
            let name = qualifiedName(inherited, owner: declaration.owner)
            let candidates = (typesByName[name] ?? []).filter { $0.kind == .type }
            if !candidates.isEmpty {
                return candidates.contains {
                    isMainActorType($0, visited: visited)
                }
            }
            // The pinned SDK declares SwiftUI View as @MainActor. Source declarations
            // of a nominal type take precedence; extensions do not redeclare SDK types.
            return ["View", "SwiftUI.View", "SwiftUICore.View"].contains(name)
        }
    }

    private func hasMainActorContainer(_ declaration: SourceDeclaration?) -> Bool {
        guard let parent = declaration?.owner
            .flatMap({ typesByName[$0]?.first { $0.kind == .type } })
        else { return false }
        // Synchronous APIs on a nested value can operate on its retained MainActor box.
        // This is an adapter execution boundary, not implicit Sendable conformance.
        return isMainActorType(parent) || hasMainActorContainer(parent)
    }

    func isKnownEncodable(_ rawType: String, relativeTo owner: String?) -> Bool {
        let type = rawType.trimmingCharacters(in: .whitespacesAndNewlines)
        if type
            .hasSuffix("?") { return isKnownEncodable(String(type.dropLast()), relativeTo: owner) }
        if type.hasPrefix("["), type.hasSuffix("]") {
            return splitTopLevel(String(type.dropFirst().dropLast()), separator: ":")
                .allSatisfy { isKnownEncodable(
                    $0,
                    relativeTo: owner,
                ) }
        }
        if let start = type.firstIndex(of: "<"), type.hasSuffix(">") {
            guard ["Array", "Set", "Dictionary", "Optional"].contains(String(type[..<start]))
            else { return false }
            return splitTopLevel(
                String(type[type.index(after: start) ..< type.index(before: type.endIndex)]),
                separator: ",",
            ).allSatisfy { isKnownEncodable($0, relativeTo: owner) }
        }
        if Self.systemEncodableTypes.contains(type) { return true }
        let candidates = typesByName[qualifiedName(type, owner: owner)] ?? []
        return candidates.contains { declaration in
            !declaration.isProtocol && declaration.conformances.contains {
                ["Codable", "Encodable", "Swift.Codable", "Swift.Encodable"].contains($0)
            }
        }
    }

    private func hasSystemEncoder(_ rawType: String) -> Bool {
        let type = rawType.trimmingCharacters(in: .whitespacesAndNewlines)
        if type.hasSuffix("?") { return hasSystemEncoder(String(type.dropLast())) }
        if type.hasPrefix("["), type.hasSuffix("]") {
            return splitTopLevel(String(type.dropFirst().dropLast()), separator: ":")
                .allSatisfy(hasSystemEncoder)
        }
        if let start = type.firstIndex(of: "<"), type.hasSuffix(">") {
            guard ["Array", "Set", "Dictionary", "Optional"].contains(String(type[..<start]))
            else { return false }
            return splitTopLevel(
                String(type[type.index(after: start) ..< type.index(before: type.endIndex)]),
                separator: ",",
            ).allSatisfy(hasSystemEncoder)
        }
        return Self.systemEncodableTypes.contains(type)
    }

    private static let systemEncodableTypes: Set<String> = [
        "Bool",
        "String",
        "Int",
        "Int8",
        "Int16",
        "Int32",
        "Int64",
        "UInt",
        "UInt8",
        "UInt16",
        "UInt32",
        "UInt64",
        "Float",
        "Double",
        "Decimal",
        "Date",
        "Data",
        "URL",
        "UUID",
        "TimeInterval",
        "Calendar",
        "TimeZone",
        "Locale",
    ]

    func qualifiedType(_ type: String, owner: String?) -> String {
        // Qualify lexical names inside containers as well as direct parameter types.
        var result = ""
        var token = ""
        var followsDot = false
        func flush() {
            if !token.isEmpty {
                result += followsDot ? token : qualifiedName(token, owner: owner)
                token = ""
            }
        }
        for character in type {
            if character.isLetter || character.isNumber || character == "_" {
                if token.isEmpty { followsDot = result.last == "." }
                token.append(character)
            } else {
                flush()
                result.append(character)
            }
        }
        flush()
        return result
    }

    private func qualifiedName(_ name: String, owner: String?) -> String {
        if name == "Self", let owner { return owner }
        var currentOwner = owner
        while let candidateOwner = currentOwner {
            let candidate = "\(candidateOwner).\(name)"
            if typesByName[candidate] != nil { return candidate }
            currentOwner = candidateOwner.lastIndex(of: ".").map { String(candidateOwner[..<$0]) }
        }
        return name
    }

    private func splitTopLevel(_ value: String, separator: Character) -> [String] {
        var depth = 0
        var result: [String] = []
        var current = ""
        for character in value {
            if character == separator, depth == 0 {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                if ["<", "[", "("].contains(character) { depth += 1 }
                if [">", "]", ")"].contains(character) { depth -= 1 }
                current.append(character)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }
}
