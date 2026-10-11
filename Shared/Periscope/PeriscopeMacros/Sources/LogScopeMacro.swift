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
        if let spanName = scope.memberBlock.members.first(where: { member in
            if let declaration = member.decl.as(EnumDeclSyntax.self) {
                return declaration.name.text == "SpanName"
            }
            if let declaration = member.decl.as(StructDeclSyntax.self) {
                return declaration.name.text == "SpanName"
            }
            if let declaration = member.decl.as(ClassDeclSyntax.self) {
                return declaration.name.text == "SpanName"
            }
            if let declaration = member.decl.as(ActorDeclSyntax.self) {
                return declaration.name.text == "SpanName"
            }
            if let declaration = member.decl.as(TypeAliasDeclSyntax.self) {
                return declaration.name.text == "SpanName"
            }
            return false
        }), !spanName.decl.is(EnumDeclSyntax.self) {
            context.diagnose(
                spanName.decl,
                id: "scope-span-name",
                message: "SpanName must be a Hashable and Sendable enum",
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
        members.append(DeclSyntax(stringLiteral: """
        \(access)static func makeLogMethods(_ log: PeriscopeCore.Log<\(scope.name
            .text)>) -> LogMethods {
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
        let extensionDecl: DeclSyntax = "extension \(type.trimmed): PeriscopeCore.LogScopeDefinition {}"
        return [extensionDecl.cast(ExtensionDeclSyntax.self)]
    }
}

extension LogScopeMacro {
    /// Dynamic-member lookup cannot shadow Log's existing instance API.
    /// Keep this set aligned with Log and its public extensions.
    private static let reservedMethodNames: Set<String> = [
        "log",
        "debug",
        "info",
        "notice",
        "warning",
        "error",
        "fault",
        "scopes",
        "tags",
        "primaryScope",
        "context",
        "callAsFunction",
        "linked",
        "retyped",
        "tagged",
        "record",
        "withContext",
        "measure",
        "begin",
        "end",
    ]

    fileprivate struct EventMethod {
        let access: String
        let name: String
        let event: String
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
            if reservedMethodNames.contains(methodName) {
                context.diagnose(
                    event,
                    id: "reserved-method",
                    message: "generated log method '\(methodName)' conflicts with a reserved logger member",
                )
                continue
            }
            if !seenMethods.insert(methodName).inserted {
                context.diagnose(
                    event,
                    id: "duplicate-method",
                    message: "generated log method '\(methodName)' is duplicated",
                )
                continue
            }
            let parsed = LogEventMacro.parseFields(event)
            guard !parsed.hasError else { continue }
            let eventAccess = accessPrefix(event.modifiers)
            let access = scopeAccess == "public " && eventAccess == "public " ? "public " : ""
            methods.append(EventMethod(
                access: access,
                name: methodName,
                event: event.name.text,
            ))
        }
        return methods
    }
}

extension LogScopeMacro {
    fileprivate static func methodsContainer(
        access: String,
        scope: String,
        events: [EventMethod],
    ) -> String {
        let properties = events.map { event in
            "    \(event.access)var `\(event.name)`: \(event.event).LogMethod { \(event.event).LogMethod(log: log) }"
        }.joined(separator: "\n")
        return """
        \(access)struct LogMethods {
            fileprivate let log: PeriscopeCore.Log<\(scope)>

        \(properties)
        }
        """
    }

    static func methodProxy(
        access: String,
        scope: String,
        event: String,
        fields: [EventField],
    ) -> String {
        var parameters = fields.map { "        \($0.name): \($0.parameterType)" }
        parameters.append("        attachments: [PeriscopeCore.LogAttachment] = []")
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
        \(access)struct LogMethod {
            fileprivate let log: PeriscopeCore.Log<\(scope)>

            \(access)func callAsFunction(
        \(parameters.joined(separator: ",\n"))
            ) {
                self.log.record(
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
