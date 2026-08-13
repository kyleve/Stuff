import SFSafeSymbols
import SwiftUI

/// Forecast heading whose disclosure and explanation remain independent
/// controls on the compact Locations card.
struct LocationForecastHeader: View {
    let elapsedDays: Int?
    let isExpanded: Bool
    var expansionAction: (() -> Void)?

    @State private var isShowingExplanation = false
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: stylesheet.spacing.xSmall) {
                title
                explanationButton
                Spacer(minLength: stylesheet.spacing.large)
                elapsed
            }

            VStack(alignment: .leading, spacing: stylesheet.locationForecast.estimateSpacing) {
                HStack(alignment: .center, spacing: stylesheet.spacing.xSmall) {
                    title
                    explanationButton
                }
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

    private var explanationButton: some View {
        Button(
            String(localized: .locationForecastExplanationButton),
            systemSymbol: .infoCircle,
        ) {
            isShowingExplanation = true
        }
        .labelStyle(.iconOnly)
        .frame(minWidth: 44, minHeight: 44)
        .popover(isPresented: $isShowingExplanation) {
            VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                Text(String(localized: .locationForecastExplanationTitle))
                    .font(.headline)
                Text(String(localized: .locationForecastExplanationBody))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(idealWidth: 320)
            .presentationCompactAdaptation(.popover)
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
