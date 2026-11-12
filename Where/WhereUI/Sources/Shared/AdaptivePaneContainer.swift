import SwiftUI

/// Measures one bounded destination. Navigation and presentation owners stay outside it.
struct AdaptivePaneContainer<Content: View>: View {
    @Environment(\.stylesheet) private var stylesheet
    @ViewBuilder var content: (AdaptivePaneArrangement) -> Content

    var body: some View {
        AdaptivePaneGeometryReader { geometry in
            content(AdaptivePaneArrangement.resolve(
                geometry: geometry,
                style: stylesheet.adaptivePane,
            ))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.background)
    }
}

/// Shares physical container geometry with pane layout, the welcome overlay, and developer
/// overlays.
struct AdaptivePaneGeometryReader<Content: View>: View {
    // Physical reserved-region coordinates require the live direction at this container.
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.adaptivePaneRegions) private var injectedRegions
    @ViewBuilder var content: (AdaptivePaneGeometry) -> Content

    var body: some View {
        GeometryReader { proxy in
            content(geometry(in: proxy))
        }
    }

    private func geometry(in proxy: GeometryProxy) -> AdaptivePaneGeometry {
        var geometry = AdaptivePaneGeometry(proxy: proxy, layoutDirection: layoutDirection)
        if let injectedRegions {
            let origin = proxy.frame(in: .named(injectedRegions.coordinateSpace)).origin
            geometry.regions = injectedRegions.regions.map { region in
                AdaptivePaneGeometry.Region(
                    kind: region.kind,
                    frame: region.frame.offsetBy(dx: -origin.x, dy: -origin.y),
                    isActive: region.isActive,
                )
            }
        }
        return geometry
    }
}

/// Detail precedes controls in both source and accessibility order. Frames are physical,
/// so RTL changes content direction without mirroring the hinge or camera clearance.
struct TabletopPaneLayout<Detail: View, Controls: View>: View {
    let panes: AdaptivePaneArrangement.Panes
    @ViewBuilder var detail: () -> Detail
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        ZStack(alignment: .topLeading) {
            detail()
                .frame(width: panes.detail.width, height: panes.detail.height)
                .clipped()
                .position(x: panes.detail.midX, y: panes.detail.midY)
            controls()
                .frame(width: panes.controls.width, height: panes.controls.height)
                .clipped()
                .position(x: panes.controls.midX, y: panes.controls.midY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AdaptivePaneRegions {
    let regions: [AdaptivePaneGeometry.Region]
    let coordinateSpace: Namespace.ID
}

extension EnvironmentValues {
    @Entry fileprivate var adaptivePaneRegions: AdaptivePaneRegions?
}

#if DEBUG
    /// Synthetic reserved regions for the adaptive lab and hosted rendering tests.
    /// Bounds, safe areas, and traits still come from the mounted container.
    @_spi(Testing) public struct AdaptivePaneReservedRegion {
        public enum Kind {
            case division
            case occlusion
        }

        let kind: Kind
        let frame: CGRect
        let isActive: Bool

        public init(kind: Kind, frame: CGRect, isActive: Bool) {
            self.kind = kind
            self.frame = frame
            self.isActive = isActive
        }
    }

    private struct AdaptivePaneRegionsModifier: ViewModifier {
        let regions: [AdaptivePaneReservedRegion]
        @Namespace private var coordinateSpace

        func body(content: Content) -> some View {
            content
                .environment(\.adaptivePaneRegions, AdaptivePaneRegions(
                    regions: regions.map { region in
                        AdaptivePaneGeometry.Region(
                            kind: region.kind == .division ? .division : .occlusion,
                            frame: region.frame,
                            isActive: region.isActive,
                        )
                    },
                    coordinateSpace: coordinateSpace,
                ))
                .coordinateSpace(name: coordinateSpace)
        }
    }

    extension View {
        /// Regions use coordinates local to the modified root. This only replaces system
        /// region delivery; production layout policy, container bounds, and traits are shared.
        @_spi(Testing) public func adaptivePaneReservedRegions(
            _ regions: [AdaptivePaneReservedRegion],
        ) -> some View {
            modifier(AdaptivePaneRegionsModifier(regions: regions))
        }
    }
#endif

#if DEBUG
    #Preview {
        AdaptivePaneContainer { arrangement in
            switch arrangement {
                case .compact: Color.blue
                case .columns: HStack { Color.blue; Color.green }
                case let .tabletop(panes):
                    TabletopPaneLayout(panes: panes) { Color.blue } controls: { Color.green }
            }
        }
        .whereBroadwayRoot()
    }
#endif
