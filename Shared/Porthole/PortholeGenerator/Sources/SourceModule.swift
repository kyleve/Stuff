import CryptoKit
import Foundation

/// The generator's source inventory. This is build metadata, never a live object graph.
struct SourceModule: Codable {
    struct BuildMetadata: Codable {
        let configuration: String
        let toolchain: String
    }

    let name: String
    let files: [SourceFile]
    let declarations: [SourceDeclaration]
    let build: BuildMetadata
}

struct SourceFile: Codable {
    let path: String
    let content: String
    let sha256: String

    init(path: String, content: String) {
        self.path = path
        self.content = content
        sha256 = SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// One declaration and the source facts needed to generate a checked call site.
struct SourceDeclaration: Codable {
    enum Kind: String, Codable {
        case type, function, initializer, property, propertySetter, enumerationCase,
             enumerationInspection, typeAlias,
             subscriptDeclaration, deinitializer, typeExtension
    }

    struct Parameter: Codable {
        /// The label used by the native Swift call.
        let label: String
        /// The unique key used by generated argument forms and invocation values.
        let name: String
        let type: String
        let defaultValue: String?
    }

    let declarationID: String
    let name: String
    let owner: String?
    let kind: Kind
    let signature: String
    let file: String
    let line: Int
    let documentation: String
    let access: String
    let conditions: [String]
    let attributes: [String]
    let parameters: [Parameter]
    let resultType: String?
    let isStatic: Bool
    let isAsync: Bool
    let isThrowing: Bool
    let isMutable: Bool
    let isStoredProperty: Bool
    let isActor: Bool
    let isMainActor: Bool
    let isNonisolated: Bool
    let isReferenceType: Bool
    let isProtocol: Bool
    let conformances: [String]
    let unsupportedReason: String?
}

enum GeneratorError: Error, CustomStringConvertible {
    case arguments(String)
    case invalidSource(path: String)
    case collision(name: String, files: [String])

    var description: String {
        switch self {
            case let .arguments(message): message
            case let .invalidSource(path): "Swift syntax errors in \(path)"
            case let .collision(name, files):
                "Private access generation cannot disambiguate '\(name)' in \(files.joined(separator: ", ")). Rename the colliding declarations before enabling Porthole for this module."
        }
    }
}
