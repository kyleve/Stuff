#if DEBUG
    import CoreGraphics
    import Testing
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
            let model = DeveloperOverlayModel()
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
            let model = DeveloperOverlayModel()
            model.toggleFullScreen()
            #expect(model.presentation == .collapsed)
        }
    }
#endif
