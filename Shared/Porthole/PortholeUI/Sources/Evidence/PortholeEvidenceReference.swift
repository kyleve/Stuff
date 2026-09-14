import Foundation
import PortholeCore

/// Only structured runtime values become links; arbitrary text and identifiers stay text.
enum PortholeEvidenceReference: Equatable {
    struct Source: Equatable {
        let scope: PortholeScopeToken
        let path: String
        let line: Int
        let sha256: String
    }

    case object(PortholeObjectReference)
    case context(PortholeContext)
    case contextLink(PortholeContextLink, scope: PortholeScopeToken)
    case source(Source)
    case savedSource(PortholeSourceFile)
    case sourceLocation(PortholeSourceLocation, scope: PortholeScopeToken)

    var title: String {
        switch self {
            case let .object(reference): "Object: \(reference.typeName)"
            case let .context(context): "Context: \(context.title)"
            case let .contextLink(link, _): "Context: \(link.label)"
            case let .source(source): "Source: \(source.path):\(source.line)"
            case let .savedSource(file): "Saved source: \(file.path)"
            case let .sourceLocation(location, _): "Source: \(location.path):\(location.line)"
        }
    }

    struct Link: Identifiable, Equatable {
        struct ID: Hashable { let path: String }
        let id: ID
        let reference: PortholeEvidenceReference
    }

    struct Scan: Equatable {
        var links: [Link] = []
        var issues: [String] = []
        var truncated = false
    }

    static func scan(_ value: PortholeValue) -> Scan {
        var result = Scan()
        var visited = 0
        visit(value, path: "$", depth: 0, visited: &visited, result: &result)
        return result
    }

    private static func visit(
        _ value: PortholeValue,
        path: String,
        depth: Int,
        visited: inout Int,
        result: inout Scan,
    ) {
        guard visited < 512, result.links.count < 64 else { result.truncated = true; return }
        visited += 1
        guard depth < 16 else { result.truncated = true; return }
        do {
            if let reference = try recognize(value) {
                result.links.append(Link(id: .init(path: path), reference: reference))
                return
            }
        } catch { result.issues.append("\(path): invalid evidence reference (\(error))"); return }
        switch value {
            case let .object(values):
                for key in values.keys.sorted() {
                    guard visited < 512,
                          result.links.count < 64 else { result.truncated = true; break }
                    if let child = values[key] { visit(
                        child,
                        path: "\(path)[\(key.debugDescription)]",
                        depth: depth + 1,
                        visited: &visited,
                        result: &result,
                    ) }
                }
            case let .array(values):
                for (index, child) in values.enumerated() {
                    guard visited < 512,
                          result.links.count < 64 else { result.truncated = true; break }
                    visit(
                        child,
                        path: "\(path)[\(index)]",
                        depth: depth + 1,
                        visited: &visited,
                        result: &result,
                    )
                }
            case .null, .bool, .integer, .unsignedInteger, .number, .string: break
        }
    }

    private static func recognize(_ value: PortholeValue) throws -> Self? {
        guard case let .object(fields) = value else { return nil }
        if let encoded = fields["$reference"] {
            return try .object(encoded.decode(PortholeObjectReference.self))
        }
        if fields["typeName"] != nil, fields["scope"] != nil, fields["id"] != nil {
            return try .object(value.decode(PortholeObjectReference.self))
        }
        if fields["capturedAt"] != nil, fields["values"] != nil, fields["scope"] != nil,
           fields["title"] != nil
        {
            return try .context(value.decode(PortholeContext.self))
        }
        if fields["content"] != nil, fields["path"] != nil, fields["sha256"] != nil {
            let file = try value.decode(PortholeSourceFile.self)
            guard file.hasValidHash
            else {
                throw PortholeError
                    .invalidArguments("Saved source hash does not match its content")
            }
            return .savedSource(file)
        }
        if let hash = fields["sha256"]?.stringValue, let path = fields["path"]?.stringValue,
           let scope = fields["scope"], let encodedLine = fields["line"] ?? fields["firstLine"]
        {
            guard case let .integer(line) = encodedLine, line > 0, line <= Int.max,
                  hash.count == 64, hash.allSatisfy({ $0.isHexDigit && $0.isASCII })
            else {
                throw PortholeError
                    .invalidArguments("Source evidence needs a positive line and SHA-256")
            }
            return try .source(Source(
                scope: scope.decode(PortholeScopeToken.self),
                path: path,
                line: Int(line),
                sha256: hash.lowercased(),
            ))
        }
        return nil
    }
}
