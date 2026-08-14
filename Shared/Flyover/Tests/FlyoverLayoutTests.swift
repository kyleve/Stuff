@testable import Flyover
import SwiftUI
import Testing

@MainActor
struct FlyoverLayoutTests {
    @Test func forwardRoutesAdvanceAcrossColumns() throws {
        let layout = FlyoverLayout(
            catalog: makeFlyoverTestCatalog(),
            style: FlyoverStylesheet.default.layout,
        ).resolve()
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
        let layout = FlyoverLayout(
            catalog: catalog,
            style: FlyoverStylesheet.default.layout,
        ).resolve()
        let frame = try #require(layout.screenFrames[.pushed])

        #expect(frame.minX > 1500)
        #expect(frame.minY > 1400)
    }

    @Test func tallAutomaticStacksSpillRightBeforeTheNextDepth() throws {
        var style = FlyoverStylesheet.default.layout
        style.maximumAutomaticRowsPerColumn = 2
        let childIDs = (1 ... 5).map { "child-\($0)" }
        let screens = ["root"] + childIDs + ["grandchild"]
        let catalog = FlyoverCatalog(
            groups: [
                FlyoverGroup(
                    id: FlyoverGroupID("main"),
                    title: "Main",
                    root: "root",
                    screens: screens.map { id in
                        FlyoverScreen(
                            id: id,
                            title: id,
                            variants: [
                                FlyoverVariant(
                                    id: FlyoverVariantID("default"),
                                    title: "Default",
                                ) {
                                    EmptyView()
                                },
                            ],
                        )
                    },
                ),
            ],
            transitions: childIDs.map {
                FlyoverTransition(from: "root", to: $0, kind: .push)
            } + [
                FlyoverTransition(from: childIDs[0], to: "grandchild", kind: .push),
            ],
        )
        let layout = FlyoverLayout(catalog: catalog, style: style).resolve()
        let firstChild = try #require(layout.screenFrames[childIDs[0]])
        let secondChild = try #require(layout.screenFrames[childIDs[1]])
        let thirdChild = try #require(layout.screenFrames[childIDs[2]])
        let fifthChild = try #require(layout.screenFrames[childIDs[4]])
        let grandchild = try #require(layout.screenFrames["grandchild"])
        let group = try #require(layout.groupFrames[FlyoverGroupID("main")])

        #expect(secondChild.minX == firstChild.minX)
        #expect(secondChild.minY > firstChild.minY)
        #expect(thirdChild.minX > secondChild.minX)
        #expect(thirdChild.minY == firstChild.minY)
        #expect(grandchild.minX > fifthChild.minX)
        #expect(
            group.height == style.groupPadding * 2
                + style.cardSize.height * 2
                + style.verticalSpacing
                + style.groupHeaderHeight,
        )
    }

    @Test func groupsFormATopAlignedHorizontalShelf() throws {
        let style = FlyoverStylesheet.default.layout
        let catalog = FlyoverCatalog(
            groups: [
                FlyoverGroup(
                    id: FlyoverGroupID("main"),
                    title: "Main",
                    root: .root,
                    screens: [
                        makeFlyoverTestScreen(.root, title: "Root"),
                    ],
                ),
                FlyoverGroup(
                    id: FlyoverGroupID("components"),
                    title: "Components",
                    root: .component,
                    screens: [
                        makeFlyoverTestScreen(.component, title: "Component"),
                        makeFlyoverTestScreen(.pushed, title: "Pushed"),
                        makeFlyoverTestScreen(.modal, title: "Modal"),
                    ],
                ),
            ],
            transitions: [
                FlyoverTransition(from: .component, to: .pushed, kind: .push),
                FlyoverTransition(from: .component, to: .modal, kind: .modal),
            ],
        )
        let layout = FlyoverLayout(catalog: catalog, style: style).resolve()
        let main = try #require(layout.groupFrames[FlyoverGroupID("main")])
        let components = try #require(layout.groupFrames[FlyoverGroupID("components")])

        #expect(main.minY == style.canvasPadding)
        #expect(components.minY == main.minY)
        #expect(components.minX == main.maxX + style.groupSpacing)
        #expect(layout.initialCanvasSize.width == main.maxX + style.canvasPadding)
        #expect(layout.initialCanvasSize.height == main.maxY + style.canvasPadding)
        #expect(layout.canvasSize.width == components.maxX + style.canvasPadding)
        #expect(layout.canvasSize.height == components.maxY + style.canvasPadding)

        let availableSize = CGSize(width: 1000, height: 1000)
        let initialZoom = FlyoverCanvasZoomPlan(
            canvasSize: layout.initialCanvasSize,
            availableSize: availableSize,
            edgeInset: FlyoverStylesheet.default.canvas.framingInset,
        ).widthZoom
        let fitAllZoom = FlyoverCanvasZoomPlan(
            canvasSize: layout.canvasSize,
            availableSize: availableSize,
            edgeInset: FlyoverStylesheet.default.canvas.framingInset,
        ).allZoom
        #expect(initialZoom > fitAllZoom)
    }
}
