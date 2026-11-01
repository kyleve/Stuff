import SFSafeSymbols
import SwiftUI

/// Adaptive seal-and-title layout shared by static and disclosure headers.
struct LocationForecastHeaderLabel: View {
    let elapsedDays: Int?
    let isExpanded: Bool
    let showsDisclosure: Bool
    var role: WhereThemeComponents.Role = .summary
    @Environment(\.whereComponentStylesheet) private var components

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.locationForecast
        let header = style.header

        if header.layout == .stacked {
            VStack(alignment: .leading, spacing: header.contentSpacing) {
                HStack {
                    emblem
                    Spacer(minLength: 0)
                    if showsDisclosure {
                        Image(systemSymbol: .chevronRight)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundStyle(.whereSecondary)
                            .accessibilityHidden(true)
                    }
                }
                LocationForecastHeaderText(elapsedDays: elapsedDays, role: role)
            }
        } else {
            HStack(spacing: header.contentSpacing) {
                emblem
                LocationForecastHeaderText(elapsedDays: elapsedDays, role: role)
                Spacer(minLength: 0)
                if showsDisclosure {
                    Image(systemSymbol: .chevronRight)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.whereSecondary)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    @ViewBuilder private var emblem: some View {
        if components[role].nativeArtwork.contains(.stamp) {
            PassportSeal(
                systemSymbol: .chartLineUptrendXyaxis,
                tint: Color.primary.opacity(stylesheet.locationForecast.ink.sealOpacity),
            )
        } else {
            Image(systemSymbol: .chartLineUptrendXyaxis)
                .font(components[role].heading)
                .accessibilityHidden(true)
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
