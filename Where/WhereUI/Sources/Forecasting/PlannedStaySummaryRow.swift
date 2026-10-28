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
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
            HStack(spacing: stylesheet.spacing.small) {
                Text(regionStyles.style(for: stay.region).emoji)
                    .accessibilityHidden(true)
                Text(stay.region.localizedName)
                    .font(.headline)
                Spacer(minLength: 0)
                Image(systemSymbol: .pencil)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            LabeledContent(String(localized: .plannedStayEditorArrival)) {
                Text(WhereFormat.plannedStayWindow(stay.arrival, calendar: calendar))
            }
            LabeledContent(String(localized: .plannedStayEditorLastDay)) {
                Text(WhereFormat.plannedStayWindow(stay.departure, calendar: calendar))
            }
            if hasDefiniteOverlap {
                Label(
                    String(localized: .plannedStaysDefiniteOverlap),
                    systemSymbol: .rectangleOnRectangle,
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if hasPossibleOverlap {
                Label(
                    String(localized: .plannedStaysPossibleOverlap),
                    systemSymbol: .rectangleDashed,
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
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
