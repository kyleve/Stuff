import SwiftSyntax

struct EventField {
    let name: String
    let type: String
    let key: String
    let exposure: String
    let kind: String
    let isOptional: Bool

    var policyType: String {
        exposure == "shareable" ? "Shared" : "Restricted"
    }

    var kindType: String {
        switch kind {
            case "boolean": "Boolean"
            case "count": "Count"
            case "limit": "Limit"
            case "duration": "Duration"
            case "category": "Category"
            case "json": "JSON"
            case "pii": "PII"
            case "identifier": "Identifier"
            case "location": "Location"
            case "userContent": "UserContent"
            case "errorDetails": "ErrorDetails"
            case "dateTime": "DateTime"
            case "pathOrURL": "PathOrURL"
            case "arbitraryText": "ArbitraryText"
            case "domainValue": "DomainValue"
            case "technicalState": "TechnicalState"
            default: "TechnicalState"
        }
    }

    var parameterType: String {
        "ClassifiedLogInput<LogFieldPolicy.\(policyType), LogFieldPolicy.\(kindType), \(type)>"
    }
}

func argumentList(of attribute: AttributeSyntax) -> LabeledExprListSyntax? {
    guard case let .argumentList(arguments) = attribute.arguments else { return nil }
    return arguments
}

func plainString(from expression: ExprSyntax) -> String? {
    guard let literal = expression.as(StringLiteralExprSyntax.self),
          literal.segments.count == 1,
          let segment = literal.segments.first?.as(StringSegmentSyntax.self)
    else {
        return nil
    }
    return segment.content.text
}

func plainInteger(from expression: ExprSyntax) -> Int? {
    guard let literal = expression.as(IntegerLiteralExprSyntax.self) else { return nil }
    return Int(literal.literal.text)
}

func memberName(from expression: ExprSyntax) -> String? {
    expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
}

func attribute(named name: String, in attributes: AttributeListSyntax) -> AttributeSyntax? {
    attributes.compactMap { element -> AttributeSyntax? in
        guard case let .attribute(attribute) = element else { return nil }
        let attributeName = attribute.attributeName.trimmedDescription
        return attributeName == name || attributeName.hasSuffix(".\(name)") ? attribute : nil
    }.first
}

func accessPrefix(_ modifiers: DeclModifierListSyntax) -> String {
    modifiers.contains { $0.name.tokenKind == .keyword(.public) } ? "public " : ""
}

func lowerCamelCase(_ name: String) -> String {
    guard let first = name.first else { return name }
    let scalars = Array(name)
    var uppercasePrefix = 0
    while uppercasePrefix < scalars.count, scalars[uppercasePrefix].isUppercase {
        uppercasePrefix += 1
    }
    if uppercasePrefix <= 1 {
        return first.lowercased() + name.dropFirst()
    }
    let acronymEnd = uppercasePrefix == scalars.count ? uppercasePrefix : uppercasePrefix - 1
    return String(scalars[..<acronymEnd]).lowercased() + String(scalars[acronymEnd...])
}

func escapedStringLiteral(_ value: String) -> String {
    var result = ""
    for character in value {
        switch character {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default: result.append(character)
        }
    }
    return result
}

extension AccessorBlockSyntax {
    var hasObservers: Bool {
        guard case let .accessors(accessors) = accessors else { return false }
        return accessors.contains { accessor in
            let name = accessor.accessorSpecifier.text
            return name == "willSet" || name == "didSet"
        }
    }
}
