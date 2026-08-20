#if DEBUG
    import SwiftUI
    import Testing
    import UIKit
    @testable import WhereUI

    @MainActor
    struct RankingAnimationPreviewTests {
        @Test func hostsTheProductionCardStack() {
            let model = RankingAnimationLabModel()
            let controller = UIHostingController(
                rootView: RankingAnimationPreview(
                    model: model,
                    motion: .standard,
                    isVisible: false,
                ),
            )

            #expect(controller.view != nil)
            #expect(model.presentation.presented(model.current) == model.current)
        }
    }
#endif
