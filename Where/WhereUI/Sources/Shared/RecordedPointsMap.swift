import MapKit
import RegionKit
import SwiftUI
import WhereCore

/// One recorded GPS point to plot on `RecordedPointsMap`: its coordinate, the
/// originating fix's horizontal accuracy (for the uncertainty circle), and the
/// region it attributes to (which tints the pin). A day that spans several
/// regions — a flight, say — therefore draws each leg's points in that
/// region's color, so the fly-over `.other` points read distinctly from the
/// grounded endpoints.
struct RecordedMapPoint: Hashable {
    let coordinate: Coordinate
    let horizontalAccuracy: Double
    let region: Region
}

/// A map of recorded GPS points with per-region tinting and GPS uncertainty
/// circles. Extracted from `RegionDaysView` so the Elsewhere drill-in, the
/// flight-day detail view, and the "Fix this day" screen share one renderer.
/// Points are de-duplicated onto a coarse grid (per region) so a day's jitter
/// collapses to a single pin and the map isn't carpeted with markers.
struct RecordedPointsMap: View {
    let points: [RecordedMapPoint]

    @Environment(\.stylesheet) private var stylesheet

    private var regionMap: WhereStylesheet.RegionMapStyle {
        stylesheet.regionMap
    }

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(pins) { pin in
                if let radius = drawnUncertaintyRadius(for: pin) {
                    MapCircle(center: pin.coordinate, radius: radius)
                        .foregroundStyle(pin.region.style.tint
                            .opacity(regionMap.uncertaintyFillOpacity))
                        .stroke(
                            pin.region.style.tint.opacity(regionMap.uncertaintyStrokeOpacity),
                            lineWidth: regionMap.uncertaintyStrokeWidth,
                        )
                }
                Marker("", coordinate: pin.coordinate)
                    .tint(pin.region.style.tint)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: regionMap.height)
        .accessibilityLabel(Strings.secondaryRegionMapAccessibility)
    }

    private var pins: [Pin] {
        Pin.deduplicated(from: points)
    }

    /// Radius in meters to draw for a pin's GPS uncertainty, or `nil` when the
    /// fix is precise enough that a circle would just clutter the map. The cap
    /// is deliberately generous so the user sees close to the real radius (the
    /// translucent fill keeps the map readable underneath); it only reins in a
    /// pathologically coarse fix so it can't zoom the auto-framed map way out.
    private func drawnUncertaintyRadius(for pin: Pin) -> CLLocationDistance? {
        let minimumVisible = 25.0
        let maximumDrawn = 3000.0
        guard pin.horizontalAccuracy > minimumVisible else { return nil }
        return min(pin.horizontalAccuracy, maximumDrawn)
    }
}

/// A map annotation for one recorded point: its coordinate, uncertainty radius,
/// and attributed region (for tinting). Points are de-duplicated onto a coarse
/// grid *per region* so a day's jitter collapses to a single pin per area while
/// two regions that happen to share a grid cell each keep their own marker.
private struct Pin: Identifiable {
    let id: Int
    let coordinate: CLLocationCoordinate2D
    let horizontalAccuracy: CLLocationDistance
    let region: Region

    static func deduplicated(from points: [RecordedMapPoint], limit: Int = 250) -> [Pin] {
        struct Bucket: Hashable {
            let region: Region
            let cell: Int
        }
        var bestByBucket: [Bucket: RecordedMapPoint] = [:]
        var bucketOrder: [Bucket] = []
        for point in points {
            let latBucket = Int((point.coordinate.latitude * 100).rounded())
            let lngBucket = Int((point.coordinate.longitude * 100).rounded())
            let bucket = Bucket(region: point.region, cell: latBucket &* 100_000 &+ lngBucket)
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
            return Pin(
                id: index,
                coordinate: point.coordinate.clLocationCoordinate,
                horizontalAccuracy: point.horizontalAccuracy,
                region: point.region,
            )
        }
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
