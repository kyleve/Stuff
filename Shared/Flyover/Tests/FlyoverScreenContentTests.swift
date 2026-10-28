@testable import Flyover
import SwiftUI
import Testing

@MainActor
struct FlyoverScreenContentTests {
    @Test func synchronousRenderingDoesNotBuildVariantContent() {
        var buildCount = 0
        let screen = FlyoverScreen(
            id: FlyoverTestScreen.root,
            title: "Root",
            variants: [
                FlyoverVariant(
                    id: FlyoverVariantID("expensive"),
                    title: "Expensive",
                ) {
                    buildCount += 1
                    return Color.red
                },
            ],
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
        let renderer = ImageRenderer(
            content: FlyoverScreenContent(
                screen: screen,
                model: FlyoverModel(catalog: catalog),
                isOverview: true,
            ),
        )
        renderer.proposedSize = ProposedViewSize(width: 300, height: 650)

        _ = renderer.uiImage

        #expect(buildCount == 0)
    }
}
