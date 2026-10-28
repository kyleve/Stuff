@testable import Flyover
import SwiftUI
import Testing

@MainActor
struct FlyoverModelTests {
    @Test func resetRestoresFirstVariantAndRunsScreenReset() {
        var resetCount = 0
        let screen = FlyoverScreen(
            id: FlyoverTestScreen.root,
            title: "Root",
            variants: [
                variant(id: "first"),
                variant(id: "second"),
            ],
            reset: {
                resetCount += 1
            },
        )
        let catalog = FlyoverCatalog(
            groups: [
                FlyoverGroup(
                    id: FlyoverGroupID("main"),
                    title: "Main",
                    root: .root,
                    screens: [screen],
                ),
            ],
        )
        let model = FlyoverModel(catalog: catalog)
        let state = model.state(for: screen)
        state.variantID = FlyoverVariantID("second")

        model.reset(screen)

        #expect(state.variantID == FlyoverVariantID("first"))
        #expect(state.generation == 1)
        #expect(resetCount == 1)
    }

    @Test func orientationSwapsDeviceDimensions() {
        let model = FlyoverModel(catalog: makeFlyoverTestCatalog())

        model.device = .phone
        model.orientation = .portrait
        #expect(model.viewportSize == CGSize(width: 402, height: 874))

        model.orientation = .landscape
        #expect(model.viewportSize == CGSize(width: 874, height: 402))
    }

    @Test func previewSelectionKeepsOnlyOneCanvasScreenLive() throws {
        let catalog = makeFlyoverTestCatalog()
        let root = try #require(catalog.screen(id: .root))
        let pushed = try #require(catalog.screen(id: .pushed))
        let model = FlyoverModel(catalog: catalog)

        model.preview(root)
        #expect(model.previewedScreenID == .root)

        model.preview(pushed)
        #expect(model.previewedScreenID == .pushed)

        model.pausePreview()
        #expect(model.previewedScreenID == nil)
    }

    @Test func invalidDuplicateScreenCatalogCanCreateDiagnosticModel() {
        let first = FlyoverScreen(
            id: FlyoverTestScreen.root,
            title: "First",
            variants: [variant(id: "first")],
        )
        let second = FlyoverScreen(
            id: FlyoverTestScreen.root,
            title: "Second",
            variants: [variant(id: "second")],
        )
        let catalog = FlyoverCatalog(
            groups: [
                FlyoverGroup(
                    id: FlyoverGroupID("first"),
                    title: "First",
                    root: .root,
                    screens: [first],
                ),
                FlyoverGroup(
                    id: FlyoverGroupID("second"),
                    title: "Second",
                    root: .root,
                    screens: [second],
                ),
            ],
        )

        let model = FlyoverModel(catalog: catalog)

        #expect(catalog.isValid == false)
        #expect(model.state(for: first).variantID == FlyoverVariantID("first"))
    }

    @Test func initialCanvasZoomIsAppliedOnlyOnce() {
        let model = FlyoverModel(catalog: makeFlyoverTestCatalog())

        model.applyInitialCanvasZoom(0.7)
        model.zoom = 0.95
        model.applyInitialCanvasZoom(0.2)

        #expect(model.zoom == 0.95)
    }

    private func variant(id: String) -> FlyoverVariant {
        FlyoverVariant(id: FlyoverVariantID(id), title: id) {
            EmptyView()
        }
    }
}
