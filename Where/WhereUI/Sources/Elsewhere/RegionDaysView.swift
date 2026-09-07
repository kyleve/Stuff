import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Drill-in from an Elsewhere card: the individual days that counted for a
/// region this year. This is the "see where those check-ins are" view — a map
/// of the points actually recorded in the region sits above a list of days,
/// each tappable to correct a wrong attribution via `DayRelabelView` and
/// labeled with the place it reverse-geocodes to.
struct RegionDaysView: View {
    let region: Region
    let report: YearReportModel

    /// Raw per-day coordinates for this region, loaded asynchronously from the
    /// store. `mapPoints` drives the map pins; `coordinatesByDay` feeds each
    /// row's representative point. Empty until loaded (and in previews/tests,
    /// which seed no raw samples).
    @State private var mapPoints: [RecordedMapPoint] = []
    @State private var coordinatesByDay: [CalendarDay: [Coordinate]] = [:]

    private var days: [DayPresence] {
        report.days(in: region)
    }

    var body: some View {
        content
            .navigationTitle(region.localizedName)
            .navigationBarTitleDisplayMode(.inline)
            // Keyed on the report (not just the year) so the map reloads after a
            // relabel changes which days count for this region.
            .task(id: report.report) { await loadLocations() }
    }

    private func loadLocations() async {
        // The day list is report-based (it honors manual overrides) while raw
        // GPS coordinates are not, so a relabeled-away day could otherwise keep
        // a stale pin on the map. Restrict pins/points to days still in the list.
        let listedDays = Set(days.map(\.day))
        let locations = await report.locations(in: region)
            .filter { listedDays.contains($0.day) }
        guard !Task.isCancelled else { return }
        coordinatesByDay = Dictionary(
            locations.map { ($0.day, $0.points.map(\.coordinate)) },
            uniquingKeysWith: { first, _ in first },
        )
        mapPoints = locations.flatMap(\.points).map {
            RecordedMapPoint(
                coordinate: $0.coordinate,
                horizontalAccuracy: $0.horizontalAccuracy,
                region: region,
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if days.isEmpty {
            ContentUnavailableView {
                Label(
                    String(localized: .secondaryRegionEmptyTitle),
                    systemSymbol: .checkmarkCircle,
                )
            } description: {
                Text(String(localized: .secondaryRegionEmptyDescription))
            }
        } else {
            VStack(spacing: 0) {
                if !mapPoints.isEmpty {
                    RecordedPointsMap(points: mapPoints)
                }
                dayList
            }
        }
    }

    private var dayList: some View {
        List {
            Section {
                ForEach(days, id: \.day) { day in
                    NavigationLink {
                        DayRelabelView(day: day, report: report)
                    } label: {
                        DayRow(day: day, coordinate: coordinatesByDay[day.day]?.first)
                    }
                }
            } footer: {
                Text(String(localized: .secondaryRegionFooter))
            }
        }
        .accessibilityIdentifier("where_region_days_list")
    }
}

/// One day in the region's list: the date, the place it reverse-geocodes to
/// (when a coordinate is known), and the regions it currently counts for so
/// the user can spot a wrong attribution at a glance.
private struct DayRow: View {
    let day: DayPresence
    let coordinate: Coordinate?

    @State private var placeName: String?

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        HStack(spacing: stylesheet.spacing.large) {
            Image(systemSymbol: .calendar)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                Text(dateText)
                    .font(.headline)
                if let placeName {
                    Label(placeName, systemSymbol: .mappinAndEllipse)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                Text(WhereFormat.secondaryRegionCurrent(regions: regionsText))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, stylesheet.spacing.xSmall)
        .task(id: coordinate) {
            guard let coordinate else { return }
            placeName = await LocationNamer.shared.name(for: coordinate)
        }
        .accessibilityElement(children: .combine)
    }

    private var dateText: String {
        day.displayDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    /// Region names joined in canonical order so the caption is stable.
    private var regionsText: String {
        Region.inCanonicalOrder(day.regions)
            .map(\.localizedName)
            .joined(separator: ", ")
    }
}

#if DEBUG
    extension RegionDaysView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "WithData", configurations: .fullContentScreenDefaults) {
                NavigationStack {
                    RegionDaysView(
                        region: .other,
                        report: PreviewSupport.elsewhereOnlyYearReportModel(),
                    )
                }
            }
        }
    }

    #Preview {
        RegionDaysView.snapshotPreviews
    }
#endif

#if DEBUG
    extension RegionDaysView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            RegionDaysView.self,
            title: "Region Days",
            routes: [
                .push(to: DayRelabelView.flyoverID),
            ],
        )
    }
#endif
