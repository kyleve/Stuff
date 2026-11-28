import SwiftUI

struct CalendarZoomFlight<TileContent: View>: View {
    let phase: CalendarZoomTransitionState.Phase
    let content: (CalendarPresentationState.Target, CalendarPresentationState.Mode) -> TileContent
    let completion: (CalendarZoomTransitionState.ID) -> Void
    @Environment(\.stylesheet) private var stylesheet
    @State private var arrived = false

    /// Keep the same target IDs and source view hierarchy while the destination is measured.
    private var tiles: [CalendarZoomTransitionState.Tile] {
        switch phase {
            case let .preparing(source):
                source.visibleFrames.sorted { CalendarZoomTransitionState.ordered($0.key, $1.key) }
                    .map { target, frame in
                        .init(id: target, source: frame, destination: frame, visibility: .source)
                    }
            case let .moving(plan):
                plan.tiles
        }
    }

    private var movingID: CalendarZoomTransitionState.ID? {
        guard case let .moving(plan) = phase else { return nil }
        return plan.id
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(tiles) { tile in
                CalendarFlyingTile(
                    tile: tile,
                    phase: phase,
                    arrived: arrived,
                    isMoving: movingID != nil,
                    content: content,
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: movingID, initial: true) { _, id in
            guard let id else { return }
            withAnimation(stylesheet.calendar.overview.animation, completionCriteria: .removed) {
                arrived = true
            } completion: {
                completion(id)
            }
        }
    }
}

#if DEBUG
    #Preview("Zoom between months and year") {
        NavigationStack {
            CalendarContentView(
                report: PreviewSupport.plannedStayYearReportModel(),
                initialMode: .overview,
            )
        }
        .whereBroadwayRoot()
    }
#endif
