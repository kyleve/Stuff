import SFSafeSymbols
import SwiftUI

/// A quiet disclosure treatment for the floating Locations forecast card.
struct LocationForecastDisclosureStyle: DisclosureGroupStyle {
    let foregroundColor: Color

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    configuration.label
                    Image(systemSymbol: .chevronRight)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(foregroundColor)

            if configuration.isExpanded {
                configuration.content
                    .foregroundStyle(.primary)
            }
        }
    }
}
