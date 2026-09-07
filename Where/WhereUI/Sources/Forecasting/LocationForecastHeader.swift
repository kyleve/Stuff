import SwiftUI

/// Forecast endorsement heading that optionally expands the Locations panel.
struct LocationForecastHeader: View {
    let elapsedDays: Int?
    let isExpanded: Bool
    var expansionAction: (() -> Void)?

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        if let expansionAction {
            Button(action: expansionAction) {
                LocationForecastHeaderLabel(
                    elapsedDays: elapsedDays,
                    isExpanded: isExpanded,
                    showsDisclosure: true,
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(
                maxWidth: .infinity,
                minHeight: stylesheet.locationForecast.header.minimumHeight,
            )
            .accessibilityValue(String(localized: isExpanded
                    ? .locationForecastExpanded
                    : .locationForecastCollapsed))
        } else {
            LocationForecastHeaderLabel(
                elapsedDays: elapsedDays,
                isExpanded: true,
                showsDisclosure: false,
            )
        }
    }
}

#if DEBUG
    #Preview {
        LocationForecastHeader(
            elapsedDays: 224,
            isExpanded: false,
            expansionAction: {},
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
