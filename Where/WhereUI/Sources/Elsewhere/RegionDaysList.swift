import RegionKit
import SFSafeSymbols
import SwiftUI
import WhereCore

struct RegionDaysList: View {
    let history: ElsewhereRegion
    let region: Region
    let report: YearReportModel
    let model: ElsewhereModel
    let mapPoints: [RecordedMapPoint]
    let failureMessage: String?
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !mapPoints.isEmpty {
                RecordedPointsMap(points: mapPoints)
            }
            List {
                if let failureMessage {
                    Section {
                        Label(
                            failureMessage,
                            systemSymbol: .exclamationmarkIcloud,
                        )
                        Button(String(localized: .commonRetry), action: retry)
                    }
                }
                Section {
                    ForEach(history.days, id: \.day) { day in
                        RegionDayLink(
                            day: day,
                            coordinate: region == .other ? nil : history.locations
                                .first { $0.day == day.day }?.points.first?.coordinate,
                            report: report,
                            model: model,
                        )
                    }
                } footer: {
                    Text(String(localized: .secondaryRegionFooter))
                }
            }
            .accessibilityIdentifier("where_region_days_list")
        }
    }
}

#if DEBUG
    #Preview("Region days") {
        RegionDaysView.snapshotPreviews
    }
#endif
