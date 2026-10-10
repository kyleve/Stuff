import SwiftParser
import SwiftSyntax

/// Validated semantic kinds understood by the macro, independent of the runtime module.
enum EventFieldKind: String, CaseIterable {
    case boolean
    case count
    case limit
    case duration
    case category
    case json
    case pii
    case identifier
    case location
    case userContent
    case errorDetails
    case dateTime
    case pathOrURL
    case arbitraryText
    case domainValue
    case technicalState

    var policyType: String {
        switch self {
            case .boolean: "Boolean"
            case .count: "Count"
            case .limit: "Limit"
            case .duration: "Duration"
            case .category: "Category"
            case .json: "JSON"
            case .pii: "PII"
            case .identifier: "Identifier"
            case .location: "Location"
            case .userContent: "UserContent"
            case .errorDetails: "ErrorDetails"
            case .dateTime: "DateTime"
            case .pathOrURL: "PathOrURL"
            case .arbitraryText: "ArbitraryText"
            case .domainValue: "DomainValue"
            case .technicalState: "TechnicalState"
        }
    }

    var isShareable: Bool {
        switch self {
            case .boolean, .count, .limit, .duration, .category, .json: true
            case .pii, .identifier, .location, .userContent, .errorDetails,
                 .dateTime, .pathOrURL, .arbitraryText, .domainValue, .technicalState: false
        }
    }
}

struct EventField {
    let name: String
    let type: String
    let key: String
    let exposure: String
    let kind: EventFieldKind
    let isOptional: Bool
    var exportRequirements: String?

    var resolvedExportRequirements: String {
        if let exportRequirements {
            return "LogExportRequirements.diagnostic(requiring: []).constrained(by: \(exportRequirements))"
        }
        if exposure == "restricted", kind == .errorDetails,
           ["LogError", "LogError?"].contains(type)
        {
            return ".diagnostic(requiring: [])"
        }
        return ".classified(exposure: .\(exposure), kind: .\(kind))"
    }

    var policyType: String {
        exposure == "shareable" ? "Shared" : "Restricted"
    }

    var kindType: String {
        kind.policyType
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
    expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
}

func plainInteger(from expression: ExprSyntax) -> Int? {
    guard let literal = expression.as(IntegerLiteralExprSyntax.self) else { return nil }
    return Int(literal.literal.text)
}

/// Resolves an explicit literal or an ASCII property name. Invalid explicit keys never fall back.
func fieldKey(in arguments: LabeledExprListSyntax, propertyName: String) -> String? {
    if let explicit = arguments.first(where: { $0.label == nil }) {
        guard let key = plainString(from: explicit.expression), !key.isEmpty else { return nil }
        return key
    }
    let bytes = Array(propertyName.filter { $0 != "`" }.utf8)
    let uppercase: ClosedRange<UInt8> = 65 ... 90
    let lowercase: ClosedRange<UInt8> = 97 ... 122
    let digits: ClosedRange<UInt8> = 48 ... 57
    guard !bytes.isEmpty, bytes.allSatisfy({
        uppercase.contains($0) || lowercase.contains($0) || digits.contains($0) || $0 == 95
    }) else { return nil }
    var result: [UInt8] = []
    for (index, byte) in bytes.enumerated() {
        if uppercase.contains(byte) {
            if index > 0 {
                let previous = bytes[index - 1]
                let followsLowercaseOrDigit = lowercase.contains(previous) || digits
                    .contains(previous)
                let endsAcronym = uppercase.contains(previous)
                    && index + 1 < bytes.count && lowercase.contains(bytes[index + 1])
                if followsLowercaseOrDigit || endsAcronym { result.append(95) }
            }
            result.append(byte + 32)
        } else {
            result.append(byte)
        }
    }
    return String(decoding: result, as: UTF8.self)
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
        if let escape = [
            "\0": "\\0",
            "\\": "\\\\",
            "\"": "\\\"",
            "\n": "\\n",
            "\r": "\\r",
            "\t": "\\t",
        ][String(character)] {
            result += escape
            continue
        }
        result.append(character)
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
