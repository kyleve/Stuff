import SwiftUI
import TestHostSupport
import Testing
import UIKit
@testable import WhereUI

struct LocationsViewTests {
    @MainActor
    @Test(arguments: WhereThemeExamples.allCases)
    func seasonalCardsScrollWithinTheClippedViewport(example: WhereThemeExamples) async throws {
        let theme = try example.prepare()
        let report = PreviewSupport.loadedYearReportModel()
        let cache = RegionOutlinePathCache()
        await PreviewSupport.loadCardArtwork(for: [.california, .newYork], cache: cache)
        let root = LocationsView(report: report)
            .environment(\.regionOutlinePathCache, cache)
            .whereBroadwayRoot(themeDocument: theme)
            .environment(\.scenePhase, .active)
            .frame(height: 480)
        try await show(UIHostingController(rootView: root)) { host in
            try await ThemeInteractionTestSupport.wait("the scrollable illustrated cards") {
                ThemeInteractionTestSupport.button("California", in: host.view) != nil
            }
            let scrollView = try #require(ThemeInteractionTestSupport.objects(in: host.view)
                .compactMap { $0 as? UIScrollView }
                .first { $0.contentSize.height > $0.bounds.height + 100 })
            #expect(scrollView.clipsToBounds)
            let initialOffset = scrollView.contentOffset
            let initialFrame = try #require(ThemeInteractionTestSupport
                .button("California", in: host.view)).accessibilityFrame
            scrollView.setContentOffset(
                CGPoint(x: initialOffset.x, y: initialOffset.y + 80),
                animated: false,
            )
            try await ThemeInteractionTestSupport.wait("the card to scroll with its content") {
                guard let card = ThemeInteractionTestSupport.button("California", in: host.view)
                else { return false }
                return card.accessibilityFrame.minY < initialFrame.minY - 60
            }
            #expect(scrollView.clipsToBounds)
            scrollView.setContentOffset(initialOffset, animated: false)
            try await ThemeInteractionTestSupport
                .wait("the card to return to its original position") {
                    guard let card = ThemeInteractionTestSupport.button("California", in: host.view)
                    else { return false }
                    return abs(card.accessibilityFrame.minY - initialFrame.minY) < 1
                }
            let returnedFrame = try #require(ThemeInteractionTestSupport
                .button("California", in: host.view)).accessibilityFrame
            #expect(returnedFrame.width == initialFrame.width)
        }
    }

    @MainActor
    @Test(arguments: WhereThemeExamples.allCases)
    func seasonalCardsKeepNativeFocusBoundsThroughRepeatedNavigationAndSheets(
        example: WhereThemeExamples,
    ) async throws {
        let theme = try example.prepare()
        let report = PreviewSupport.loadedYearReportModel()
        let cache = RegionOutlinePathCache()
        await PreviewSupport.loadCardArtwork(for: [.california, .newYork], cache: cache)
        let root = LocationsView(report: report)
            .environment(\.regionOutlinePathCache, cache)
            .whereBroadwayRoot(themeDocument: theme)
            .environment(\.scenePhase, .active)
        try await show(UIHostingController(rootView: root)) { host in
            host.view.window?.layer.speed = 1
            try await ThemeInteractionTestSupport.wait("the native region links") {
                ThemeInteractionTestSupport.button("California", in: host.view) != nil
                    && ThemeInteractionTestSupport.button("New York", in: host.view) != nil
            }
            try assertNativeCardBounds(in: host.view, minimumGap: example == .halloween ? 70 : 60)
            let navigation = try #require(ThemeInteractionTestSupport.navigation(in: host))
            for _ in 0 ..< 2 {
                try ThemeInteractionTestSupport.activate(
                    #require(ThemeInteractionTestSupport.button("California", in: host.view)),
                )
                try await ThemeInteractionTestSupport.wait("the card zoom to finish") {
                    navigation.viewControllers.count == 2 && navigation.transitionCoordinator == nil
                }
                navigation.popViewController(animated: true)
                try await ThemeInteractionTestSupport.wait("the card zoom to return") {
                    navigation.viewControllers.count == 1 && navigation.transitionCoordinator == nil
                        && ThemeInteractionTestSupport.button("California", in: host.view) != nil
                }
                try assertNativeCardBounds(
                    in: host.view,
                    minimumGap: example == .halloween ? 70 : 60,
                )
            }
            try ThemeInteractionTestSupport.activate(
                #require(ThemeInteractionTestSupport.button("Planned stays", in: host.view)),
            )
            try await ThemeInteractionTestSupport.wait("the planning sheet") {
                ThemeInteractionTestSupport.presented(in: host) != nil
            }
            let sheet = try #require(ThemeInteractionTestSupport.presented(in: host))
            try await ThemeInteractionTestSupport.wait("the sheet controls") {
                ThemeInteractionTestSupport.button("Done", in: sheet.view) != nil
            }
            try ThemeInteractionTestSupport.activate(
                #require(ThemeInteractionTestSupport.button("Done", in: sheet.view)),
            )
            try await ThemeInteractionTestSupport.wait("the sheet to dismiss") {
                ThemeInteractionTestSupport.presented(in: host) == nil
            }
            #expect(ThemeInteractionTestSupport.button("California", in: host.view) != nil)
            try assertNativeCardBounds(in: host.view, minimumGap: example == .halloween ? 70 : 60)
        }
    }

    @MainActor
    private func assertNativeCardBounds(in view: UIView, minimumGap: CGFloat) throws {
        let california = try #require(ThemeInteractionTestSupport.button("California", in: view))
        let newYork = try #require(ThemeInteractionTestSupport.button("New York", in: view))
        // Exterior artwork occupies this gap without joining either native focus target.
        #expect(newYork.accessibilityFrame.minY - california.accessibilityFrame.maxY >= minimumGap)
        #expect(california.accessibilityFrame.width > 0)
        #expect(california.accessibilityLabel?.contains("148") == true)
    }

    @MainActor
    @Test func emptyLocationsCanAnimateTheirThemeBackground() throws {
        let theme = try activeThemeBackground()
        let host =
            UIHostingController(rootView: LocationsView(report: PreviewSupport
                    .emptyYearReportModel())
                .whereBroadwayRoot(themeDocument: theme)
                .environment(\.scenePhase, .active))
        try show(host) { host in
            try waitFor { themeBackgroundIsRed(in: host.view) }
        }
    }

    @Test func screenCompositionKeepsViewValuesWithinStackBudget() {
        #expect(MemoryLayout<LocationsView.Body>.size < 16384)
    }
}
