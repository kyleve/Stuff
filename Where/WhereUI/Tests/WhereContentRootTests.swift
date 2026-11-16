import Observation
import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct WhereContentRootTests {
    @Test func inheritedWidthsKeepTheViewportAndScrollPosition() async throws {
        let state = WidthState()
        let host = UIHostingController(rootView: WidthSurface(state: state).whereBroadwayRoot())
        host.safeAreaRegions = []
        try await show(host) { controller in
            controller.view.frame = CGRect(x: 0, y: 0, width: 1200, height: 500)
            controller.view.layoutIfNeeded()
            try await waitForAsync { state.frames[.inherited]?.width == 600 }
            let scroll = try #require(AdaptivePaneTestSupport.descendants(
                of: controller.view,
                matching: UIScrollView.self,
            ).first)
            #expect(scroll.bounds.width == 1200)
            scroll.setContentOffset(CGPoint(x: 0, y: 200), animated: false)
            let offset = scroll.contentOffset

            for policy in [WhereContentWidth.wide, .fluid, .regular] {
                state.width = policy
                let expected: CGFloat = switch policy {
                    case .regular: 600
                    case .wide: 900
                    case .fluid: 1200
                }
                try await waitForAsync { state.frames[.inherited]?.width == expected }
                let inherited = try #require(state.frames[.inherited])
                #expect(abs(inherited.midX - 600) < 0.5)
                #expect(state.frames[.regular]?.width == 600)
                #expect(state.frames[.fluid]?.width == 1200)
                #expect(scroll.bounds.width == 1200)
                #expect(scroll.contentOffset == offset)
                #expect(AdaptivePaneTestSupport.descendants(
                    of: controller.view,
                    matching: UIScrollView.self,
                ).first === scroll)
            }

            controller.view.frame.size.width = 320
            controller.view.layoutIfNeeded()
            try await waitForAsync { state.frames.values.allSatisfy { $0.width == 320 } }
            #expect(state.frames.count == 3)
            #expect(scroll.bounds.width == 320)
            #expect(scroll.contentOffset == offset)
        }
    }

    fileprivate enum ProbeID: Hashable {
        case inherited
        case regular
        case fluid
    }

    @MainActor @Observable
    fileprivate final class WidthState {
        var width = WhereContentWidth.regular
        var frames: [ProbeID: CGRect] = [:]
    }

    private struct WidthSurface: View {
        let state: WidthState
        @Namespace private var coordinates

        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    WidthProbe(id: .inherited, state: state, coordinates: coordinates)
                        .whereContentRoot()
                    WidthProbe(id: .regular, state: state, coordinates: coordinates)
                        .whereContentRoot()
                        .whereContentWidth(.regular)
                    WidthProbe(id: .fluid, state: state, coordinates: coordinates)
                        .whereContentRoot()
                        .whereContentWidth(.fluid)
                }
            }
            .coordinateSpace(name: coordinates)
            .whereContentWidth(state.width)
        }
    }

    private struct WidthProbe: View {
        let id: ProbeID
        let state: WidthState
        let coordinates: Namespace.ID

        var body: some View {
            Color.clear
                .frame(height: 400)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(coordinates)) } action: {
                    state.frames[id] = $0
                }
        }
    }
}
