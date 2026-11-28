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
            if position.isJoinedContinuation {
                JourneyTransitionFill(
                    top: tint.opacity(row.fillOpacity),
                    bottom: tint.opacity(planned.fillOpacity),
                    height: planned.transitionHeight,
                )

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
                if position.isJoinedContinuation {
                    JourneyTransitionFill(
                        top: .clear,
                        bottom: .white,
                        height: planned.transitionHeight,
                    )

                } else {
                    Color.white
                }
            }
        }
        .clipShape(shape)
    }
}

private struct JourneyTransitionFill: View {
    let top: Color
    let bottom: Color
    let height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
                .frame(height: height)
            bottom
        }
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
