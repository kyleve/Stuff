import MapKit
import RegionKit
import SnapshotKit
import SwiftUI
import WhereCore

/// Draws the production GPS overlays on a deterministic background for captures.
struct RecordedMapCapture: View {
    @Environment(\.stylesheet) private var stylesheet
    let data: RecordedMapData
    let variant: WhereStylesheet.RegionMapStyle.Variant
    let tint: (RecordedMapPoint) -> Color
    let uncertaintyRadius: (RecordedMapPoint) -> CLLocationDistance?

    var body: some View {
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
                        if index == 0 {
                            path.move(to: point(coordinate))
                        } else {
                            path.addLine(to: point(coordinate))
                        }
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
                let tint = tint(pin.point)
                if let meters = uncertaintyRadius(pin.point) {
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
}

#if DEBUG
    #Preview {
        RecordedPointsMap(points: []).environment(\.isCapturingSnapshot, true).whereBroadwayRoot()
    }
#endif
