#if DEBUG
    import CoreGraphics
    import Testing
    @_spi(Testing) import WhereCore
    @testable import WhereUI

    struct DeveloperOverlayModelTests {
        @Test func nearestCornerPicksTheEnclosingQuadrant() {
            let size = CGSize(width: 100, height: 200)
            #expect(
                DeveloperOverlayModel.nearestCorner(to: CGPoint(x: 10, y: 10), in: size)
                    == .topLeading,
            )
            #expect(
                DeveloperOverlayModel.nearestCorner(to: CGPoint(x: 90, y: 10), in: size)
                    == .topTrailing,
            )
            #expect(
                DeveloperOverlayModel.nearestCorner(to: CGPoint(x: 10, y: 190), in: size)
                    == .bottomLeading,
            )
            #expect(
                DeveloperOverlayModel.nearestCorner(to: CGPoint(x: 90, y: 190), in: size)
                    == .bottomTrailing,
            )
        }

        @MainActor
        @Test func presentationTransitionsFollowTheExpectedFlow() {
            let model = DeveloperOverlayModel(store: InMemoryKeyValueStore())
            #expect(model.presentation == .collapsed)

            model.open()
            #expect(model.presentation == .floating)

            model.toggleFullScreen()
            #expect(model.presentation == .fullScreen)

            model.toggleFullScreen()
            #expect(model.presentation == .floating)

            model.close()
            #expect(model.presentation == .collapsed)
        }

        @MainActor
        @Test func toggleFullScreenIsANoOpWhileCollapsed() {
            let model = DeveloperOverlayModel(store: InMemoryKeyValueStore())
            model.toggleFullScreen()
            #expect(model.presentation == .collapsed)
        }

        // MARK: Floating layout geometry

        @Test func defaultLayoutIsCenteredAtTheDefaultSize() {
            let container = CGSize(width: 400, height: 800)
            let layout = DeveloperOverlayModel.defaultLayout(in: container)
            #expect(layout.center == CGPoint(x: 200, y: 400))
            // width = container - 2*edgeInset (368) under the 420 cap; height = 62%.
            #expect(layout.size == CGSize(width: 368, height: 800 * 0.62))
        }

        @Test func clampKeepsTheWindowFullyOnScreen() {
            let container = CGSize(width: 400, height: 800)
            let offscreen = DeveloperOverlayModel.FloatingLayout(
                center: CGPoint(x: 10000, y: 10000),
                size: CGSize(width: 300, height: 400),
            )
            let clamped = DeveloperOverlayModel.clamp(offscreen, in: container)
            #expect(clamped.size == CGSize(width: 300, height: 400))
            // Far corner pinned inside: center = container - half-size.
            #expect(clamped.center == CGPoint(x: 400 - 150, y: 800 - 200))
        }

        @Test func clampEnforcesTheMinimumAndContainerSizeBounds() {
            let container = CGSize(width: 400, height: 800)
            let tiny = DeveloperOverlayModel.FloatingLayout(
                center: CGPoint(x: 200, y: 400),
                size: CGSize(width: 10, height: 10),
            )
            #expect(
                DeveloperOverlayModel.clamp(tiny, in: container).size
                    == DeveloperOverlayModel.Layout.minSize,
            )

            let huge = DeveloperOverlayModel.FloatingLayout(
                center: CGPoint(x: 200, y: 400),
                size: CGSize(width: 9999, height: 9999),
            )
            #expect(DeveloperOverlayModel.clamp(huge, in: container).size == container)
        }

        @Test func movedShiftsTheCenterAndClampsBackIn() {
            let container = CGSize(width: 400, height: 800)
            // Size is above `Layout.minSize`, so `clamp` won't resize it and the
            // center math is exact.
            let base = DeveloperOverlayModel.FloatingLayout(
                center: CGPoint(x: 200, y: 400),
                size: CGSize(width: 300, height: 400),
            )
            // A small move shifts the center directly.
            let nudged = DeveloperOverlayModel.moved(
                base,
                by: CGSize(width: 30, height: -40),
                in: container,
            )
            #expect(nudged.center == CGPoint(x: 230, y: 360))

            // A huge move parks the window against the edges (half-size margins).
            let flung = DeveloperOverlayModel.moved(
                base,
                by: CGSize(width: 9999, height: 9999),
                in: container,
            )
            #expect(flung.center == CGPoint(x: 400 - 150, y: 800 - 200))
        }

        @Test func resizedPinsTheTopLeadingCorner() {
            let container = CGSize(width: 400, height: 800)
            let base = DeveloperOverlayModel.FloatingLayout(
                center: CGPoint(x: 200, y: 400),
                size: CGSize(width: 300, height: 400),
            )
            let topLeading = CGPoint(
                x: base.center.x - base.size.width / 2,
                y: base.center.y - base.size.height / 2,
            )

            // Growing keeps the top-leading corner fixed.
            let grown = DeveloperOverlayModel.resized(
                base,
                by: CGSize(width: 40, height: 60),
                in: container,
            )
            #expect(grown.center.x - grown.size.width / 2 == topLeading.x)
            #expect(grown.center.y - grown.size.height / 2 == topLeading.y)
            #expect(grown.size == CGSize(width: 340, height: 460))

            // Shrinking past the minimum floors the size but still pins top-leading.
            let shrunk = DeveloperOverlayModel.resized(
                base,
                by: CGSize(width: -9999, height: -9999),
                in: container,
            )
            #expect(shrunk.size == DeveloperOverlayModel.Layout.minSize)
            #expect(shrunk.center.x - shrunk.size.width / 2 == topLeading.x)
            #expect(shrunk.center.y - shrunk.size.height / 2 == topLeading.y)
        }

        // MARK: Persistence

        @MainActor
        @Test func floatingLayoutAndCornerRoundTripThroughTheStore() {
            let store = InMemoryKeyValueStore()
            let layout = DeveloperOverlayModel.FloatingLayout(
                center: CGPoint(x: 123, y: 456),
                size: CGSize(width: 300, height: 420),
            )

            let first = DeveloperOverlayModel(store: store)
            first.setFloating(layout)
            first.setCorner(.topLeading)

            let restored = DeveloperOverlayModel(store: store)
            #expect(restored.floating == layout)
            #expect(restored.corner == .topLeading)
        }

        @MainActor
        @Test func floatingLayoutSurvivesAFullScreenToggle() {
            let model = DeveloperOverlayModel(store: InMemoryKeyValueStore())
            let layout = DeveloperOverlayModel.FloatingLayout(
                center: CGPoint(x: 100, y: 200),
                size: CGSize(width: 280, height: 360),
            )
            model.setFloating(layout)

            model.open()
            model.toggleFullScreen()
            model.toggleFullScreen()

            #expect(model.presentation == .floating)
            #expect(model.floating == layout)
        }
    }
#endif
