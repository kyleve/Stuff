import Foundation
import SwiftParser
import SwiftSyntax

private final class LayoutVisitor: SyntaxVisitor {
    let locations: SourceLocationConverter
    var hasViolations = false

    init(file: String, tree: SourceFileSyntax) {
        locations = SourceLocationConverter(fileName: file, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let members = node.memberBlock
        let openingLine = members.leftBrace.startLocation(converter: locations).line
        let closingLine = members.rightBrace.startLocation(converter: locations).line
        for member in members.members where member.decl.is(EnumCaseDeclSyntax.self) {
            if member.startLocation(converter: locations).line == openingLine
                || member.endLocation(converter: locations).line == closingLine
            {
                report(member, "Place enum cases on separate lines inside the braces.")
            }
        }
        return .visitChildren
    }

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        // SwiftFormat preserves grouped cases when a modifier or attribute applies to all of them.
        for (previous, next) in zip(node.elements, node.elements.dropFirst()) {
            if previous.endLocation(converter: locations).line == next
                .startLocation(converter: locations).line
            {
                report(
                    next,
                    "Split grouped enum cases and repeat any shared modifiers or attributes.",
                )
                break
            }
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression
        if isObservableHost(callee), node.arguments.count == 1,
           let factory = node.arguments.first, factory.label == nil,
           factory.expression.is(ClosureExprSyntax.self), node.trailingClosure != nil
        {
            report(callee, "Use a trailing factory closure followed by content: { … }.")
        }
        return .visitChildren
    }

    private func isObservableHost(_ callee: ExprSyntax) -> Bool {
        if let specialized = callee.as(GenericSpecializationExprSyntax.self) {
            return isObservableHost(specialized.expression)
        }
        if let member = callee.as(MemberAccessExprSyntax.self) {
            if member.declName.baseName.text == "init", let base = member.base {
                return isObservableHost(base)
            }
            return member.declName.baseName.text == "ObservableHostingView"
        }
        return callee.as(DeclReferenceExprSyntax.self)?.baseName.text == "ObservableHostingView"
    }

    private func report(_ node: some SyntaxProtocol, _ message: String) {
        let location = node.startLocation(converter: locations)
        print("\(location.file):\(location.line):\(location.column): error: \(message)")
        hasViolations = true
    }
}

var failed = false
let paths = FileHandle.standardInput.readDataToEndOfFile().split(separator: 0)
for bytes in paths {
    let path = String(decoding: bytes, as: UTF8.self)
    let source = try String(contentsOfFile: path, encoding: .utf8)
    let tree = Parser.parse(source: source)
    let visitor = LayoutVisitor(file: path, tree: tree)
    visitor.walk(tree)
    failed = failed || visitor.hasViolations
}

exit(failed ? 1 : 0)
