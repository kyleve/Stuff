#if DEBUG
    import CoreGraphics
    import SwiftUI
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

        // MARK: Content insets (footprint behind the HUD)

        private let insetContainer = CGSize(width: 400, height: 800)
        private let insetTolerance: CGFloat = 16

        private func insets(
            center: CGPoint,
            size: CGSize,
        ) -> EdgeInsets {
            DeveloperOverlayModel.contentInsets(
                for: DeveloperOverlayModel.FloatingLayout(center: center, size: size),
                in: insetContainer,
                edgeTolerance: insetTolerance,
            )
        }

        @Test func defaultWindowClaimsNoContentInset() {
            // The near full-width/centered default spans the width and sits mid
            // height, so it docks no edge.
            let layout = DeveloperOverlayModel.defaultLayout(in: insetContainer)
            #expect(
                DeveloperOverlayModel.contentInsets(
                    for: layout,
                    in: insetContainer,
                    edgeTolerance: insetTolerance,
                ) == EdgeInsets(),
            )
        }

        @Test func midScreenWindowClaimsNoContentInset() {
            #expect(
                insets(center: CGPoint(x: 200, y: 400), size: CGSize(width: 200, height: 200))
                    == EdgeInsets(),
            )
        }

        @Test func edgeDockedWindowInsetsThatEdgeOnly() {
            let size = CGSize(width: 200, height: 300)
            #expect(
                insets(center: CGPoint(x: 200, y: 650), size: size)
                    == EdgeInsets(top: 0, leading: 0, bottom: 300, trailing: 0),
            )
            #expect(
                insets(center: CGPoint(x: 200, y: 150), size: size)
                    == EdgeInsets(top: 300, leading: 0, bottom: 0, trailing: 0),
            )
            #expect(
                insets(center: CGPoint(x: 100, y: 400), size: size)
                    == EdgeInsets(top: 0, leading: 200, bottom: 0, trailing: 0),
            )
            #expect(
                insets(center: CGPoint(x: 300, y: 400), size: size)
                    == EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 200),
            )
        }

        @Test func cornerDockedWindowInsetsBothTouchedEdges() {
            #expect(
                insets(center: CGPoint(x: 300, y: 650), size: CGSize(width: 200, height: 300))
                    == EdgeInsets(top: 0, leading: 0, bottom: 300, trailing: 200),
            )
        }

        @Test func windowSpanningAnAxisClaimsNoInsetOnThatAxis() {
            // Near full height (touches top *and* bottom): no room to push content
            // aside vertically, so no vertical inset.
            #expect(
                insets(center: CGPoint(x: 200, y: 400), size: CGSize(width: 200, height: 790))
                    == EdgeInsets(),
            )
        }

        @Test func contentInsetIsCappedAtAFractionOfTheContainer() {
            // A tall (but not axis-spanning) bottom-docked window would inset 760;
            // it's capped at 0.8 * 800.
            let bottom = insets(
                center: CGPoint(x: 200, y: 420),
                size: CGSize(width: 200, height: 760),
            ).bottom
            #expect(bottom == insetContainer.height * DeveloperOverlayModel.Layout
                .maxContentInsetFraction)
        }

        @Test func contentInsetsAreZeroForAnEmptyContainer() {
            #expect(
                DeveloperOverlayModel.contentInsets(
                    for: DeveloperOverlayModel.FloatingLayout(
                        center: CGPoint(x: 10, y: 10),
                        size: CGSize(width: 100, height: 100),
                    ),
                    in: .zero,
                    edgeTolerance: insetTolerance,
                ) == EdgeInsets(),
            )
        }

        @Test func restoredLayoutClampsIntoASmallerContainer() {
            // A layout persisted in a large container, clamped into a smaller one
            // (rotation / different device), lands fully on-screen — the guard
            // against a window opening off-screen after the container changes.
            let persisted = DeveloperOverlayModel.FloatingLayout(
                center: CGPoint(x: 900, y: 1300),
                size: CGSize(width: 700, height: 900),
            )
            let small = CGSize(width: 400, height: 600)
            let clamped = DeveloperOverlayModel.clamp(persisted, in: small)
            #expect(clamped.center.x - clamped.size.width / 2 >= 0)
            #expect(clamped.center.y - clamped.size.height / 2 >= 0)
            #expect(clamped.center.x + clamped.size.width / 2 <= small.width)
            #expect(clamped.center.y + clamped.size.height / 2 <= small.height)
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
