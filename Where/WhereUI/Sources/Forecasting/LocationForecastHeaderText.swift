import SwiftUI

/// The localized title and elapsed-day block beside the forecast seal.
struct LocationForecastHeaderText: View {
    let elapsedDays: Int?
    var role: WhereThemeComponents.Role = .summary

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.whereComponentStylesheet) private var components

    var body: some View {
        let header = stylesheet.locationForecast.header

        VStack(alignment: .leading, spacing: header.textSpacing) {
            Text(String(localized: .locationForecastTitle))
                .font(components[role].heading ?? header.titleFont)
                .bold()
            if let elapsedDays {
                Text(WhereFormat.locationForecastElapsed(days: elapsedDays))
                    .font(components[role].body ?? header.elapsedFont)
                    .foregroundStyle(.whereSecondary)
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
