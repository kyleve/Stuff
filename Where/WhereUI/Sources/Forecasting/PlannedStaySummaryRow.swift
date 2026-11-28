import Foundation
import RegionKit
import SFSafeSymbols
import SwiftUI
import WhereCore

/// A stay's destination and separately labeled arrival/departure windows.
struct PlannedStaySummaryRow: View {
    let stay: PlannedStay
    let calendar: Calendar
    let hasDefiniteOverlap: Bool
    let hasPossibleOverlap: Bool

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
            PlannedStaySummaryHeading(region: stay.region)

            LabeledContent(String(localized: .plannedStayEditorArrival)) {
                Text(WhereFormat.plannedStayWindow(stay.arrival, calendar: calendar))
            }
            LabeledContent(String(localized: .plannedStayEditorLastDay)) {
                Text(WhereFormat.plannedStayWindow(stay.departure, calendar: calendar))
            }
            if hasDefiniteOverlap {
                PlannedStayOverlapBadge(
                    title: String(localized: .plannedStaysDefiniteOverlap),
                    symbol: .rectangleOnRectangle,
                )
            }
            if hasPossibleOverlap {
                PlannedStayOverlapBadge(
                    title: String(localized: .plannedStaysPossibleOverlap),
                    symbol: .rectangleDashed,
                )
            }
        }
        .foregroundStyle(.primary)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

private struct PlannedStaySummaryHeading: View {
    let region: Region
    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        HStack(spacing: stylesheet.spacing.small) {
            Text(regionStyles.style(for: region).emoji)
                .accessibilityHidden(true)
            Text(region.localizedName)
                .font(.headline)
            Spacer(minLength: 0)
            Image(systemSymbol: .pencil)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

private struct PlannedStayOverlapBadge: View {
    let title: String
    let symbol: SFSymbol

    var body: some View {
        Label(title, systemSymbol: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

#if DEBUG
    #Preview {
        let report = PreviewSupport.itineraryYearReportModel()
        if let stay = report.forecasts.planning.stays.first {
            List {
                PlannedStaySummaryRow(
                    stay: stay,
                    calendar: report.calendar,
                    hasDefiniteOverlap: false,
                    hasPossibleOverlap: true,
                )
            }
            .whereBroadwayRoot()
        }
    }
#endif
