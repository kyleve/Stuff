import RegionKit
import SwiftUI
import WhereCore

struct ElsewhereRegionLink: View {
    let item: ElsewhereRegion
    let content: ElsewhereModel.Content
    let report: YearReportModel
    let model: ElsewhereModel
    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        NavigationLink {
            RegionDaysView(
                region: item.region,
                report: report,
                model: model,
            )
        } label: {
            RegionSummaryCard(
                regionDays: RegionDays(
                    region: item.region,
                    days: item.days.count,
                ),
                places: content.placeNames[item.region],
                variant: .elsewhere,
                year: report.selectedYear,
                recordedPoints: content.cardLocations
                    .pointsByRegion[item.region] ?? [],
                showsRecordedPoints: report.showsRecordedLocationDots,
                recordedPointsID: content.cardLocations.id,
            )
        }
        .buttonStyle(stylesheet.card[.elsewhere].buttonStyle(
            tint: regionStyles.style(for: item.region).tint,
        ))
    }
}

#if DEBUG
    #Preview("Visited regions") {
        ElsewhereView.snapshotPreviews
    }
#endif
