import SFSafeSymbols
import SwiftUI

/// Forecast heading that optionally expands the compact Locations card.
struct LocationForecastHeader: View {
    let elapsedDays: Int?
    let isExpanded: Bool
    var expansionAction: (() -> Void)?

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: stylesheet.spacing.xSmall) {
                title
                Spacer(minLength: stylesheet.spacing.large)
                elapsed
            }

            VStack(alignment: .leading, spacing: stylesheet.locationForecast.estimateSpacing) {
                title
                elapsed
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private var title: some View {
        if let expansionAction {
            Button(action: expansionAction) {
                Label {
                    HStack(spacing: stylesheet.spacing.xSmall) {
                        Text(String(localized: .locationForecastTitle))
                        Image(systemSymbol: .chevronRight)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .accessibilityHidden(true)
                    }
                } icon: {
                    Image(systemSymbol: .chartLineUptrendXyaxis)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(stylesheet.locationForecast.collapsedLabelColor)
            .frame(minHeight: 44)
            .accessibilityValue(String(localized: isExpanded
                    ? .locationForecastExpanded
                    : .locationForecastCollapsed))
        } else {
            Label(
                String(localized: .locationForecastTitle),
                systemSymbol: .chartLineUptrendXyaxis,
            )
        }
    }

    @ViewBuilder
    private var elapsed: some View {
        if let elapsedDays {
            Text(WhereFormat.locationForecastElapsed(days: elapsedDays))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
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
