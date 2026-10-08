import MapKit
import RegionKit
import WhereCore

/// Render-ready GPS geometry. Limits affect display only, never reviewed evidence.
struct RecordedMapData {
    struct Pin: Identifiable {
        let id: Int
        let point: RecordedMapPoint
    }

    struct Route: Identifiable {
        let id: FlightAssessment.RecordingSource
        let coordinates: [Coordinate]
    }

    static let maximumPins = 250
    static let maximumRoutePoints = 2048
    static let empty = RecordedMapData(points: [], routes: [])

    let pins: [Pin]
    let routes: [Route]
    let captureBounds: MKMapRect
    private let referenceX: Double

    init(points: [RecordedMapPoint], routes: [Route]) {
        struct Bucket: Hashable {
            let attribution: RecordedMapPoint.Attribution
            let latitude: Int
            let longitude: Int
        }
        var bestByBucket: [Bucket: RecordedMapPoint] = [:]
        var bucketOrder: [Bucket] = []
        for point in points where Self.isValid(point.coordinate) {
            let bucket = Bucket(
                attribution: point.attribution,
                latitude: Int((point.coordinate.latitude * 100).rounded()),
                longitude: Int((point.coordinate.longitude * 100).rounded()),
            )
            if let existing = bestByBucket[bucket] {
                if point.horizontalAccuracy < existing.horizontalAccuracy {
                    bestByBucket[bucket] = point
                }
            } else {
                bestByBucket[bucket] = point
                bucketOrder.append(bucket)
            }
        }
        pins = Self.spread(bucketOrder, limit: Self.maximumPins).enumerated()
            .compactMap { index, key in
                bestByBucket[key].map { Pin(id: index, point: $0) }
            }
        self.routes = routes.map {
            Route(id: $0.id, coordinates: Self.spread(
                $0.coordinates.filter(Self.isValid),
                limit: Self.maximumRoutePoints,
            ))
        }.filter { !$0.coordinates.isEmpty }
        let coordinates = pins.map(\.point.coordinate) + self.routes.flatMap(\.coordinates)
        let reference = coordinates.first.map { MKMapPoint($0.clLocationCoordinate).x } ?? 0
        referenceX = reference
        let projected = coordinates.map { Self.project($0, relativeTo: reference) }
        if let minX = projected.map(\.x).min(), let maxX = projected.map(\.x).max(),
           let minY = projected.map(\.y).min(), let maxY = projected.map(\.y).max()
        {
            captureBounds = MKMapRect(
                x: minX,
                y: minY,
                width: max(1, maxX - minX),
                height: max(1, maxY - minY),
            )
        } else {
            captureBounds = .null
        }
    }

    func projected(_ coordinate: Coordinate) -> MKMapPoint {
        Self.project(coordinate, relativeTo: referenceX)
    }

    /// Gives an individual fix geographic context without cropping larger routes.
    func bounds(minimumSpanMeters: Double) -> MKMapRect {
        guard !captureBounds.isNull, minimumSpanMeters > 0,
              let coordinate = pins.first?.point.coordinate ?? routes.first?.coordinates.first
        else { return captureBounds }
        let minimumSpan = min(
            MKMapRect.world.width,
            minimumSpanMeters * MKMapPointsPerMeterAtLatitude(coordinate.latitude),
        )
        guard minimumSpan > captureBounds.width || minimumSpan > captureBounds.height
        else { return captureBounds }
        let width = max(captureBounds.width, minimumSpan)
        let height = max(captureBounds.height, minimumSpan)
        return MKMapRect(
            x: captureBounds.midX - width / 2,
            y: captureBounds.midY - height / 2,
            width: width,
            height: height,
        )
    }

    private static func project(
        _ coordinate: Coordinate,
        relativeTo referenceX: Double,
    ) -> MKMapPoint {
        var point = MKMapPoint(coordinate.clLocationCoordinate)
        let width = MKMapRect.world.size.width
        if point.x - referenceX > width / 2 { point.x -= width }
        if point.x - referenceX < -width / 2 { point.x += width }
        return point
    }

    private static func isValid(_ coordinate: Coordinate) -> Bool {
        coordinate.latitude.isFinite && coordinate.longitude.isFinite
            && (-90 ... 90).contains(coordinate.latitude) && (-180 ... 180)
            .contains(coordinate.longitude)
    }

    /// Select across the complete sequence, including both ends, rather than truncating the trip.
    private static func spread<Value>(_ values: [Value], limit: Int) -> [Value] {
        guard values.count > limit else { return values }
        return (0 ..< limit).map { values[$0 * (values.count - 1) / (limit - 1)] }
    }
}
