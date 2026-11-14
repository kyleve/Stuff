import CoreGraphics
import Observation
import SnapshotKit
import SwiftUI
import TestHostSupport
@_spi(Testing) @testable import WhereUI

enum AdaptivePaneTestSupport {
    /// Native inner-portrait measurements; frames include reserved-region margins.
    static var portrait: AdaptivePaneGeometry {
        AdaptivePaneGeometry(
            bounds: CGRect(x: 0, y: 0, width: 669, height: 951),
            insets: .init(top: 82, left: 0, bottom: 34, right: 0),
            regions: [],
            layoutDirection: .leftToRight,
        )
    }

    static var horizontalDivision: AdaptivePaneGeometry.Region {
        .init(
            kind: .division,
            frame: CGRect(x: 0, y: 455.5, width: 669, height: 40),
            isActive: true,
        )
    }

    static var multiplePaneStyle: WhereStylesheet.AdaptivePaneStyle {
        var style = WhereStylesheet.AdaptivePaneStyle()
        style.panes = .multiple
        return style
    }
}

@MainActor @Observable
final class AdaptivePaneHostState {
    var pose = SnapshotConfiguration.DuoPose.outerPortrait
    var renderedSize: CGSize = .zero
    var panes = WhereStylesheet.AdaptivePaneStyle.Panes.single
    var arrangement: AdaptivePaneArrangement?
}

struct AdaptivePaneHostedSurface<Content: View>: View {
    let state: AdaptivePaneHostState
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .adaptivePaneReservedRegions(state.pose.regions)
            .overlay { AdaptivePanePolicyProbe(state: state) }
            .whereBroadwayRoot()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { state.renderedSize = $0 }
    }
}

private struct AdaptivePanePolicyProbe: View {
    let state: AdaptivePaneHostState
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onChange(of: stylesheet.adaptivePane.panes, initial: true) { _, panes in
                state.panes = panes
            }
    }
}

extension AdaptivePaneTestSupport {
    @MainActor static func resize(
        _ controller: UIViewController,
        state: AdaptivePaneHostState,
        to pose: SnapshotConfiguration.DuoPose,
    ) async throws {
        state.pose = pose
        controller.view.frame = CGRect(origin: .zero, size: pose.size)
        let isRegular = [.innerPortrait, .innerLandscape, .tabletop, .book].contains(pose)
        controller.traitOverrides.horizontalSizeClass = isRegular ? .regular : .compact
        controller.traitOverrides.verticalSizeClass = pose == .outerLandscape ? .compact : .regular
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try await waitForAsync {
            state.renderedSize == pose.size && state.panes == (isRegular ? .multiple : .single)
        }
    }

    @MainActor static func presentedController(from root: UIViewController) -> UIViewController? {
        if let presented = root.presentedViewController { return presented }
        return root.children.lazy.compactMap { presentedController(from: $0) }.first
    }

    @MainActor static func descendants<T: UIView>(of view: UIView, matching _: T.Type) -> [T] {
        let matches = (view as? T).map { [$0] } ?? []
        return matches + view.subviews.flatMap { descendants(of: $0, matching: T.self) }
    }
}
