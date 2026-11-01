import BroadwayCore
import BroadwayUI
import Foundation
import ViewDocumentCore

/// Immutable content accepted at the rendering boundary. Invalid input never enters the cache.
public struct ValidatedWhereThemeDocument: Hashable, Sendable {
    public let document: WhereThemeDocument

    public let resolved: ResolvedWhereTheme
    let artwork: [WhereThemeComponents.Role: [ValidatedViewDocument]]

    @MainActor
    public init(document: WhereThemeDocument, resources: ViewDocumentResources) throws {
        let bundled = try WhereBundledThemes.documents.get().filter { $0.id != document.id }
        let catalog = try WhereThemeCatalog(documents: bundled + [document])
        try self.init(
            document: document,
            resolved: catalog.resolve(document.id),
            resources: resources,
        )
    }

    @MainActor
    init(
        document: WhereThemeDocument,
        resolved: ResolvedWhereTheme,
        resources: ViewDocumentResources,
    ) throws {
        var budget = ThemeLayerBudget()
        var artwork: [WhereThemeComponents.Role: [ValidatedViewDocument]] = [:]
        for role in WhereThemeComponents.Role.allCases {
            let entries = resolved.components[role]?.artwork ?? []
            // Two version 1 slots can normalize into one component; retain their bounded capacity.
            guard entries.count <= 16, Set(entries.map(\.id)).count == entries.count else {
                throw WhereThemeValidationError(
                    path: "components.\(role).artwork",
                    reason: "Duplicate artwork identity or too many layers",
                )
            }
            artwork[role] = try entries.map { entry in
                try entry.placement.validate()
                for mode: BMode in [.light, .dark] {
                    try WhereThemeValidation.validate(
                        entry.opacity.resolve(mode: mode),
                        range: 0 ... 1,
                        path: "artwork.opacity",
                    )
                }
                let layer = try ValidatedViewDocument(
                    document: entry.document,
                    resources: resources,
                    limits: .standard,
                )
                budget.include(entry.document.root)
                return layer
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
        self.document = try document.converted()
        self.resolved = resolved
        self.artwork = artwork
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
            case .text, .image, .raster, .symbol, .shape, .spacer: break
        }
    }
}
