import SFSafeSymbols
import SwiftUI

/// Opens the itinerary from an annual estimate.
struct LocationForecastControls: View {
    let planningAction: () -> Void
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Button(
            String(localized: .plannedStaysTitle),
            systemSymbol: .calendarBadgeClock,
            action: planningAction,
        )
        .buttonStyle(LocationForecastEndorsementButtonStyle(
            tint: .primary,
            expands: true,
            controls: stylesheet.locationForecast.controls,
            ink: stylesheet.locationForecast.ink,
        ))
    }
}

#if DEBUG
    #Preview {
        LocationForecastControls(planningAction: {})
            .padding()
            .whereBroadwayRoot()
    }
#endif
