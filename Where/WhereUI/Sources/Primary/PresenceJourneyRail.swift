import SwiftUI

/// The continuous route beside a timeline row: a region-tinted line passing
/// through an emoji marker, trimmed at the first and last stops.
struct PresenceJourneyRail: View {
    let tint: Color
    let emoji: String
    let isFirst: Bool
    let isLast: Bool

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let timeline = stylesheet.timeline

        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let nodeRadius = timeline.nodeSize / 2

                if !isFirst {
                    var incoming = Path()
                    incoming.move(to: CGPoint(x: center.x, y: 0))
                    incoming.addLine(to: CGPoint(x: center.x, y: center.y - nodeRadius))
                    context.stroke(
                        incoming,
                        with: .color(tint),
                        lineWidth: timeline.railLineWidth,
                    )
                }

                if !isLast {
                    var outgoing = Path()
                    outgoing.move(to: CGPoint(x: center.x, y: center.y + nodeRadius))
                    outgoing.addLine(to: CGPoint(x: center.x, y: size.height))
                    context.stroke(
                        outgoing,
                        with: .color(tint),
                        lineWidth: timeline.railLineWidth,
                    )
                }
            }

            ZStack {
                Circle()
                    .fill(tint.opacity(timeline.nodeFillOpacity))
                Circle()
                    .stroke(tint, lineWidth: timeline.nodeStrokeWidth)
                Text(emoji)
                    .font(timeline.nodeEmojiFont)
            }
            .frame(width: timeline.nodeSize, height: timeline.nodeSize)
        }
        .frame(width: timeline.nodeSize)
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview {
        PresenceJourneyRail(tint: .orange, emoji: "🌴", isFirst: false, isLast: false)
            .frame(height: 120)
            .padding()
            .whereBroadwayRoot()
    }
#endif
