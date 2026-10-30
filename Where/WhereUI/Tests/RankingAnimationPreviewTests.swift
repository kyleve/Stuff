import SwiftUI
import TestHostSupport
import Testing
import UIKit
@testable import WhereUI

@MainActor
struct RankingAnimationPreviewTests {
    @Test(arguments: [false, true])
    func halloweenCardsCompleteTwoOvertakesWithNativeFocusOrder(reduceMotion: Bool) async throws {
        let model = RankingAnimationLabModel()
        let theme = try WhereThemeExamples.halloween.prepare()
        let cache = RegionOutlinePathCache()
        await PreviewSupport.loadCardArtwork(for: [.california, .newYork], cache: cache)
        let root = RankingAnimationPreview(
            model: model,
            motion: reduceMotion ? .reducedMotion : .standard,
            isVisible: true,
        )
        .padding(24)
        .environment(\.regionOutlinePathCache, cache)
        .whereBroadwayRoot(themeDocument: theme)
        .environment(\.scenePhase, .active)
        try await show(UIHostingController(rootView: root)) { host in
            host.view.window?.layer.speed = 1
            try await ThemeInteractionTestSupport.wait("the ranked card content") {
                card("California", in: host.view) != nil && card("New York", in: host.view) != nil
            }
            for sequence in 1 ... 2 {
                model.playNextOvertake()
                try await ThemeInteractionTestSupport.wait("the overtake to settle") {
                    model.presentation.latestOvertake?.sequence == sequence
                        && model.presentation.overtakeMovement == nil
                        && model.presentation.presented(model.current) == model.current
                }
                let winner = sequence == 1 ? "New York" : "California"
                let loser = sequence == 1 ? "California" : "New York"
                try await ThemeInteractionTestSupport.wait("the settled native focus frames") {
                    guard let first = card(winner, in: host.view),
                          let second = card(loser, in: host.view)
                    else { return false }
                    return first.accessibilityFrame.maxY < second.accessibilityFrame.minY
                }
                let labels = ThemeInteractionTestSupport.objects(in: host.view)
                    .filter(\.isAccessibilityElement).compactMap(\.accessibilityLabel)
                #expect(!labels.contains { $0.localizedCaseInsensitiveContains("pumpkin") })
            }
        }
    }

    private func card(_ name: String, in view: UIView) -> NSObject? {
        ThemeInteractionTestSupport.objects(in: view).first {
            $0.isAccessibilityElement && $0.accessibilityLabel?.hasPrefix(name) == true
        }
    }
}
