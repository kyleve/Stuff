import SnapshotKit
import SwiftUI
import TestHostSupport
import Testing
@_spi(Testing) @testable import WhereUI

@MainActor
struct AdaptivePaneContainerTests {
    @Test func oneMountedContainerRespondsToBoundsTraitsAndReservedRegions() async throws {
        let state = AdaptivePaneHostState()
        let host = UIHostingController(rootView: AdaptivePaneHostedSurface(state: state) {
            AdaptivePaneContainer { arrangement in
                Color.clear.onChange(of: arrangement, initial: true) { _, value in
                    state.arrangement = value
                }
            }
        })
        host.safeAreaRegions = []
        try await show(host) { controller in
            for _ in 0 ..< 2 {
                for pose in [
                    SnapshotConfiguration.DuoPose.outerPortrait,
                    .innerPortrait,
                    .tabletop,
                    .book,
                    .narrow,
                    .outerPortrait,
                ] {
                    try await AdaptivePaneTestSupport.resize(controller, state: state, to: pose)
                    let expected: AdaptivePaneArrangement = switch pose {
                        case .outerPortrait, .outerLandscape, .narrow: .compact
                        case .innerPortrait, .innerLandscape, .book: .columns
                        case .tabletop: .tabletop(.init(
                                detail: CGRect(x: 0, y: 0, width: 669, height: 455.5),
                                controls: CGRect(x: 0, y: 495.5, width: 669, height: 455.5),
                            ))
                    }
                    try await waitForAsync {
                        state.arrangement == expected
                    }
                    if case let .tabletop(panes) = state.arrangement {
                        #expect(panes.detail.maxY == 455.5)
                        #expect(panes.controls.minY == 495.5)
                    }
                }
            }
        }
    }
}
