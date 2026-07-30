@testable import Flyover
import SwiftUI
import Testing

@MainActor
struct FlyoverLayoutTests {
    @Test func forwardRoutesAdvanceAcrossColumns() throws {
        let layout = FlyoverLayout(catalog: makeFlyoverTestCatalog()).resolve()
        let root = try #require(layout.screenFrames[.root])
        let pushed = try #require(layout.screenFrames[.pushed])
        let modal = try #require(layout.screenFrames[.modal])

        #expect(pushed.minX > root.minX)
        #expect(modal.minX > root.minX)
        #expect(pushed.minY != modal.minY)
    }

    @Test func explicitPositionOverridesGraphDepth() throws {
        let positioned = FlyoverScreen(
            id: FlyoverTestScreen.pushed,
            title: "Pushed",
            position: FlyoverPosition(column: 4, row: 2),
            variants: [
                FlyoverVariant(
                    id: FlyoverVariantID("default"),
                    title: "Default",
                ) {
                    EmptyView()
                },
            ],
        )
        let catalog = FlyoverCatalog(
            groups: [
                FlyoverGroup(
                    id: FlyoverGroupID("main"),
                    title: "Main",
                    root: .pushed,
                    screens: [positioned],
                ),
            ],
        )
        let layout = FlyoverLayout(catalog: catalog).resolve()
        let frame = try #require(layout.screenFrames[.pushed])

        #expect(frame.minX > 1500)
        #expect(frame.minY > 1400)
    }
}
