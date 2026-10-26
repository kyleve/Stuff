import SwiftUI

/// Moves fixed-layout copies of the visible tiles while the real scroll view stays positioned.
struct CalendarZoomOverlay<TileContent: View>: View {
    let phase: CalendarZoomTransitionModel.Phase
    let content: (CalendarPresentationModel.Target, CalendarPresentationModel.Mode) -> TileContent
    let completion: (CalendarZoomTransitionModel.ID) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch phase {
                case let .preparing(source):
                    ForEach(
                        source.visibleFrames.keys.sorted(by: CalendarZoomTransitionModel.ordered),
                        id: \.self,
                    ) { target in
                        if let frame = source.visibleFrames[target] {
                            content(target, source.measurement.mode)
                                .frame(width: frame.width, height: frame.height)
                                .offset(x: frame.minX, y: frame.minY)
                        }
                    }
                case let .moving(plan):
                    CalendarZoomFlight(plan: plan, content: content, completion: completion)
                        .id(plan.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CalendarZoomFlight<TileContent: View>: View {
    let plan: CalendarZoomTransitionModel.Plan
    let content: (CalendarPresentationModel.Target, CalendarPresentationModel.Mode) -> TileContent
    let completion: (CalendarZoomTransitionModel.ID) -> Void
    @Environment(\.stylesheet) private var stylesheet
    @State private var arrived = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(plan.tiles) { tile in
                ZStack(alignment: .topLeading) {
                    // Months remain transparent at rest. During the flight,
                    // mask neighboring tiles that pass behind this one.
                    RoundedRectangle(cornerRadius: cornerRadius(for: tile.id), style: .continuous)
                        .fill(stylesheet.calendar.overview.zoomBackground)
                        .frame(
                            width: arrived ? tile.destination.width : tile.source.width,
                            height: arrived ? tile.destination.height : tile.source.height,
                        )
                        .opacity(backgroundOpacity(for: tile.visibility))
                    if tile.visibility != .destination {
                        content(tile.id, plan.source.measurement.mode)
                            .frame(width: tile.source.width, height: tile.source.height)
                            .scaleEffect(
                                x: arrived ? tile.destination.width / tile.source.width : 1,
                                y: arrived ? tile.destination.height / tile.source.height : 1,
                                anchor: .topLeading,
                            )
                            .opacity(arrived ? 0 : 1)
                    }
                    if tile.visibility != .source {
                        content(tile.id, plan.source.destination)
                            .frame(width: tile.destination.width, height: tile.destination.height)
                            .scaleEffect(
                                x: arrived ? 1 : tile.source.width / tile.destination.width,
                                y: arrived ? 1 : tile.source.height / tile.destination.height,
                                anchor: .topLeading,
                            )
                            .opacity(arrived ? 1 : 0)
                    }
                }
                .frame(width: tile.source.width, height: tile.source.height, alignment: .topLeading)
                .offset(
                    x: arrived ? tile.destination.minX : tile.source.minX,
                    y: arrived ? tile.destination.minY : tile.source.minY,
                )
                .zIndex(tile.id == plan.source.focus ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            withAnimation(stylesheet.calendar.overview.animation, completionCriteria: .removed) {
                arrived = true
            } completion: {
                completion(plan.id)
            }
        }
    }

    private func cornerRadius(for target: CalendarPresentationModel.Target) -> CGFloat {
        switch target {
            case .month:
                let mode = arrived ? plan.source.destination : plan.source.measurement.mode
                return mode == .overview ? stylesheet.calendar.overview.cornerRadius
                    : stylesheet.calendar.month.cornerRadius
            case .estimate:
                return stylesheet.locationForecast.cornerRadius
        }
    }

    private func backgroundOpacity(for visibility: CalendarZoomTransitionModel.Tile.Visibility)
        -> Double
    {
        switch visibility {
            case .source: arrived ? 0 : 1
            case .destination: arrived ? 1 : 0
            case .both: 1
        }
    }
}

struct CalendarZoomFrames: PreferenceKey {
    typealias Mode = CalendarPresentationModel.Mode
    typealias Target = CalendarPresentationModel.Target
    enum Frame: Hashable {
        case content
        case tile(Target)
    }

    static let defaultValue: [Mode: [Frame: Anchor<CGRect>]] = [:]

    static func measure(
        _ anchors: [Frame: Anchor<CGRect>],
        in proxy: GeometryProxy,
        mode: Mode,
        scrollOffset: CGPoint,
    ) -> CalendarZoomTransitionModel.Measurement? {
        guard let content = anchors[.content] else { return nil }
        let contentFrame = proxy[content]
        // Resolve anchors relative to their content, then apply the current scroll
        // offset. Anchors alone do not update as the viewport scrolls.
        let translation = CGPoint(
            x: -contentFrame.minX - scrollOffset.x,
            y: -contentFrame.minY - scrollOffset.y,
        )
        let frames = anchors.reduce(into: [Target: CGRect]()) { frames, entry in
            switch entry.key {
                case .content: break
                case let .tile(target):
                    frames[target] = proxy[entry.value].offsetBy(
                        dx: translation.x,
                        dy: translation.y,
                    )
            }
        }
        return .init(
            mode: mode,
            frames: frames,
            viewport: CGRect(origin: .zero, size: proxy.size),
            content: contentFrame.offsetBy(dx: translation.x, dy: translation.y),
        )
    }

    static func reduce(
        value: inout [Mode: [Frame: Anchor<CGRect>]],
        nextValue: () -> [Mode: [Frame: Anchor<CGRect>]],
    ) {
        for (mode, frames) in nextValue() {
            value[mode, default: [:]].merge(frames, uniquingKeysWith: { _, new in new })
        }
    }
}

#if DEBUG
    #Preview("Calendar zoom") {
        NavigationStack {
            CalendarContentView(
                report: PreviewSupport.plannedStayYearReportModel(),
                initialMode: .overview,
            )
        }
        .whereBroadwayRoot()
    }
#endif
