import SwiftUI

struct CalendarFlyingTile<TileContent: View>: View {
    let tile: CalendarZoomTransitionState.Tile
    let phase: CalendarZoomTransitionState.Phase
    let arrived: Bool
    let isMoving: Bool
    let content: (CalendarPresentationState.Target, CalendarPresentationState.Mode) -> TileContent
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Mask neighboring tiles behind a month only during its flight.
            CalendarFlyingTileBackground(
                size: arrived ? tile.destination.size : tile.source.size,
                radius: cornerRadius(for: tile.id),
                opacity: isMoving ?
                    backgroundOpacity(for: tile.visibility) : 0,
            )
            if tile.visibility != .destination {
                CalendarZoomEndpoint(
                    content: content(tile.id, phase.source.measurement.mode),
                    frame: tile.source,
                    scaledTo: arrived ? tile.destination : nil,
                    opacity: arrived ? 0 : 1,
                )
            }
            if tile.visibility != .source {
                CalendarZoomEndpoint(
                    content: content(tile.id, phase.source.destination),
                    frame: tile.destination,
                    scaledTo: arrived ? nil : tile.source,
                    opacity: arrived ? 1 : 0,
                )
            }
        }
        .frame(width: tile.source.width, height: tile.source.height, alignment: .topLeading)
        .offset(
            x: arrived ? tile.destination.minX : tile.source.minX,
            y: arrived ? tile.destination.minY : tile.source.minY,
        )
        .zIndex(tile.id == phase.source.focus ? 1 : 0)
    }

    private func cornerRadius(for target: CalendarPresentationState.Target) -> CGFloat {
        switch target {
            case .month:
                let mode = arrived ? phase.source.destination : phase.source.measurement.mode
                return mode == .overview ? stylesheet.calendar.overview.cornerRadius
                    : stylesheet.calendar.month.cornerRadius
            case .estimate:
                return stylesheet.locationForecast.cornerRadius
        }
    }

    private func backgroundOpacity(for visibility: CalendarZoomTransitionState.Tile.Visibility)
        -> Double
    {
        switch visibility {
            case .source: arrived ? 0 : 1
            case .destination: arrived ? 1 : 0
            case .both: 1
        }
    }
}

private struct CalendarFlyingTileBackground: View {
    let size: CGSize
    let radius: CGFloat
    let opacity: Double
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(stylesheet.calendar.overview.zoomBackground)
            .frame(width: size.width, height: size.height)
            .opacity(opacity)
    }
}

private struct CalendarZoomEndpoint<Content: View>: View {
    let content: Content
    let frame: CGRect
    let scaledTo: CGRect?
    let opacity: Double

    var body: some View {
        content
            .frame(width: frame.width, height: frame.height)
            .scaleEffect(
                x: scaledTo.map { $0.width / frame.width } ?? 1,
                y: scaledTo.map { $0.height / frame.height } ?? 1,
                anchor: .topLeading,
            )
            .opacity(opacity)
    }
}

#if DEBUG
    #Preview("Calendar zoom tiles") {
        NavigationStack {
            CalendarContentView(
                report: PreviewSupport.plannedStayYearReportModel(),
                initialMode: .overview,
            )
        }
        .whereBroadwayRoot()
    }
#endif
