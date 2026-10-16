import SwiftUI

/// Measures one bounded destination. Navigation and presentation owners stay outside it.
struct AdaptiveHistoryContainer<Content: View>: View {
    @Environment(\.stylesheet) private var stylesheet
    @ViewBuilder var content: (AdaptiveHistoryArrangement) -> Content

    var body: some View {
        AdaptiveHistoryGeometryReader { geometry in
            content(AdaptiveHistoryArrangement.resolve(
                geometry: geometry,
                style: stylesheet.adaptiveHistory,
            ))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.background)
    }
}

/// Shares the native/injected coordinate mapping with custom chrome above the destinations.
struct AdaptiveHistoryGeometryReader<Content: View>: View {
    // Physical reserved-region coordinates require the live direction at this container.
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.adaptiveHistoryRegions) private var injectedRegions
    @ViewBuilder var content: (AdaptiveHistoryGeometry) -> Content

    var body: some View {
        GeometryReader { proxy in
            content(geometry(in: proxy))
        }
    }

    private func geometry(in proxy: GeometryProxy) -> AdaptiveHistoryGeometry {
        var geometry = AdaptiveHistoryGeometry(proxy: proxy, layoutDirection: layoutDirection)
        if let injectedRegions {
            let origin = proxy.frame(in: .named(injectedRegions.coordinateSpace)).origin
            geometry.regions = injectedRegions.regions.map { region in
                AdaptiveHistoryGeometry.Region(
                    kind: region.kind,
                    frame: region.frame.offsetBy(dx: -origin.x, dy: -origin.y),
                    isActive: region.isActive,
                )
            }
        }
        return geometry
    }
}

/// History precedes controls in both source and accessibility order. Frames are physical,
/// so RTL changes content direction without mirroring the hinge or camera clearance.
struct TabletopHistoryLayout<History: View, Controls: View>: View {
    let panes: AdaptiveHistoryArrangement.Panes
    @ViewBuilder var history: () -> History
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        ZStack(alignment: .topLeading) {
            history()
                .frame(width: panes.history.width, height: panes.history.height)
                .clipped()
                .position(x: panes.history.midX, y: panes.history.midY)
            controls()
                .frame(width: panes.controls.width, height: panes.controls.height)
                .clipped()
                .position(x: panes.controls.midX, y: panes.controls.midY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AdaptiveHistoryRegions {
    let regions: [AdaptiveHistoryGeometry.Region]
    let coordinateSpace: Namespace.ID
}

extension EnvironmentValues {
    @Entry fileprivate var adaptiveHistoryRegions: AdaptiveHistoryRegions?
}

#if DEBUG
    /// Synthetic reserved regions for the adaptive lab and hosted rendering tests.
    /// Bounds, safe areas, and traits still come from the mounted container.
    @_spi(Testing) public struct AdaptiveHistoryReservedRegion {
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

    private struct AdaptiveHistoryRegionsModifier: ViewModifier {
        let regions: [AdaptiveHistoryReservedRegion]
        @Namespace private var coordinateSpace

        func body(content: Content) -> some View {
            content
                .environment(\.adaptiveHistoryRegions, AdaptiveHistoryRegions(
                    regions: regions.map { region in
                        AdaptiveHistoryGeometry.Region(
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
        @_spi(Testing) public func adaptiveHistoryReservedRegions(
            _ regions: [AdaptiveHistoryReservedRegion],
        ) -> some View {
            modifier(AdaptiveHistoryRegionsModifier(regions: regions))
        }
    }
#endif

#if DEBUG
    #Preview {
        AdaptiveHistoryContainer { arrangement in
            switch arrangement {
                case .compact: Color.blue
                case .columns: HStack { Color.blue; Color.green }
                case let .tabletop(panes):
                    TabletopHistoryLayout(panes: panes) { Color.blue } controls: { Color.green }
            }
        }
        .whereBroadwayRoot()
    }
#endif
