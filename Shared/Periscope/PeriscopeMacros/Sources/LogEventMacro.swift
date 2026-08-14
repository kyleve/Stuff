import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct LogEventMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext,
    ) throws -> [DeclSyntax] {
        guard let event = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(
                declaration,
                id: "event-not-struct",
                message: "@LogEvent requires a struct",
            )
            return []
        }
        guard let arguments = argumentList(of: node),
              let idExpression = arguments.first(where: { $0.label == nil })?.expression,
              let eventID = plainString(from: idExpression),
              !eventID.isEmpty
        else {
            context.diagnose(
                node,
                id: "event-id",
                message: "@LogEvent requires a nonempty string-literal event ID",
            )
            return []
        }
        guard let scope = context.lexicalContext.first?.as(EnumDeclSyntax.self),
              attribute(named: "LogScope", in: scope.attributes) != nil
        else {
            context.diagnose(
                event,
                id: "event-scope",
                message: "@LogEvent must be nested directly in an @LogScope enum",
            )
            return []
        }

        let parsed = parseArguments(arguments, on: node, in: context)
        let fields = parseFields(event, in: context)
        guard !parsed.hasError, !fields.hasError else { return [] }
        let access = accessPrefix(event.modifiers)
        let hasLevel = instanceProperty(named: "level", in: event) != nil
        let hasMessage = instanceProperty(named: "message", in: event) != nil
        let hasExternalID = instanceProperty(named: "externalID", in: event) != nil
        let hasProtected = staticProperty(named: "isProtectedFromDropping", in: event) != nil

        if parsed.level != nil, hasLevel {
            context.diagnose(
                event,
                id: "duplicate-level",
                message: "an event cannot declare both a fixed and an instance level",
            )
            return []
        }
        if parsed.message != nil, hasMessage {
            context.diagnose(
                event,
                id: "duplicate-message",
                message: "an event cannot declare both a static and an instance message",
            )
            return []
        }
        if parsed.message == nil, !hasMessage {
            context.diagnose(
                event,
                id: "missing-message",
                message: "an event requires a static or instance message",
            )
            return []
        }

        let scopeName = scope.name.text
        var members: [DeclSyntax] = [
            "\(raw: access)static let eventName = \(raw: scopeName).scopeName + \".\(raw: escapedStringLiteral(eventID))\"",
            "\(raw: access)static let eventVersion = \(raw: parsed.version)",
            DeclSyntax(stringLiteral: initializer(access: access, fields: fields.values)),
            DeclSyntax(stringLiteral: classifiedFields(access: access, fields: fields.values)),
        ]
        if !fields.values.isEmpty {
            members.insert(
                DeclSyntax(stringLiteral: codingKeys(access: access, fields: fields.values)),
                at: 2,
            )
        }
        if let level = parsed.level {
            members.append("\(raw: access)var level: LogLevel { .\(raw: level) }")
        }
        if let message = parsed.message {
            members
                .append(
                    "\(raw: access)var message: String { \"\(raw: escapedStringLiteral(message))\" }",
                )
        }
        if !hasExternalID {
            members.append("\(raw: access)var externalID: String? { nil }")
        }
        if !hasProtected {
            members.append("\(raw: access)static var isProtectedFromDropping: Bool { false }")
        }
        return members
    }

    public static func expansion(
        of _: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext,
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(StructDeclSyntax.self),
              context.lexicalContext.first?.as(EnumDeclSyntax.self).map({
                  attribute(named: "LogScope", in: $0.attributes) != nil
              }) == true
        else {
            return []
        }
        let extensionDecl: DeclSyntax = "extension \(type.trimmed): LogEvent {}"
        return [extensionDecl.cast(ExtensionDeclSyntax.self)]
    }
}

extension LogEventMacro {
    fileprivate struct ParsedArguments {
        var level: String?
        var message: String?
        var version = 1
        var hasError = false
    }

    fileprivate struct ParsedFields {
        var values: [EventField] = []
        var hasError = false
    }

