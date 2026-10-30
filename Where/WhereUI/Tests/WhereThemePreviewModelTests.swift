import Foundation
import Testing
import ViewDocumentCore
import ViewDocumentUI
@testable import WhereUI

@MainActor
struct WhereThemePreviewModelTests {
    @Test func rejectedImportsKeepTheAcceptedThemeAndCatalog() throws {
        let model = try WhereThemePreviewModel.bundled()
        model.select(.halloween)
        let original = try #require(model.theme?.validated)
        model.importTheme(Data("invalid JSON".utf8))
        #expect(model.failure != nil)
        #expect(model.theme?.validated == original)
        var invalid = original.document
        invalid.parent = invalid.id
        try model.importTheme(JSONEncoder().encode(invalid))
        #expect(model.failure != nil)
        #expect(model.theme?.validated == original)
        var missingAsset = original.document
        missingAsset.components.regularCard?.artwork?[0].document.root.content = .raster(.init(
            asset: .init(rawValue: "not-bundled"),
            sizing: .fit,
        ))
        try model.importTheme(JSONEncoder().encode(missingAsset))
        #expect(model.failure != nil)
        #expect(model.theme?.validated == original)
        model.select(.halloween)
        #expect(model.failure == nil)
        #expect(model.theme?.validated == original)
    }

    @Test func sameIdentityUpdatesReplaceContentAndClearReturnsToSavedTheme() throws {
        let model = try WhereThemePreviewModel.bundled()
        model.select(.halloween)
        var updated = try #require(model.theme?.validated.document)
        updated.appearance.card?.regular?.cornerRadius = .constant(35)
        try model.importTheme(JSONEncoder().encode(updated))
        #expect(model.failure == nil)
        #expect(model.theme?.resolved.id == .halloween)
        #expect(model.theme?.resolved.appearance.card?.regular?.cornerRadius == .constant(35))
        model.clear()
        #expect(model.theme == nil)
        #expect(model.failure == nil)
        model.select(.halloween)
        #expect(model.theme?.resolved.appearance.card?.regular?.cornerRadius == .constant(35))
    }
}
