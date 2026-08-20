#if DEBUG
    import SwiftUI
    import Testing
    import UIKit
    @testable import WhereUI

    @MainActor
    struct RankingAnimationLabViewTests {
        @Test func hostsWithSessionLocalStandardMotion() {
            let controller = UIHostingController(
                rootView: NavigationStack {
                    RankingAnimationLabView()
                },
            )

            #expect(controller.view != nil)
            #expect(WhereStylesheet.LocationCardStackStyle.OvertakeMotion.standard.duration == 0.72)
        }
    }
#endif
