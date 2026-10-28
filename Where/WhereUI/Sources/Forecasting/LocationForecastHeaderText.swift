import SwiftUI

/// The localized title and elapsed-day block beside the forecast seal.
struct LocationForecastHeaderText: View {
    let elapsedDays: Int?

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let header = stylesheet.locationForecast.header

        VStack(alignment: .leading, spacing: header.textSpacing) {
            Text(String(localized: .locationForecastTitle))
                .font(header.titleFont)
                .bold()
            if let elapsedDays {
                Text(WhereFormat.locationForecastElapsed(days: elapsedDays))
                    .font(header.elapsedFont)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
    #Preview {
        LocationForecastHeaderText(elapsedDays: 224)
            .padding()
            .whereBroadwayRoot()
    }
#endif
