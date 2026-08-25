import SwiftUI

/// The perforated rule between visa rows and their planning endorsement.
struct LocationForecastPerforation: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.locationForecast
        let row = style.row

        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(
                path,
                with: .color(Color.primary.opacity(style.ink.separatorOpacity)),
                style: StrokeStyle(
                    lineWidth: row.separatorLineWidth,
                    dash: [row.separatorDashLength, row.separatorDashSpacing],
                ),
            )
        }
        .frame(height: row.separatorHeight)
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview {
        LocationForecastPerforation()
            .padding()
            .whereBroadwayRoot()
    }
#endif
