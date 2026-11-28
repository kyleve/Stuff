import SFSafeSymbols
import SwiftUI

/// Adaptive seal-and-title layout shared by static and disclosure headers.
struct LocationForecastHeaderLabel: View {
    let elapsedDays: Int?
    let isExpanded: Bool
    let showsDisclosure: Bool

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.locationForecast
        let header = style.header

        if header.layout == .stacked {
            VStack(alignment: .leading, spacing: header.contentSpacing) {
                HStack {
                    PassportSeal(
                        systemSymbol: .chartLineUptrendXyaxis,
                        tint: Color.primary.opacity(style.ink.sealOpacity),
                    )
                    Spacer(minLength: 0)
                    if showsDisclosure {
                        ForecastDisclosureIndicator(isExpanded: isExpanded)
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
                    ForecastDisclosureIndicator(isExpanded: isExpanded)
                }
            }
        }
    }
}

private struct ForecastDisclosureIndicator: View {
    let isExpanded: Bool

    var body: some View {
        Image(systemSymbol: .chevronRight)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

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
