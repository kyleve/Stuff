import SFSafeSymbols
import SwiftUI

/// Adaptive seal-and-title layout shared by static and disclosure headers.
struct LocationForecastHeaderLabel: View {
    let elapsedDays: Int?
    let isExpanded: Bool
    let showsDisclosure: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.locationForecast
        let header = style.header

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: header.contentSpacing) {
                HStack {
                    PassportSeal(
                        systemSymbol: .chartLineUptrendXyaxis,
                        tint: Color.primary.opacity(style.ink.sealOpacity),
                    )
                    Spacer(minLength: 0)
                    if showsDisclosure {
                        Image(systemSymbol: .chevronRight)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                LocationForecastHeaderText(elapsedDays: elapsedDays)
            }
        } else {
            HStack(spacing: header.contentSpacing) {
                PassportSeal(
                    systemSymbol: .chartLineUptrendXyaxis,
                    tint: Color.primary.opacity(style.ink.sealOpacity),
                )
                LocationForecastHeaderText(elapsedDays: elapsedDays)
                Spacer(minLength: 0)
                if showsDisclosure {
                    Image(systemSymbol: .chevronRight)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

#if DEBUG
    #Preview {
        LocationForecastHeaderLabel(
            elapsedDays: 224,
            isExpanded: true,
            showsDisclosure: true,
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
