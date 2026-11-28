import MapKit
import RegionKit
import SnapshotKit
import SwiftUI
import WhereCore

/// A raw observation with its effective attribution for marker tinting.
struct RecordedMapPoint: Hashable {
    enum Attribution: Hashable {
        case region(Region)
        case excluded
    }

    let coordinate: Coordinate
    let horizontalAccuracy: Double
    let attribution: Attribution

    init(coordinate: Coordinate, horizontalAccuracy: Double, attribution: Attribution) {
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
        self.attribution = attribution
    }

    init(coordinate: Coordinate, horizontalAccuracy: Double, region: Region) {
        self.init(
            coordinate: coordinate,
            horizontalAccuracy: horizontalAccuracy,
            attribution: .region(region),
        )
    }
}

/// Shared GPS map. Geometry is prepared by the owning model for large reviews.
struct RecordedPointsMap: View {
    let data: RecordedMapData
    let variant: WhereStylesheet.RegionMapStyle.Variant
    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles
    /// Capture infrastructure: remote MapKit tiles cannot settle deterministically.
    @Environment(\.isCapturingSnapshot) private var isCapturingSnapshot

    init(data: RecordedMapData, variant: WhereStylesheet.RegionMapStyle.Variant = .overview) {
        self.data = data
        self.variant = variant
    }

    init(points: [RecordedMapPoint]) {
        data = RecordedMapData(points: points, routes: [])
        variant = .overview
    }

    var body: some View {
        let viewport = stylesheet.regionMap[variant]
        let bounds = data.bounds(minimumSpanMeters: viewport.minimumSpanMeters)
        Group {
            if isCapturingSnapshot {
                RecordedMapCapture(
                    data: data,
                    variant: variant,
                    tint: tint(for:),
                    uncertaintyRadius: drawnUncertaintyRadius(for:),
                )
            } else {
                RecordedMapLive(
                    data: data,
                    bounds: bounds,
                    variant: variant,
                    tint: tint(for:),
                    uncertaintyRadius: drawnUncertaintyRadius(for:),
                )
            }
        }
        .frame(height: viewport.height)
        .accessibilityLabel(String(localized: .secondaryRegionMapAccessibility))
    }

    private func tint(for point: RecordedMapPoint) -> Color {
        switch point.attribution {
            case let .region(region): regionStyles.style(for: region).tint
            case .excluded: .secondary
        }
    }

    private func drawnUncertaintyRadius(for point: RecordedMapPoint) -> CLLocationDistance? {
        guard point.horizontalAccuracy.isFinite, point.horizontalAccuracy > 25 else { return nil }
        return min(point.horizontalAccuracy, 3000)
    }
}

#if DEBUG
    #Preview("Flight day") {
        RecordedPointsMap(points: [
            RecordedMapPoint(
                coordinate: Coordinate(latitude: 40.6413, longitude: -73.7781),
                horizontalAccuracy: 30,
                region: .newYork,
            ),
            RecordedMapPoint(
                coordinate: Coordinate(latitude: 39.53, longitude: -106.16),
                horizontalAccuracy: 200,
                region: .other,
            ),
            RecordedMapPoint(
                coordinate: Coordinate(latitude: 38.68, longitude: -116.90),
                horizontalAccuracy: 200,
                region: .other,
            ),
            RecordedMapPoint(
                coordinate: Coordinate(latitude: 37.6213, longitude: -122.3790),
                horizontalAccuracy: 30,
                region: .california,
            ),
        ])
    }
#endif
