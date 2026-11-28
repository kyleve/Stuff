import Observation
import SwiftUI
import TestHostSupport
import Testing
@_spi(Testing) @testable import WhereUI

@MainActor
@Suite(.serialized)
struct WhereScreenRootTests {
    @Test func widthAndPaddingChangesRetainOneScroller() async throws {
        let state = ScreenState()
        let host = UIHostingController(rootView: ScreenSurface(state: state).whereBroadwayRoot())
        host.safeAreaRegions = []
        try await show(host) { controller in
            controller.view.frame = CGRect(x: 0, y: 0, width: 1200, height: 500)
            controller.view.layoutIfNeeded()
            try await waitForAsync { state.frame.width == 900 }
            let scroll = try #require(scrollers(in: controller.view).first)
            #expect(scrollers(in: controller.view).count == 1)
            #expect(scroll.bounds.width == 1200)
            scroll.setContentOffset(CGPoint(x: 0, y: 100), animated: false)

            state.override = .regular
            state.padding = .custom(EdgeInsets(top: 10, leading: 24, bottom: 30, trailing: 24))
            try await waitForAsync { state.frame.width == 552 }
            #expect(abs(state.frame.midX - 600) < 1)
            #expect(scroll.contentOffset.y == 100)
            #expect(scrollers(in: controller.view).first === scroll)

            state.override = nil
            state.inherited = .fluid
            state.padding = .standard
            let padding = WhereStylesheet.default.contentRoot.standardPadding
            try await waitForAsync { state.frame.width == 1200 - padding * 2 }
            controller.view.frame.size.width = 320
            controller.view.layoutIfNeeded()
            try await waitForAsync { state.frame.width == 320 - padding * 2 }
            #expect(scroll.bounds.width == 320)
            #expect(scroll.contentOffset.y == 100)
            #expect(scrollers(in: controller.view).first === scroll)
        }
    }

    @Test func nestedScreenRootPassesThroughWithoutPaddingOrScrolling() async throws {
        let state = ScreenState()
        let root = NestedScreenSurface(state: state)
        let host = UIHostingController(rootView: root)
        host.safeAreaRegions = []
        try await show(host) { controller in
            controller.view.frame = CGRect(x: 0, y: 0, width: 1200, height: 500)
            controller.view.layoutIfNeeded()
            try await waitForAsync { state.frame.width == 900 }
            #expect(state.diagnostics.count == 1)
            #expect(scrollers(in: controller.view).count == 1)
            #expect(state.frame.minY == 0)
        }
    }

    @Test func navigationAndSheetsStartIndependentRoots() async throws {
        let state = ScreenState()
        let host = UIHostingController(rootView: PresentationSurface(state: state)
            .whereBroadwayRoot())
        try await show(host) { controller in
            state.showDetail = true
            try await waitForAsync { state.detailWidth != nil }
            #expect(state.detailWidth == .wide)
            #expect(state.diagnostics.isEmpty)
            state.showSheet = true
            try await waitForAsync { state.sheetWidth != nil }
            #expect(state.sheetWidth == .wide)
            #expect(state.diagnostics.isEmpty)
            state.showSheet = false
            try await waitForAsync { controller.presentedViewController == nil }
            state.showDetail = false
        }
    }

    private func scrollers(in view: UIView) -> [UIScrollView] {
        AdaptivePaneTestSupport.descendants(of: view, matching: UIScrollView.self)
    }

    @MainActor @Observable
    fileprivate final class ScreenState {
        var inherited = WhereContentWidth.wide
        var override: WhereContentWidth?
        var padding = WhereContentPadding.none
        var frame = CGRect.zero
        var diagnostics: Set<String> = []
        var showDetail = false
        var showSheet = false
        var detailWidth: WhereContentWidth?
        var sheetWidth: WhereContentWidth?
    }

    private struct ScreenSurface: View {
        let state: ScreenState
        var body: some View {
            ScreenProbe(state: state)
                .whereScreenRoot(state.override, padding: state.padding)
                .whereContentWidth(state.inherited)
        }
    }

    private struct NestedScreenSurface: View {
        let state: ScreenState

        var body: some View {
            ScreenProbe(state: state)
                .whereScreenRoot(
                    .fluid,
                    padding: .custom(EdgeInsets(top: 40, leading: 80, bottom: 40, trailing: 80)),
                )
                .whereScreenRoot(.wide, padding: .none)
                .whereContentRootAssertionHandler { state.diagnostics.insert($0) }
                .whereBroadwayRoot()
        }
    }

    private struct ScreenProbe: View {
        let state: ScreenState
        var body: some View {
            Color.clear
                .frame(height: 1600)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    state.frame = $0
                }
        }
    }

    private struct PresentationSurface: View {
        @Bindable var state: ScreenState
        var body: some View {
            NavigationStack {
                Text("Source")
                    .navigationDestination(isPresented: $state.showDetail) {
                        Destination(state: state, isSheet: false)
                            .whereScreenBoundary()
                    }
                    .whereScreenRoot()
            }
            .whereContentWidth(.wide)
            .whereContentRootAssertionHandler { state.diagnostics.insert($0) }
        }
    }

    private struct Destination: WhereScreen {
        @Bindable var state: ScreenState
        let isSheet: Bool
        @Environment(\.whereContentWidth) private var width

        var content: some View {
            Group {
                if isSheet {
                    Text("Sheet").onAppear { state.sheetWidth = width }
                } else {
                    Text("Detail")
                        .onAppear { state.detailWidth = width }
                        .sheet(isPresented: $state.showSheet) {
                            Destination(state: state, isSheet: true)
                                .whereScreenBoundary()
                        }
                }
            }
        }
    }
}
