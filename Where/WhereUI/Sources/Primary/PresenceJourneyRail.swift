import SwiftUI

/// The continuous route beside a timeline row: a region-tinted line passing
/// through a precise region-symbol marker, trimmed at the first and last stops.
struct PresenceJourneyRail: View {
    let tint: Color
    let symbolName: String
    let emoji: String
    let isFirst: Bool
    let isLast: Bool

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let timeline = stylesheet.timeline
        let rail = timeline.rail

        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let nodeRadius = rail.nodeSize / 2

                if !isFirst {
                    var incoming = Path()
                    incoming.move(to: CGPoint(x: center.x, y: 0))
                    incoming.addLine(to: CGPoint(x: center.x, y: center.y - nodeRadius))
                    context.stroke(
                        incoming,
                        with: .color(tint),
                        lineWidth: rail.lineWidth,
                    )
                }

                if !isLast {
                    var outgoing = Path()
                    outgoing.move(to: CGPoint(x: center.x, y: center.y + nodeRadius))
                    outgoing.addLine(to: CGPoint(x: center.x, y: size.height))
                    context.stroke(
                        outgoing,
                        with: .color(tint),
                        lineWidth: rail.lineWidth,
                    )
                }
            }

            ZStack {
                Circle()
                    .fill(stylesheet.palette.brand.raisedPaper)
                Circle()
                    .fill(tint.opacity(rail.nodeFillOpacity))
                Circle()
                    .stroke(tint, lineWidth: rail.nodeStrokeWidth)
                Image(systemName: symbolName)
                    .font(rail.nodeSymbolFont)
                    .foregroundStyle(tint)
                Text(emoji)
                    .font(rail.nodeEmojiFont)
                    .offset(
                        x: rail.charmOffset.width,
                        y: rail.charmOffset.height,
                    )
            }
            .frame(width: rail.nodeSize, height: rail.nodeSize)
        }
        .frame(width: rail.nodeSize)
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview {
        PresenceJourneyRail(
            tint: .orange,
            symbolName: "sun.max.fill",
            emoji: "🌴",
            isFirst: false,
            isLast: false,
        )
        .frame(height: 120)
        .padding()
        .whereBroadwayRoot()
    }
#endif
