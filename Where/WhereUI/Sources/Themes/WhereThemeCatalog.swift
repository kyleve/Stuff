import BroadwayCore
import BroadwayUI
import Foundation
import ViewDocumentCore
import ViewDocumentUI

/// Resolves a supplied, finite set of themes before any document reaches a view hierarchy.
public struct WhereThemeCatalog {
    private let documents: [WhereThemeDocument.ID: WhereThemeDocument]

    public init(documents: [WhereThemeDocument]) throws {
        guard documents.count <= 64, Set(documents.map(\.id)).count == documents.count else {
            throw WhereThemeValidationError(
                path: "catalog",
                reason: "Duplicate theme identities or too many documents",
            )
        }
        var totalBytes = 0
        for document in documents {
            guard document.schemaVersion == 1 || document.schemaVersion == 2 else {
                throw WhereThemeValidationError(
                    path: "schemaVersion",
                    reason: "Unsupported theme schema version",
                )
            }
            guard !document.id.rawValue.isEmpty, document.id.rawValue.utf8.count <= 128 else {
                throw WhereThemeValidationError(path: "id", reason: "Invalid theme identity")
            }
            let bytes = try JSONEncoder().encode(document).count
            guard bytes <= ViewDocumentLimits.standard.bytes else { throw WhereThemeValidationError(
                path: "$",
                reason: "Theme exceeds byte limit",
            ) }
            totalBytes += bytes
        }
        guard totalBytes <= 4 * ViewDocumentLimits.standard.bytes
        else { throw WhereThemeValidationError(
            path: "catalog",
            reason: "Catalog exceeds byte limit",
        ) }
        self.documents = try Dictionary(uniqueKeysWithValues: documents.map { try (
            $0.id,
            $0.converted()
        ) })
    }

    public func replacing(_ document: WhereThemeDocument) throws -> Self {
        try .init(documents: documents.values.filter { $0.id != document.id } + [document])
    }

    public func resolve(_ id: WhereThemeDocument.ID) throws -> ResolvedWhereTheme {
        var chain: [WhereThemeDocument] = []
        var visited: Set<WhereThemeDocument.ID> = []
        var next: WhereThemeDocument.ID? = id
        while let current = next {
            guard visited.insert(current).inserted, chain.count < 16 else {
                throw WhereThemeValidationError(
                    path: "parent",
                    reason: "Theme inheritance cycle or excessive depth",
                )
            }
            guard let document = documents[current] else {
                throw WhereThemeValidationError(
                    path: "parent",
                    reason: "Missing theme \(current.rawValue)",
                )
            }
            chain.append(document)
            next = document.parent
        }
        var parent: ResolvedWhereTheme?
        for document in chain.reversed() {
            parent = try resolve(document, parent: parent)
        }
        guard let parent
        else { throw WhereThemeValidationError(path: "id", reason: "Missing theme") }
        return parent
    }

    private func resolve(
        _ document: WhereThemeDocument,
        parent: ResolvedWhereTheme?,
    ) throws -> ResolvedWhereTheme {
        let id = document.id
        let values = try document.values.inheriting(parent?.values)
        let components = try document.components.assigningLiteralOwnership(document.appearance)
            .inheriting(parent?.components)
        var appearance = document.appearance.inheriting(parent?.appearance)
        appearance = try components.applyingReferences(to: appearance, values: values)
        try appearance.requireComplete(path: "appearance")
        try components.requireComplete(path: "components")
        try components.validateCapabilities()
        // Validate every named value, including values not used by the selected components.
        for mode: BMode in [.light, .dark] {
            var traits = BTraits()
            traits.mode = mode
            let rendererAppearance = BViewDocumentStylesheet(traits: traits).appearance
            for entry in values.colors ?? [] {
                try WhereThemeValidation.validate(
                    entry.value.resolve(mode: mode),
                    path: "values.colors.\(entry.id.rawValue)",
                )
            }
            for entry in values.fonts ?? [] {
                try WhereThemeValidation.validate(
                    entry.value.resolve(mode: mode),
                    path: "values.fonts.\(entry.id.rawValue)",
                )
            }
            for entry in values.surfaces ?? [] {
                _ = try values.surface(entry.id).resolve(mode: mode).resolve(
                    mode: mode,
                    appearance: rendererAppearance,
                    base: .reflective,
                )
            }
            var sheet = WhereStylesheet()
            try appearance.apply(
                to: &sheet,
                traits: traits,
                appearance: rendererAppearance,
                path: "appearance",
            )
        }
        return .init(
            id: id,
            values: values,
            appearance: appearance,
            components: components,
            fallback: id == .flat ? .flat : parent?.fallback ?? .standard,
        )
    }

    @MainActor
    public func prepare(
        _ id: WhereThemeDocument.ID,
        assets: ViewDocumentAssets,
    ) throws -> PreparedWhereThemeDocument {
        guard let document = documents[id] else { throw WhereThemeValidationError(
            path: "id",
            reason: "Missing theme",
        ) }
        let validated = try ValidatedWhereThemeDocument(
            document: document,
            resolved: resolve(id),
            resources: assets.resources,
        )
        return try PreparedWhereThemeDocument(validated: validated, assets: assets)
    }
}
