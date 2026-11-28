import Observation
import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
@Suite(.serialized)
struct WhereFormRootTests {
    @Test(arguments: NativeKind.allCases, [false, true])
    func nativeMarginsRemainContinuousAtWidthLimits(
        kind: NativeKind,
        regularSizeClass: Bool,
    ) async throws {
        let state = FormState()
        let host = UIHostingController(rootView: NativeSurface(state: state, kind: kind)
            .whereBroadwayRoot())
        host.safeAreaRegions = []
        host.traitOverrides.horizontalSizeClass = regularSizeClass ? .regular : .compact
        try await show(host) { controller in
            for (policy, limit) in [(WhereContentWidth.regular, CGFloat(600)), (.wide, 900)] {
                state.width = policy
                controller.view.frame = CGRect(x: 0, y: 0, width: limit, height: 500)
                controller.view.layoutIfNeeded()
                try await waitForAsync {
                    state.viewportWidth == limit && abs(state.frame.midX - limit / 2) < 1
                }
                let boundaryFrame = state.frame
                let boundaryWidth = state.frame.width
                controller.view.frame.size.width = limit + 1
                controller.view.layoutIfNeeded()
                try await waitForAsync {
                    state.viewportWidth == limit + 1 && state.frame != boundaryFrame
                }
                #expect(abs(state.frame.width - boundaryWidth) <= 1)
            }
        }
    }

    @Test(arguments: NativeKind.allCases, [
        EdgeInsets(),
        EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 48),
    ])
    func nativeContainersKeepTheirViewportAndIdentity(
        kind: NativeKind,
        callerInsets: EdgeInsets,
    ) async throws {
        let state = FormState()
        let host = UIHostingController(rootView: NativeSurface(state: state, kind: kind)
            .safeAreaPadding(callerInsets)
            .whereBroadwayRoot())
        host.safeAreaRegions = []
        try await show(host) { controller in
            controller.view.frame = CGRect(x: 0, y: 0, width: 1200, height: 500)
            controller.view.layoutIfNeeded()
            try await waitForAsync { state.frame.width > 0 && state.frame.width <= 600 }
            let scroll = try #require(AdaptivePaneTestSupport.descendants(
                of: controller.view,
                matching: UIScrollView.self,
            ).first)
            #expect(scroll.bounds.width == 1200)
            #expect(abs(state.frame
                    .midX - (600 + (callerInsets.leading - callerInsets.trailing) / 2)) < 1)
            let regularWidth = state.frame.width
            #expect(abs(scroll.safeAreaInsets.right + scroll.verticalScrollIndicatorInsets
                    .right - callerInsets.trailing) < 1)
            scroll.setContentOffset(CGPoint(x: 0, y: 10), animated: false)
            state.override = .wide
            try await waitForAsync { state.frame.width > regularWidth && state.frame.width <= 900 }
            #expect(state.frame.width <= 900)
            #expect(abs(state.frame
                    .midX - (600 + (callerInsets.leading - callerInsets.trailing) / 2)) < 1)
            state.override = nil
            state.width = .fluid
            try await waitForAsync { state.frame.width > 900 }
            controller.view.frame.size.width = 320
            controller.view.layoutIfNeeded()
            try await waitForAsync {
                state.viewportWidth == 320 - callerInsets.leading - callerInsets.trailing && state
                    .frame.width > 0 && state.frame.width <= 320
            }
            let nativeNarrowWidth = state.frame.width
            state.width = .regular
            try await waitForAsync { state.appliedWidth == .regular }
            controller.view.layoutIfNeeded()
            #expect(state.frame.width == nativeNarrowWidth)
            #expect(scroll.bounds.width == 320)
            #expect(scroll.contentOffset.y == 10)
            #expect(AdaptivePaneTestSupport.descendants(
                of: controller.view,
                matching: UIScrollView.self,
            ).first === scroll)
        }
    }

    enum NativeKind: CaseIterable {
        case form
        case list
        case plain
        case sidebar
    }

    @MainActor @Observable
    fileprivate final class FormState {
        var width = WhereContentWidth.regular
        var override: WhereContentWidth?
        var appliedWidth: WhereContentWidth?
        var frame = CGRect.zero
        var viewportWidth: CGFloat = 0
    }

    private struct NativeSurface: View {
        let state: FormState
        let kind: NativeKind

        var body: some View {
            Group {
                switch kind {
                    case .form: Form { rows }
                    case .list: List { rows }
                    case .plain: List { rows }.listStyle(.plain)
                    case .sidebar: List { rows }.listStyle(.sidebar)
                }
            }
            .whereFormRoot(state.override)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                state.viewportWidth = $0
            }
            .whereContentWidth(state.width)
        }

        private var rows: some View {
            Section("Section") {
                NativeProbe(state: state)
                    .listRowInsets(EdgeInsets())
                ForEach(0 ..< 30) { value in Text(value.formatted()) }
            }
        }
    }

    private struct NativeProbe: View {
        let state: FormState
        @Environment(\.whereContentWidth) private var width

        var body: some View {
            Color.clear
                .frame(height: 40)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    state.frame = $0
                }
                .onChange(of: width, initial: true) { state.appliedWidth = width }
        }
    }
}
