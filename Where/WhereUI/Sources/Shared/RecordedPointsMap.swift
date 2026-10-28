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
                captureSurface
            } else {
                Map(
                    initialPosition: variant == .overview || bounds
                        .isNull ? .automatic : .rect(bounds),
                    interactionModes: variant == .overview ? .all : [],
                ) {
                    ForEach(data.routes) { route in
                        MapPolyline(coordinates: route.coordinates.clLocationCoordinates)
                            .stroke(.secondary, lineWidth: stylesheet.regionMap.routeLineWidth)
                    }
                    ForEach(data.pins) { pin in
                        let tint = tint(for: pin.point)
                        if let radius = drawnUncertaintyRadius(for: pin.point) {
                            MapCircle(
                                center: pin.point.coordinate.clLocationCoordinate,
                                radius: radius,
                            )
                            .foregroundStyle(tint
                                .opacity(stylesheet.regionMap.uncertaintyFillOpacity))
                            .stroke(
                                tint.opacity(stylesheet.regionMap.uncertaintyStrokeOpacity),
                                lineWidth: stylesheet.regionMap.uncertaintyStrokeWidth,
                            )
                        }
                        Marker("", coordinate: pin.point.coordinate.clLocationCoordinate).tint(tint)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
            }
        }
        .frame(height: viewport.height)
        .accessibilityLabel(String(localized: .secondaryRegionMapAccessibility))
    }

    /// Same GPS overlays and height as the live map, over a deterministic tile substrate.
    private var captureSurface: some View {
        Canvas { context, size in
            let bounds = data
                .bounds(minimumSpanMeters: stylesheet.regionMap[variant].minimumSpanMeters)
            let inset = stylesheet.regionMap.captureInset
            guard !bounds.isNull, size.width > 2 * inset, size.height > 2 * inset else { return }
            let scale = max(
                bounds.width / (size.width - 2 * inset),
                bounds.height / (size.height - 2 * inset),
            )
            func point(_ coordinate: Coordinate) -> CGPoint {
                let projected = data.projected(coordinate)
                return CGPoint(
                    x: size.width / 2 + (projected.x - bounds.midX) / scale,
                    y: size.height / 2 + (projected.y - bounds.midY) / scale,
                )
            }
            for route in data.routes {
                let path = Path { path in
                    for (index, coordinate) in route.coordinates.enumerated() {
                        if index == 0 { path.move(to: point(coordinate)) }
                        else { path.addLine(to: point(coordinate)) }
                    }
                }
                context.stroke(
                    path,
                    with: .style(.secondary),
                    lineWidth: stylesheet.regionMap.routeLineWidth,
                )
            }
            for pin in data.pins {
                let center = point(pin.point.coordinate)
                let tint = tint(for: pin.point)
                if let meters = drawnUncertaintyRadius(for: pin.point) {
                    let radius = meters *
                        MKMapPointsPerMeterAtLatitude(pin.point.coordinate.latitude) / scale
                    let circle = Path(ellipseIn: CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2,
                    ))
                    context.fill(
                        circle,
                        with: .color(tint.opacity(stylesheet.regionMap.uncertaintyFillOpacity)),
                    )
                    context.stroke(
                        circle,
                        with: .color(tint.opacity(stylesheet.regionMap.uncertaintyStrokeOpacity)),
                        lineWidth: stylesheet.regionMap.uncertaintyStrokeWidth,
                    )
                }
                let diameter = stylesheet.regionMap.capturePointDiameter
                let dot = Path(ellipseIn: CGRect(
                    x: center.x - diameter / 2,
                    y: center.y - diameter / 2,
                    width: diameter,
                    height: diameter,
                ))
                context.fill(dot, with: .color(tint))
            }
        }
        .background(Color(.secondarySystemBackground))
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
