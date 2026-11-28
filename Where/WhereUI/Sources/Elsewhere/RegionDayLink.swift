import RegionKit
import SFSafeSymbols
import SwiftUI
import WhereCore

struct RegionDayLink: View {
    let day: DayPresence
    let coordinate: Coordinate?
    let report: YearReportModel
    let model: ElsewhereModel

    @Environment(\.stylesheet) private var stylesheet

    private var placeName: String? {
        coordinate.flatMap { model.cachedPlaceName(for: $0) }
    }

    var body: some View {
        NavigationLink {
            DayRelabelView(day: day, report: report)
        } label: {
            HStack(spacing: stylesheet.spacing.large) {
                Image(systemSymbol: .calendar)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                    Text(day.displayDate
                        .formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                        .font(.headline)
                    if let placeName {
                        Label(placeName, systemSymbol: .mappinAndEllipse)
                            .font(.subheadline)
                    }
                    Text(WhereFormat
                        .secondaryRegionCurrent(regions: Region.inCanonicalOrder(day.regions)
                            .map(\.localizedName).joined(separator: ", ")))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, stylesheet.spacing.xSmall)
            .task(id: coordinate) {
                guard let coordinate else { return }
                _ = await model.placeName(for: coordinate)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#if DEBUG
    #Preview("Region days") {
        RegionDaysView.snapshotPreviews
    }
#endif