    fileprivate static func parseArguments(
        _ arguments: LabeledExprListSyntax,
        on node: AttributeSyntax,
        in context: some MacroExpansionContext,
    ) -> ParsedArguments {
        var result = ParsedArguments()
        for argument in arguments {
            switch argument.label?.text {
                case "level":
                    guard let level = memberName(from: argument.expression) else {
                        context.diagnose(
                            argument,
                            id: "event-level",
                            message: "level must be a LogLevel member",
                        )
                        result.hasError = true
                        continue
                    }
                    result.level = level
                case "message":
                    guard let message = plainString(from: argument.expression) else {
                        context.diagnose(
                            argument,
                            id: "event-message",
                            message: "message must be a plain string literal",
                        )
                        result.hasError = true
                        continue
                    }
                    result.message = message
                case "version":
                    guard let version = plainInteger(from: argument.expression), version > 0 else {
                        context.diagnose(
                            argument,
                            id: "event-version",
                            message: "version must be a positive integer literal",
                        )
                        result.hasError = true
                        continue
                    }
                    result.version = version
                case nil:
                    break
                default:
                    context.diagnose(
                        node,
                        id: "event-argument",
                        message: "unsupported @LogEvent argument",
                    )
                    result.hasError = true
            }
        }
        return result
    }

