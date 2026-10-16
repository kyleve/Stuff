import SwiftUI
import TestHostSupport
import Testing
@_spi(Testing) @testable import WhereUI

@MainActor
struct AdaptiveHistoryContainerTests {
    @Test func oneMountedContainerRespondsToBoundsTraitsAndReservedRegions() async throws {
        let state = AdaptiveHistoryHostState()
        let host = UIHostingController(rootView: AdaptiveHistoryHostedSurface(state: state) {
            AdaptiveHistoryContainer { arrangement in
                Color.clear.onChange(of: arrangement, initial: true) { _, value in
                    state.arrangement = value
                }
            }
        })
        host.safeAreaRegions = []
        try await show(host) { controller in
            for _ in 0 ..< 2 {
                for pose in [
                    AdaptiveHistoryPose.outerPortrait,
                    .innerPortrait,
                    .tabletop,
                    .book,
                    .narrow,
                    .outerPortrait,
                ] {
                    try await AdaptiveHistoryTestSupport.resize(controller, state: state, to: pose)
                    let expected: AdaptiveHistoryArrangement = switch pose {
                        case .outerPortrait, .outerLandscape, .narrow: .compact
                        case .innerPortrait, .innerLandscape, .book: .columns
                        case .tabletop: .tabletop(.init(
                                history: CGRect(x: 0, y: 0, width: 669, height: 455.5),
                                controls: CGRect(x: 0, y: 495.5, width: 669, height: 455.5),
                            ))
                    }
                    try await waitForAsync {
                        state.arrangement == expected
                    }
                    if case let .tabletop(panes) = state.arrangement {
                        #expect(panes.history.maxY == 455.5)
                        #expect(panes.controls.minY == 495.5)
                    }
                }
            }
        }
    }
}
