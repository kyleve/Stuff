import SwiftUI
import Testing
import ViewDocumentCore
import ViewDocumentUI

@MainActor
struct ViewDocumentViewTests {
    @Test func rejectsAssetsThatDifferFromValidation() throws {
        let asset = ViewAssetID(rawValue: "artwork")
        let document = try ValidatedViewDocument(
            document: .init(schemaVersion: 1, root: .init(
                id: .init(rawValue: "root"),
                content: .image(asset),
                modifiers: [],
                animation: nil,
                accessibility: .label("Artwork"),
            )),
            resources: .init(images: [asset], symbols: []),
            limits: .standard,
        )
        #expect(throws: ViewDocumentView.ResourceError.self) {
            try ViewDocumentView(
                document: document,
                assets: .init(images: [:], symbols: [:]),
                appearance: .init(background: .white, dimensionScales: [:]),
                policy: .init(purpose: .content, isActive: true, motionIsStatic: true),
            )
        }
    }

    @Test func rendersStandaloneDocumentWithOrderedPadding() throws {
        let document = try ValidatedViewDocument(
            document: .init(schemaVersion: 1, root: .init(
                id: .init(rawValue: "root"),
                content: .shape(.rectangle),
                modifiers: [
                    .frame(width: .points(20), height: .points(10), alignment: .center),
                    .padding(.points(5)),
                ],
                animation: nil,
                accessibility: .hidden,
            )),
            resources: .init(images: [], symbols: []),
            limits: .standard,
        )
        let view = try ViewDocumentView(
            document: document,
            assets: .init(images: [:], symbols: [:]),
            appearance: .init(background: .white, dimensionScales: [:]),
            policy: .init(purpose: .content, isActive: true, motionIsStatic: true),
        )
        let renderer = ImageRenderer(content: view)
        let image = try #require(renderer.uiImage)
        #expect(image.size == CGSize(width: 30, height: 20))
    }
}
