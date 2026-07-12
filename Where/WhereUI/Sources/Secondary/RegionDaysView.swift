import MapKit
import RegionKit
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
    /// store. Drives the map pins and each row's representative point. Empty
    /// until loaded (and in previews/tests, which seed no raw samples).
    @State private var pins: [MapPin] = []
    @State private var coordinatesByDay: [Date: [Coordinate]] = [:]

    @Environment(\.stylesheet) private var stylesheet

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
        let listedDates = Set(days.map(\.date))
        let locations = await report.locations(in: region)
            .filter { listedDates.contains($0.date) }
        guard !Task.isCancelled else { return }
        coordinatesByDay = Dictionary(
            locations.map { ($0.date, $0.points.map(\.coordinate)) },
            uniquingKeysWith: { first, _ in first },
        )
        pins = MapPin.deduplicated(from: locations.flatMap(\.points))
    }

    @ViewBuilder
    private var content: some View {
        if days.isEmpty {
            ContentUnavailableView {
                Label(Strings.secondaryRegionEmptyTitle, systemImage: "checkmark.circle")
            } description: {
                Text(Strings.secondaryRegionEmptyDescription)
            }
        } else {
            VStack(spacing: 0) {
                if !pins.isEmpty {
                    map
                }
                dayList
            }
        }
    }

    private var map: some View {
        Map(initialPosition: .automatic) {
            ForEach(pins) { pin in
                if let radius = drawnUncertaintyRadius(for: pin) {
                    MapCircle(center: pin.coordinate, radius: radius)
                        .foregroundStyle(region.style.tint.opacity(0.15))
                        .stroke(region.style.tint.opacity(0.6), lineWidth: 1)
                }
                Marker("", coordinate: pin.coordinate)
                    .tint(region.style.tint)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: stylesheet.size.regionMapHeight)
        .accessibilityLabel(Strings.secondaryRegionMapAccessibility)
    }

    /// Radius in meters to draw for a pin's GPS uncertainty, or `nil` when the
    /// fix is precise enough that a circle would just clutter the map. The cap
    /// is deliberately generous so the user sees close to the real radius (the
    /// translucent fill keeps the map readable underneath); it only reins in a
    /// pathologically coarse fix so it can't zoom the auto-framed map way out.
    private func drawnUncertaintyRadius(for pin: MapPin) -> CLLocationDistance? {
        let minimumVisible = 25.0
        let maximumDrawn = 3000.0
        guard pin.horizontalAccuracy > minimumVisible else { return nil }
        return min(pin.horizontalAccuracy, maximumDrawn)
    }

    private var dayList: some View {
        List {
            Section {
                ForEach(days, id: \.date) { day in
                    NavigationLink {
                        DayRelabelView(day: day, report: report)
                    } label: {
                        DayRow(day: day, coordinate: coordinatesByDay[day.date]?.first)
                    }
                }
            } footer: {
                Text(Strings.secondaryRegionFooter)
            }
        }
        .accessibilityIdentifier("where_region_days_list")
    }
}

/// A map annotation for one recorded point, with its GPS uncertainty radius.
/// Points are de-duplicated onto a coarse grid so a day's jitter collapses to a
/// single pin and the map isn't carpeted with overlapping markers.
private struct MapPin: Identifiable {
    let id: Int
    let coordinate: CLLocationCoordinate2D
    let horizontalAccuracy: CLLocationDistance

    /// ~0.01° (~1 km) buckets, capped so a very dense region stays responsive.
    /// When several points land in one bucket the most accurate (smallest
    /// radius) wins, so the pin sits on the best fix and the drawn uncertainty
    /// circle reflects it rather than a coarse outlier.
    static func deduplicated(from points: [RegionDayPoint], limit: Int = 250) -> [MapPin] {
        var bestByBucket: [Int: RegionDayPoint] = [:]
        var bucketOrder: [Int] = []
        for point in points {
            let latBucket = Int((point.coordinate.latitude * 100).rounded())
            let lngBucket = Int((point.coordinate.longitude * 100).rounded())
            let bucket = latBucket &* 100_000 &+ lngBucket
            if let existing = bestByBucket[bucket] {
                if point.horizontalAccuracy < existing.horizontalAccuracy {
                    bestByBucket[bucket] = point
                }
            } else {
                bestByBucket[bucket] = point
                bucketOrder.append(bucket)
            }
        }
        return bucketOrder.prefix(limit).enumerated().compactMap { index, bucket in
            guard let point = bestByBucket[bucket] else { return nil }
            return MapPin(
                id: index,
                coordinate: point.coordinate.clLocationCoordinate,
                horizontalAccuracy: point.horizontalAccuracy,
            )
        }
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
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                Text(dateText)
                    .font(.headline)
                if let placeName {
                    Label(placeName, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                Text(Strings.secondaryRegionCurrent(regions: regionsText))
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
        day.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    /// Region names joined in declaration order so the caption is stable.
    private var regionsText: String {
        Region.allCases
            .filter { day.regions.contains($0) }
            .map(\.localizedName)
            .joined(separator: ", ")
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            RegionDaysView(region: .other, report: PreviewSupport.elsewhereOnlyYearReportModel())
        }
    }
#endif
