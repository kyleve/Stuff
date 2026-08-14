import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct LogScopeMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext,
    ) throws -> [DeclSyntax] {
        guard let scope = declaration.as(EnumDeclSyntax.self) else {
            context.diagnose(
                declaration,
                id: "scope-not-enum",
                message: "@LogScope requires an enum namespace",
            )
            return []
        }
        guard let arguments = argumentList(of: node),
              let expression = arguments.first?.expression,
              let id = plainString(from: expression), !id.isEmpty
        else {
            context.diagnose(
                node,
                id: "scope-id",
                message: "@LogScope requires a nonempty string-literal scope ID",
            )
            return []
        }
        if scope.memberBlock.members.contains(where: { $0.decl.is(EnumCaseDeclSyntax.self) }) {
            context.diagnose(
                scope,
                id: "scope-cases",
                message: "an @LogScope enum cannot declare cases",
            )
            return []
        }
        let access = accessPrefix(scope.modifiers)
        let events = eventMethods(in: scope, context: context)
        var members: [DeclSyntax] = [
            "\(raw: access)static let scopeName = \"\(raw: escapedStringLiteral(id))\"",
        ]
        guard !events.isEmpty else { return members }
        members.append(DeclSyntax(stringLiteral: methodsContainer(
            access: access,
            scope: scope.name.text,
            events: events,
        )))
        members.append(contentsOf: events.map { event in
            DeclSyntax(stringLiteral: methodProxy(
                access: event.access,
                name: event.name,
                scope: scope.name.text,
                event: event.event,
                fields: event.fields,
            ))
        })
        members.append(DeclSyntax(stringLiteral: """
        \(access)static func makeLogMethods(_ log: Log<\(scope.name.text)>) -> LogMethods {
            LogMethods(log: log)
        }
        """))
        return members
    }

    public static func expansion(
        of _: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext,
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(EnumDeclSyntax.self) else { return [] }
        let extensionDecl: DeclSyntax = "extension \(type.trimmed): LogScopeDefinition {}"
        return [extensionDecl.cast(ExtensionDeclSyntax.self)]
    }
}

extension LogScopeMacro {
    fileprivate struct EventMethod {
        let access: String
        let name: String
        let event: String
        let fields: [EventField]
    }

    fileprivate static func eventMethods(
        in scope: EnumDeclSyntax,
        context: some MacroExpansionContext,
    ) -> [EventMethod] {
        let scopeAccess = accessPrefix(scope.modifiers)
        var seenIDs = Set<String>()
        var seenMethods = Set<String>()
        var methods: [EventMethod] = []

        for member in scope.memberBlock.members {
            guard let event = member.decl.as(StructDeclSyntax.self),
                  let eventAttribute = attribute(named: "LogEvent", in: event.attributes),
                  let arguments = argumentList(of: eventAttribute),
                  let idExpression = arguments.first?.expression,
                  let eventID = plainString(from: idExpression)
            else {
                continue
            }
            if !seenIDs.insert(eventID).inserted {
                context.diagnose(
                    event,
                    id: "duplicate-event-id",
                    message: "event ID '\(eventID)' is duplicated in this scope",
                )
                continue
            }
            let methodName = lowerCamelCase(event.name.text)
            if !seenMethods.insert(methodName).inserted {
                context.diagnose(
                    event,
                    id: "duplicate-method",
                    message: "generated log method '\(methodName)' is duplicated",
                )
                continue
            }
            let fields = eventFields(event)
            let eventAccess = accessPrefix(event.modifiers)
            let access = scopeAccess == "public " && eventAccess == "public " ? "public " : ""
            methods.append(EventMethod(
                access: access,
                name: methodName,
                event: event.name.text,
                fields: fields,
            ))
        }
        return methods
    }
}

extension LogScopeMacro {
    fileprivate static func eventFields(_ event: StructDeclSyntax) -> [EventField] {
        event.memberBlock.members.compactMap { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  let fieldAttribute = attribute(named: "LogField", in: variable.attributes),
                  let binding = variable.bindings.first,
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let type = binding.typeAnnotation?.type.trimmedDescription,
                  let arguments = argumentList(of: fieldAttribute),
                  let keyExpression = arguments.first?.expression,
                  let key = plainString(from: keyExpression),
                  let exposureExpression = arguments.first(where: { $0.label?.text == "exposure" })?
                  .expression,
                  let exposure = memberName(from: exposureExpression),
                  let kindExpression = arguments.first(where: { $0.label?.text == "kind" })?
                  .expression,
                  let kind = memberName(from: kindExpression)
            else {
                return nil
            }
            return EventField(
                name: name,
                type: type,
                key: key,
                exposure: exposure,
                kind: kind,
                isOptional: type.hasSuffix("?"),
            )
        }
    }

    fileprivate static func methodsContainer(
        access: String,
        scope: String,
        events: [EventMethod],
    ) -> String {
        let properties = events.map { event in
            "    \(event.access)var \(event.name): \(event.event)LogMethod { \(event.event)LogMethod(log: log) }"
        }.joined(separator: "\n")
        return """
        \(access)struct LogMethods {
            fileprivate let log: Log<\(scope)>

        \(properties)
        }
        """
    }

    fileprivate static func methodProxy(
        access: String,
        name _: String,
        scope: String,
        event: String,
        fields: [EventField],
    ) -> String {
        var parameters = fields.map { "        \($0.name): \($0.parameterType)" }
        parameters.append("        attachments: [LogAttachment] = []")
        parameters.append("        function: StaticString = #function")
        parameters.append("        fileID: StaticString = #fileID")
        let arguments = fields.map { "                \($0.name): \($0.name)" }
            .joined(separator: ",\n")
        let eventInit = fields.isEmpty ? "\(scope).\(event)()" : """
        \(scope).\(event)(
        \(arguments)
                    )
        """
        return """
        \(access)struct \(event)LogMethod {
            fileprivate let log: Log<\(scope)>

            \(access)func callAsFunction(
        \(parameters.joined(separator: ",\n"))
            ) {
                log.record(
                    \(eventInit),
                    attachments: attachments,
                    function: function,
                    fileID: fileID
                )
            }
        }
        """
    }
}
