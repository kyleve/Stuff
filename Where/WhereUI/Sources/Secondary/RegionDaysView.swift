import MapKit
import SwiftUI
import WhereCore

/// Drill-in from an Elsewhere card: the individual days that counted for a
/// region this year. This is the "see where those check-ins are" view — a map
/// of the points actually recorded in the region sits above a list of days,
/// each tappable to correct a wrong attribution via `DayRelabelView` and
/// labeled with the place it reverse-geocodes to.
struct RegionDaysView: View {
    @Environment(WhereSession.self) private var session

    let region: Region

    /// Raw per-day coordinates for this region, loaded asynchronously from the
    /// store. Drives the map pins and each row's representative point. Empty
    /// until loaded (and in previews/tests, which seed no raw samples).
    @State private var pins: [MapPin] = []
    @State private var coordinatesByDay: [Date: [Coordinate]] = [:]

    private var days: [DayPresence] {
        session.days(in: region)
    }

    var body: some View {
        content
            .navigationTitle(region.localizedName)
            .navigationBarTitleDisplayMode(.inline)
            // Keyed on the report (not just the year) so the map reloads after a
            // relabel changes which days count for this region.
            .task(id: session.report) { await loadLocations() }
    }

    private func loadLocations() async {
        // The day list is report-based (it honors manual overrides) while raw
        // GPS coordinates are not, so a relabeled-away day could otherwise keep
        // a stale pin on the map. Restrict pins/points to days still in the list.
        let listedDates = Set(days.map(\.date))
        let locations = await session.locations(in: region)
            .filter { listedDates.contains($0.date) }
        guard !Task.isCancelled else { return }
        coordinatesByDay = Dictionary(
            locations.map { ($0.date, $0.points.map(\.coordinate)) },
            uniquingKeysWith: { first, _ in first },
        )
        pins = MapPin.deduplicated(from: locations.flatMap(\.points).map(\.coordinate))
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
                Marker("", coordinate: pin.coordinate)
                    .tint(region.style.tint)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: UIConstants.Size.regionMapHeight)
        .accessibilityLabel(Strings.secondaryRegionMapAccessibility)
    }

    private var dayList: some View {
        List {
            Section {
                ForEach(days, id: \.date) { day in
                    NavigationLink {
                        DayRelabelView(day: day)
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

/// A map annotation for one recorded point. Coordinates are de-duplicated onto
/// a coarse grid so a day's GPS jitter collapses to a single pin and the map
/// isn't carpeted with overlapping markers.
private struct MapPin: Identifiable {
    let id: Int
    let coordinate: CLLocationCoordinate2D

    /// ~0.01° (~1 km) buckets, capped so a very dense region stays responsive.
    static func deduplicated(from coordinates: [Coordinate], limit: Int = 250) -> [MapPin] {
        var seen = Set<Int>()
        var pins: [MapPin] = []
        for coordinate in coordinates {
            let latBucket = Int((coordinate.latitude * 100).rounded())
            let lngBucket = Int((coordinate.longitude * 100).rounded())
            guard seen.insert(latBucket &* 100_000 &+ lngBucket).inserted else { continue }
            pins.append(MapPin(
                id: pins.count,
                coordinate: CLLocationCoordinate2D(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                ),
            ))
            if pins.count >= limit { break }
        }
        return pins
    }
}

/// One day in the region's list: the date, the place it reverse-geocodes to
/// (when a coordinate is known), and the regions it currently counts for so
/// the user can spot a wrong attribution at a glance.
private struct DayRow: View {
    let day: DayPresence
    let coordinate: Coordinate?

    @State private var placeName: String?

    var body: some View {
        HStack(spacing: UIConstants.Spacings.large) {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: UIConstants.Spacings.xxSmall) {
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
        .padding(.vertical, UIConstants.Spacings.xSmall)
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
            RegionDaysView(region: .other)
                .environment(PreviewSupport.elsewhereOnlySession())
        }
    }
#endif
