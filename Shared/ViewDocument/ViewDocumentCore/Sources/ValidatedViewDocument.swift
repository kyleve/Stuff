import Foundation

/// Immutable proof that the document satisfies the vocabulary and resource contract.
public struct ValidatedViewDocument: Hashable, Sendable {
    public let document: ViewDocument
    public let resources: ViewDocumentResources

    public init(
        document: ViewDocument,
        resources: ViewDocumentResources,
        limits: ViewDocumentLimits,
    ) throws {
        guard limits.bytes > 0, limits.depth > 0, limits.nodes > 0, limits.animatedNodes >= 0,
              limits.modifiersPerNode >= 0, limits.modifiers >= 0
        else {
            throw ViewDocumentValidationError(path: "$", reason: "Invalid validation limits")
        }
        guard document.schemaVersion == 1 else {
            throw ViewDocumentValidationError(
                path: "$.schemaVersion",
                reason: "Unsupported schema version",
            )
        }
        var validator = ViewDocumentValidator(resources: resources, limits: limits)
        try validator.visit(document.root, path: "$.root", depth: 1, inheritedScaleAmplification: 1)
        guard try JSONEncoder().encode(document).count <= limits.bytes else {
            throw ViewDocumentValidationError(path: "$", reason: "Document exceeds byte limit")
        }
        self.document = document
        self.resources = .init(
            images: validator.referencedImages,
            symbols: validator.referencedSymbols,
        )
    }

    public static func decode(
        _ data: Data,
        resources: ViewDocumentResources,
        limits: ViewDocumentLimits,
    ) throws -> Self {
        guard data.count <= limits.bytes else {
            throw ViewDocumentValidationError(path: "$", reason: "Document exceeds byte limit")
        }
        do {
            let document = try JSONDecoder().decode(ViewDocument.self, from: data)
            return try Self(document: document, resources: resources, limits: limits)
        } catch let error as DecodingError {
            let context: DecodingError.Context
            switch error {
                case let .dataCorrupted(value), let .keyNotFound(_, value), let .typeMismatch(
                _,
                value,
            ), let .valueNotFound(_, value):
                    context = value
                @unknown default:
                    throw error
            }
            throw ViewDocumentValidationError(
                path: "$" + context.codingPath.map { "." + $0.stringValue }.joined(),
                reason: context.debugDescription,
            )
        }
    }
}
