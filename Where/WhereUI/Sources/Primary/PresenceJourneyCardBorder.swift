import SwiftUI

/// Draws only the outer stroke of a standalone or joined journey-card segment.
struct PresenceJourneyCardBorder: View {
    let position: PresenceJourneyCardPosition
    let cornerRadius: CGFloat
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        switch position {
            case .standalone:
                position.shape(cornerRadius: cornerRadius)
                    .stroke(color, lineWidth: lineWidth)
            case .top, .bottom:
                position.shape(cornerRadius: cornerRadius)
                    .stroke(color, lineWidth: lineWidth)
                    .mask {
                        Rectangle()
                            .padding(position.joinedEdge, lineWidth)
                    }
        }
    }
}

#if DEBUG
    #Preview {
        PresenceJourneyCardBorder(
            position: .standalone,
            cornerRadius: 18,
            color: .blue,
            lineWidth: 1,
        )
        .frame(width: 240, height: 120)
        .padding()
    }
#endif
