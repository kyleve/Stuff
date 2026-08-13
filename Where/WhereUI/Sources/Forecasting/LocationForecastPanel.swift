import RegionKit
import SFSafeSymbols
import SwiftUI
import WhereCore

/// Annual location estimates shared by the Locations summary and calendar
/// surfaces. Calendar hosts can offer one or more regions for stay planning.
struct LocationForecastPanel: View {
    let forecasts: [LocationForecast]
    var plannedStay: PlannedStay?
    var editableRegions: [Region] = []
    var editAction: ((Region) -> Void)?
    var clearAction: (@MainActor () async throws -> Void)?
    var isCollapsible = false

    @State private var isExpanded = false

    @Environment(\.stylesheet) private var stylesheet

    private var style: WhereStylesheet.LocationForecastStyle {
        stylesheet.locationForecast
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.rowSpacing) {
            if isCollapsible {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: style.rowSpacing) {
                        forecastContent
                    }
                    .padding(.top, style.rowSpacing)
                }
                label: {
                    forecastHeader
                }
                .disclosureGroupStyle(LocationForecastDisclosureStyle(
                    foregroundColor: style.collapsedLabelColor,
                ))
            } else {
                forecastHeader
                forecastContent
            }
        }
        .padding(style.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: style.cornerRadius)
            if isCollapsible {
                shape
                    .fill(.background)
                    .overlay {
                        shape.strokeBorder(style.borderColor, lineWidth: style.borderWidth)
                    }
                    .shadow(
                        color: style.shadowColor,
                        radius: style.shadowRadius,
                        y: style.shadowOffsetY,
                    )
            } else {
                Color.clear.glassEffect(.regular, in: shape)
            }
        }
        .animation(style.expansionAnimation, value: isExpanded)
    }

    @ViewBuilder
    private var forecastHeader: some View {
        if let elapsedDays = forecasts.first?.elapsedDays {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemSymbol: .chartLineUptrendXyaxis)
                        .accessibilityHidden(true)
                    Text(String(localized: .locationForecastTitle))
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: stylesheet.spacing.large)
                    Text(WhereFormat.locationForecastElapsed(days: elapsedDays))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: style.estimateSpacing) {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemSymbol: .chartLineUptrendXyaxis)
                            .accessibilityHidden(true)
                        Text(String(localized: .locationForecastTitle))
                    }
                    Text(WhereFormat.locationForecastElapsed(days: elapsedDays))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .font(.headline)
        } else {
            HStack(alignment: .firstTextBaseline) {
                Image(systemSymbol: .chartLineUptrendXyaxis)
                    .accessibilityHidden(true)
                Text(String(localized: .locationForecastTitle))
            }
            .font(.headline)
        }
    }

    @ViewBuilder
    private var forecastContent: some View {
        ForEach(forecasts, id: \.region) { forecast in
            LocationForecastRow(
                forecast: forecast,
                plannedStay: plannedStay,
            )
        }

        if !editableRegions.isEmpty, let editAction {
            LocationForecastControls(
                editableRegions: editableRegions,
                plannedStay: plannedStay,
                editAction: editAction,
                clearAction: clearAction,
            )
        }
    }
}

private struct LocationForecastRow: View {
    let forecast: LocationForecast
    var plannedStay: PlannedStay?

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.locationForecast.estimateSpacing) {
            Text(WhereFormat.locationForecastEstimate(
                region: forecast.region,
                days: forecast.estimatedTotalDays,
            ))
            .font(.subheadline)
            Text(WhereFormat.locationForecastBasis(
                yearToDateDays: forecast.yearToDateDays,
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)

            if let plannedStay, plannedStay.region == forecast.region {
                Text(WhereFormat.locationForecastPlan(through: plannedStay.through))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview {
        let report = PreviewSupport.plannedStayYearReportModel()
        LocationForecastPanel(
            forecasts: report.forecasts.leadingForecasts(report: report.report),
            plannedStay: report.forecasts.activePlannedStay,
            editableRegions: [.california, .newYork],
            editAction: { _ in },
            clearAction: {},
        )
        .padding()
    }
#endif
