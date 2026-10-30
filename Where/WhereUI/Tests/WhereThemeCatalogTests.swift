import BroadwayCore
import Foundation
import Testing
import ViewDocumentCore
import ViewDocumentUI
@testable import WhereUI

@MainActor
struct WhereThemeCatalogTests {
    @Test nonisolated func maximumParentDepthResolvesOnAWorkerThread() async throws {
        try await Task.detached {
            let root = try WhereBundledThemeDefinitions.load("StandardTheme")
            var documents = [root]
            for index in 1 ... 15 {
                documents.append(.init(
                    id: .init(rawValue: "child-\(index)"),
                    parent: documents.last!.id,
                    values: .init(colors: nil, fonts: nil, surfaces: nil),
                    appearance: .init(),
                    components: .init(),
                ))
            }
            let catalog = try WhereThemeCatalog(documents: documents)
            let resolved = try catalog.resolve(documents.last!.id)
            #expect(resolved.appearance.card?.regular?.padding == root.appearance.card?.regular?
                .padding)
            documents.append(.init(
                id: .init(rawValue: "too-deep"),
                parent: documents.last!.id,
                values: .init(colors: nil, fonts: nil, surfaces: nil),
                appearance: .init(),
                components: .init(),
            ))
            #expect(throws: WhereThemeValidationError.self) {
                try WhereThemeCatalog(documents: documents).resolve(.init(rawValue: "too-deep"))
            }
        }.value
    }

    @Test func bundledRootsAreCompleteAndFlatInheritsGeometry() throws {
        let catalog = try WhereBundledThemes.catalog()
        let standard = try catalog.resolve(.init(rawValue: "standard"))
        let flat = try catalog.resolve(.init(rawValue: "flat"))
        try standard.appearance.requireComplete(path: "appearance")
        try flat.appearance.requireComplete(path: "appearance")
        #expect(standard.appearance.card?.regular?.padding == flat.appearance.card?.regular?
            .padding)
        #expect(standard.appearance.card?.regular?.surface != flat.appearance.card?.regular?
            .surface)
        #expect(flat.fallback == .flat)
    }

    @Test func rejectsIncompleteRootsMissingParentsAndCycles() throws {
        let root = child("root", parent: nil)
        #expect(throws: WhereThemeValidationError.self) {
            try WhereThemeCatalog(documents: [root]).resolve(root.id)
        }
        let missing = child("missing", parent: "absent")
        #expect(throws: WhereThemeValidationError.self) {
            try WhereThemeCatalog(documents: [missing]).resolve(missing.id)
        }
        let first = child("first", parent: "second"), second = child("second", parent: "first")
        #expect(throws: WhereThemeValidationError.self) { try WhereThemeCatalog(documents: [
            first,
            second,
        ]).resolve(first.id) }
    }

    @Test func artworkReplacesAsAUnitAndEmptyRemovesIt() throws {
        var parent = child("parent", parent: "flat")
        parent.components.regularCard = .init()
        parent.components.regularCard?.artwork = [artwork()]
        var child = child("child", parent: "parent")
        child.components.regularCard = .init()
        child.components.regularCard?.artwork = []
        child.components.regularCard?.nativeArtwork = []
        let catalog = try WhereThemeCatalog(documents: WhereBundledThemes.documents.get() + [
            parent,
            child,
        ])
        #expect(try catalog.resolve(parent.id).components.regularCard?.artwork?.count == 1)
        #expect(try catalog.resolve(child.id).components.regularCard?.artwork == [])
        #expect(try catalog.resolve(child.id).components.regularCard?.nativeArtwork == [])
    }

    @Test func missingReferencesAndAssetsFailBeforeInjection() throws {
        var document = child("invalid", parent: "flat")
        document.components.regularCard = .init()
        document.components.regularCard?.surface = .value(.init(rawValue: "missing"))
        #expect(throws: WhereThemeValidationError.self) {
            try WhereThemeCatalog(documents: WhereBundledThemes.documents.get() + [document])
                .resolve(document.id)
        }
        document.components.regularCard?.surface = nil
        document.components.regularCard?.artwork = [artwork()]
        let catalog = try WhereThemeCatalog(documents: WhereBundledThemes.documents
            .get() + [document])
        #expect(throws: ViewDocumentValidationError.self) {
            try catalog.prepare(document.id, assets: .init(images: [:], symbols: [:]))
        }
    }

    @Test func sameIdentityWithChangedContentProducesANewSlice() throws {
        var first = child("same", parent: "standard")
        first.appearance.card = .init()
        first.appearance.card?.regular = .init()
        first.appearance.card?.regular?.cornerRadius = .constant(18)
        var second = first
        second.appearance.card?.regular?.cornerRadius = .constant(40)
        let a = try resolveTheme(first, traits: .system)
        let b = try resolveTheme(second, traits: .system)
        #expect(a.card.regular.cornerRadius == 18)
        #expect(b.card.regular.cornerRadius == 40)
    }

    @Test func explicitRemovalSurvivesEncodingAndInheritance() throws {
        var document = child("removed", parent: "flat")
        document.appearance.card = .init()
        document.appearance.card?.regular = .init()
        document.appearance.card?.regular?.regionShape = .clear
        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(WhereThemeDocument.self, from: encoded)
        let result = try WhereThemeCatalog(documents: WhereBundledThemes.documents
            .get() + [decoded]).resolve(decoded.id)
        #expect(result.appearance.card?.regular?.regionShape == .clear)
        #expect(result.appearance.card?.compact?.regionShape != .clear)
    }

    private func child(_ name: String, parent: String?) -> WhereThemeDocument {
        .init(
            id: .init(rawValue: name),
            parent: parent.map { .init(rawValue: $0) },
            values: .init(colors: nil, fonts: nil, surfaces: nil),
            appearance: .init(),
            components: .init(),
        )
    }

    private func artwork() -> WhereThemeArtwork {
        .init(
            id: .init(rawValue: "art"),
            document: .init(
                schemaVersion: 1,
                root: .init(
                    id: .init(rawValue: "image"),
                    content: .raster(.init(asset: .init(rawValue: "missing-image"), sizing: .fit)),
                    modifiers: [],
                    animation: nil,
                    accessibility: .hidden,
                ),
            ),
            placement: .init(
                anchor: .bottomTrailing,
                size: .fixed(width: 80, height: 60),
                offset: .zero,
                plane: .exterior,
                outsets: .init(top: 0, leading: 0, bottom: 20, trailing: 20),
            ),
            role: .ornament,
            opacity: .constant(1),
        )
    }
}
