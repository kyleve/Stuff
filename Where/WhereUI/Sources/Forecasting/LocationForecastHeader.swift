import SwiftUI

/// Forecast endorsement heading that optionally expands the Locations panel.
struct LocationForecastHeader: View {
    let elapsedDays: Int?
    let isExpanded: Bool
    var expansionAction: (() -> Void)?

    var body: some View {
        if let expansionAction {
            ForecastDisclosureButton(
                elapsedDays: elapsedDays,
                isExpanded: isExpanded,
                expansionAction: expansionAction,
            )

        } else {
            LocationForecastHeaderLabel(
                elapsedDays: elapsedDays,
                isExpanded: true,
                showsDisclosure: false,
            )
        }
    }
}

private struct ForecastDisclosureButton: View {
    let elapsedDays: Int?
    let isExpanded: Bool
    let expansionAction: () -> Void
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
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