    fileprivate static func parseFields(
        _ event: StructDeclSyntax,
        in context: some MacroExpansionContext,
    ) -> ParsedFields {
        let storedMetadataNames = [
            "message",
            "externalID",
            "classifiedFields",
            "eventName",
            "eventVersion",
            "isProtectedFromDropping",
        ]
        let reservedLabels = ["attachments", "function", "fileID"]
        let shareableKinds = ["boolean", "count", "limit", "duration", "category", "json"]
        var result = ParsedFields()
        var keys = Set<String>()

        for member in event.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  !variable.modifiers
                  .contains(where: { ["static", "class"].contains($0.name.text) })
            else {
                continue
            }
            guard variable.bindings.count == 1, let binding = variable.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self)
            else {
                context.diagnose(
                    variable,
                    id: "event-binding",
                    message: "event properties require one named binding",
                )
                result.hasError = true
                continue
            }
            let name = identifier.identifier.text
            if let accessorBlock = binding.accessorBlock {
                if attribute(named: "LogField", in: variable.attributes) != nil
                    || accessorBlock.hasObservers
                {
                    context.diagnose(
                        variable,
                        id: "event-accessor",
                        message: "event fields cannot declare accessors or observers",
                    )
                    result.hasError = true
                }
                // Computed projections are ordinary event API. They do not
                // participate in the persisted payload or classification.
                continue
            }
            if storedMetadataNames.contains(name) {
                context.diagnose(
                    variable,
                    id: "event-reserved",
                    message: "stored event property '\(name)' collides with generated metadata",
                )
                result.hasError = true
                continue
            }
            guard binding.initializer == nil,
                  let type = binding.typeAnnotation?.type.trimmedDescription
            else {
                context.diagnose(
                    variable,
                    id: "event-property",
                    message: "event fields require an explicit type and no initializer",
                )
                result.hasError = true
                continue
            }
            guard let fieldAttribute = attribute(named: "LogField", in: variable.attributes),
                  let arguments = argumentList(of: fieldAttribute),
                  let keyExpression = arguments.first(where: { $0.label == nil })?.expression,
                  let key = plainString(from: keyExpression), !key.isEmpty,
                  let exposureExpression = arguments.first(where: { $0.label?.text == "exposure" })?
                  .expression,
                  let exposure = memberName(from: exposureExpression),
                  let kindExpression = arguments.first(where: { $0.label?.text == "kind" })?
                  .expression,
                  let kind = memberName(from: kindExpression)
            else {
                context.diagnose(
                    variable,
                    id: "event-field",
                    message: "stored event properties require a complete @LogField classification",
                )
                result.hasError = true
                continue
            }
            if !keys.insert(key).inserted {
                context.diagnose(
                    fieldAttribute,
                    id: "duplicate-key",
                    message: "event field key '\(key)' is duplicated",
                )
                result.hasError = true
            }
            if reservedLabels.contains(name) {
                context.diagnose(
                    variable,
                    id: "reserved-label",
                    message: "event field label '\(name)' is reserved",
                )
                result.hasError = true
            }
            if exposure == "shareable", !shareableKinds.contains(kind) {
                context.diagnose(
                    fieldAttribute,
                    id: "shareable-kind",
                    message: "field kind '.\(kind)' cannot be shareable",
                )
                result.hasError = true
            }
            if exposure != "shareable", exposure != "restricted" {
                context.diagnose(
                    fieldAttribute,
                    id: "field-exposure",
                    message: "field exposure must be .shareable or .restricted",
                )
                result.hasError = true
            }
            if shareableTypeMismatch(type: type, kind: kind, exposure: exposure) {
                context.diagnose(
                    variable,
                    id: "shareable-type",
                    message: "shareable .\(kind) requires its classified Swift value type",
                )
                result.hasError = true
            }
            result.values.append(EventField(
                name: name,
                type: type,
                key: key,
                exposure: exposure,
                kind: kind,
                isOptional: type.hasSuffix("?"),
            ))
        }
        return result
    }

    fileprivate static func shareableTypeMismatch(
        type: String,
        kind: String,
        exposure: String,
    ) -> Bool {
        guard exposure == "shareable" else { return false }
        let base = type.hasSuffix("?") ? String(type.dropLast()) : type
        switch kind {
            case "boolean": return base != "Bool"
            case "count", "limit": return base != "Int"
            case "duration": return base != "Duration"
            case "json": return base != "JSONValue"
            case "category": return false
            default: return true
        }
    }

    fileprivate static func instanceProperty(
        named name: String,
        in event: StructDeclSyntax,
    ) -> VariableDeclSyntax? {
        event.memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }
            .first { variable in
                !variable.modifiers.contains(where: { ["static", "class"].contains($0.name.text) })
                    && variable.bindings
                    .contains {
                        $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name
                    }
            }
    }

    fileprivate static func staticProperty(
        named name: String,
        in event: StructDeclSyntax,
    ) -> VariableDeclSyntax? {
        event.memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }
            .first { variable in
                variable.modifiers.contains(where: { ["static", "class"].contains($0.name.text) })
                    && variable.bindings
                    .contains {
                        $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name
                    }
            }
    }

    fileprivate static func codingKeys(access _: String, fields: [EventField]) -> String {
        let cases = fields.map { "        case \($0.name) = \"\(escapedStringLiteral($0.key))\"" }
            .joined(separator: "\n")
        return """
        private enum CodingKeys: String, CodingKey {
        \(cases)
        }
        """
    }

    fileprivate static func initializer(access: String, fields: [EventField]) -> String {
        let parameters = fields.map { "        \($0.name): \($0.parameterType)" }
            .joined(separator: ",\n")
        let assignments = fields.map {
            "        self._\($0.name) = LogField(wrappedValue: \($0.name).value, \"\(escapedStringLiteral($0.key))\", exposure: .\($0.exposure), kind: .\($0.kind))"
        }.joined(separator: "\n")
        if fields.isEmpty {
            return "\(access)init() {}"
        }
        return """
        \(access)init(
        \(parameters)
        ) {
        \(assignments)
        }
        """
    }

    fileprivate static func classifiedFields(access: String, fields: [EventField]) -> String {
        let statements = fields.map { field -> String in
            let key = "LogFieldKey(\"\(escapedStringLiteral(field.key))\")"
            if field.exposure == "restricted" {
                return "        fields.append(.restricted(key: \(key), kind: .\(field.kind)))"
            }
            let rawName = field.isOptional ? "value" : field.name
            let value = switch field.kind {
                case "boolean": ".bool(\(rawName))"
                case "count", "limit": ".int(\(rawName))"
                case "duration": ".double(\(rawName).periscopeMilliseconds)"
                case "category": ".string(\(rawName).rawValue)"
                case "json": ".json(\(rawName))"
                default: ".string(String(describing: \(rawName)))"
            }
            let append = "fields.append(.shareable(key: \(key), kind: .\(field.kind), value: \(value)))"
            if field.isOptional {
                return "        if let value = \(field.name) { \(append) }"
            }
            return "        \(append)"
        }.joined(separator: "\n")
        return """
        \(access)var classifiedFields: [ClassifiedLogField] {
            var fields: [ClassifiedLogField] = []
        \(statements)
            return fields
        }
        """
    }
}
