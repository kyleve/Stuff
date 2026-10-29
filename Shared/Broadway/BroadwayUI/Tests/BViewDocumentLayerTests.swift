import BroadwayCore
import BroadwayUI
import SwiftUI
import Testing
import ViewDocumentCore
import ViewDocumentUI

@MainActor
struct BViewDocumentLayerTests {
    @Test func contentChangeWithSameNodeIdentityInvalidatesSlice() {
        var context = BContext(traits: .system)
        let first = context.stylesheet(
            DocumentSheet.self,
            fallback: .init(document: DocumentTheme.defaultValue.document),
        )
        var changed = first.document
        changed.root.content = .text("Updated")
        context.themes[DocumentTheme.self] = .init(document: changed)
        let second = context.stylesheet(DocumentSheet.self, fallback: first)
        #expect(second.document.root.id == first.document.root.id)
        #expect(second.document.root.content == .text("Updated"))
        #expect(second != first)
    }

    @Test func decorationsCannotExpandHostLayout() throws {
        let validated = try ValidatedViewDocument(
            document: .init(schemaVersion: 1, root: .init(
                id: .init(rawValue: "oversized"),
                content: .shape(.rectangle),
                modifiers: [.frame(
                    width: .points(1000),
                    height: .points(1000),
                    alignment: .center,
                )],
                animation: nil,
                accessibility: .label("Must stay decorative"),
            )),
            resources: .init(images: [], symbols: []),
            limits: .standard,
        )
        let document = try PreparedViewDocument(
            document: validated,
            assets: .init(images: [:], symbols: [:]),
        )
        let view = Color.white.frame(width: 40, height: 30)
            .bViewDocumentBackground(document, isActive: true, motionIsStatic: true)
            .bViewDocumentOverlay(document, isActive: true, motionIsStatic: true)
            .broadwayRoot()
        let image = try #require(ImageRenderer(content: view).uiImage)
        #expect(image.size == CGSize(width: 40, height: 30))
    }
}

private struct DocumentTheme: BTheme {
    var document: ViewDocument
    static let defaultValue = Self(document: .init(schemaVersion: 1, root: .init(
        id: .init(rawValue: "stable"),
        content: .text("Original"),
        modifiers: [],
        animation: nil,
        accessibility: .automatic,
    )))
}

private struct DocumentSheet: BStylesheet {
    let document: ViewDocument
    init(document: ViewDocument) {
        self.document = document
    }

    init(context: SlicingContext) {
        document = context.themes[DocumentTheme.self].document
    }
}
