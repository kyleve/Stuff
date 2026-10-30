import BroadwayCore
import BroadwayUI
import Foundation
import ViewDocumentCore

/// Immutable content accepted at the rendering boundary. Invalid input never enters the cache.
public struct ValidatedWhereThemeDocument: Hashable, Sendable {
    public let document: WhereThemeDocument
    let layers: [WhereThemeDocument.Slot: [ValidatedViewDocument]]

    @MainActor
    public init(document: WhereThemeDocument, resources: ViewDocumentResources) throws {
        guard document.schemaVersion == 1 else { throw WhereThemeValidationError(
            path: "schemaVersion",
            reason: "Unsupported theme schema version",
        ) }
        guard !document.id.rawValue.isEmpty,
              document.id.rawValue.utf8.count <= 128
        else { throw WhereThemeValidationError(
            path: "id",
            reason: "Invalid theme identity",
        ) }
        guard try JSONEncoder().encode(document).count <= ViewDocumentLimits.standard.bytes
        else { throw WhereThemeValidationError(
            path: "$",
            reason: "Theme exceeds byte limit",
        ) }
        // Validate every mode branch, not just the mode active at import time.
        for mode: BMode in [.light, .dark] {
            var traits = BTraits.system
            traits.mode = mode
            var sheet = BContext(
                traits: traits,
                themes: WhereThemes.current(theme: document.fallback.theme),
            ).stylesheet(WhereStylesheet.self, fallback: .default)
            try document.appearance.apply(
                to: &sheet,
                traits: traits,
                appearance: BViewDocumentStylesheet(traits: traits).appearance,
                path: "appearance",
            )
        }
        var validated: [WhereThemeDocument.Slot: [ValidatedViewDocument]] = [:]
        var budget = ThemeLayerBudget()
        for slot in WhereThemeDocument.Slot.allCases {
            let documents = document.layers[slot]
            guard documents.count <= 8 else { throw WhereThemeValidationError(
                path: "layers.\(slot.rawValue)",
                reason: "Too many layers",
            ) }
            guard Set(documents.map(\.root.id)).count == documents.count
            else { throw WhereThemeValidationError(
                path: "layers.\(slot.rawValue)",
                reason: "Duplicate layer identity",
            ) }
            validated[slot] = try documents.map { try ValidatedViewDocument(
                document: $0,
                resources: resources,
                limits: .standard,
            ) }
        }
        for documents in validated.values {
            for document in documents {
                budget.include(document.document.root)
            }
        }
        guard budget.nodes <= ViewDocumentLimits.standard.nodes,
              budget.animations <= ViewDocumentLimits.standard.animatedNodes,
              budget.modifiers <= ViewDocumentLimits.standard.modifiers
        else {
            throw WhereThemeValidationError(
                path: "layers",
                reason: "Combined theme layers exceed the rendering budget",
            )
        }
        self.document = document
        layers = validated
    }

    @MainActor
    public static func decode(_ data: Data, resources: ViewDocumentResources) throws -> Self {
        guard data.count <= ViewDocumentLimits.standard.bytes
        else { throw WhereThemeValidationError(
            path: "$",
            reason: "Theme exceeds byte limit",
        ) }
        return try Self(
            document: JSONDecoder().decode(WhereThemeDocument.self, from: data),
            resources: resources,
        )
    }
}

struct WhereDocumentTheme: BTheme {
    var document: ValidatedWhereThemeDocument?
    static let defaultValue = Self(document: nil)
}

private struct ThemeLayerBudget {
    var nodes = 0
    var animations = 0
    var modifiers = 0
    mutating func include(_ node: ViewDocument.Node) {
        nodes += 1
        modifiers += node.modifiers.count
        if node.animation != nil { animations += 1 }
        switch node.content {
            case let .group(_, _, _, children):
                for child in children {
                    include(child)
                }
            case .text, .image, .symbol, .shape, .spacer: break
        }
    }
}
