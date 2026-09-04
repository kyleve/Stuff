import SwiftUI

/// Draws the lighter planned treatment, fading it in after a joined recorded card.
struct PlannedPresenceJourneyBackground: View {
    let position: PresenceJourneyCardPosition
    let tint: Color

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let timeline = stylesheet.timeline
        let row = timeline.row
        let planned = timeline.planned
        let shape = position.shape(cornerRadius: row.cornerRadius)

        ZStack {
            if position.fadesFromRecorded {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            tint.opacity(row.fillOpacity),
                            tint.opacity(planned.fillOpacity),
                        ],
                        startPoint: .top,
                        endPoint: .bottom,
                    )
                    .frame(height: planned.transitionHeight)

                    tint.opacity(planned.fillOpacity)
                }
            } else {
                shape
                    .fill(tint.opacity(planned.fillOpacity))
            }

            PlannedStayHatch(
                color: tint,
                spacing: planned.hatchSpacing,
                lineWidth: planned.hatchLineWidth,
                gridOriginX: 0,
            )
            .opacity(planned.hatchOpacity)
            .mask {
                if position.fadesFromRecorded {
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [.clear, .white],
                            startPoint: .top,
                            endPoint: .bottom,
                        )
                        .frame(height: planned.transitionHeight)

                        Color.white
                    }
                } else {
                    Color.white
                }
            }
        }
        .clipShape(shape)
    }
}

#if DEBUG
    #Preview {
        PlannedPresenceJourneyBackground(position: .bottom, tint: .blue)
            .frame(width: 240, height: 120)
            .padding()
            .whereBroadwayRoot()
    }
#endif
