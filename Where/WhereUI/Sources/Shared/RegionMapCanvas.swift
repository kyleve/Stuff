import MapKit
import RegionKit
import SnapshotKit
import SwiftUI

/// Deterministic stand-in for ``RegionMapView``'s live `Map` under snapshot
/// capture: the same outlines, drawn with the same fill/stroke styling over a
/// flat substrate, framed by the same enclosing-region math as the live
/// camera — identical layout, none of MapKit's cache/network-dependent
/// tile/label loading.
///
/// Project through MapKit's Mercator map points and fit the camera bounds
/// to the canvas. This also keeps high-latitude Canadian coastlines and
/// antimeridian islands in the same proportions as the live map.
struct RegionMapCanvas: View {
    let geometry: RegionMapGeometry
    let selectedTitle: String?
    /// The frame the live camera would use; `nil` (nothing to show) renders
    /// just the substrate.
    let region: MKCoordinateRegion?
    let style: (RegionOutline) -> RegionMapOverlayStyle

    var body: some View {
        Canvas { context, size in
            guard let region, size.width > 0, size.height > 0 else { return }
            let world = MKMapSize.world.width
            let halfLatitude = region.span.latitudeDelta / 2
            let north = MKMapPoint(CLLocationCoordinate2D(
                latitude: min(85.05112878, region.center.latitude + halfLatitude),
                longitude: region.center.longitude,
            ))
            let south = MKMapPoint(CLLocationCoordinate2D(
                latitude: max(-85.05112878, region.center.latitude - halfLatitude),
                longitude: region.center.longitude,
            ))
            let mapPointsPerPoint = max(
                world * region.span.longitudeDelta / 360 / size.width,
                (south.y - north.y) / size.height,
            )
            guard mapPointsPerPoint > 0 else { return }
            let rect = MKMapRect(
                x: north.x - mapPointsPerPoint * size.width / 2,
                y: (north.y + south.y - mapPointsPerPoint * size.height) / 2,
                width: mapPointsPerPoint * size.width,
                height: mapPointsPerPoint * size.height,
            )
            func point(for coordinate: Coordinate) -> CGPoint {
                let point = MKMapPoint(coordinate.clLocationCoordinate)
                let deltaX = (point.x - rect.midX + 1.5 * world)
                    .truncatingRemainder(dividingBy: world) - world / 2
                return CGPoint(
                    x: size.width / 2 + deltaX / mapPointsPerPoint,
                    y: (point.y - rect.minY) / mapPointsPerPoint,
                )
            }

            for outline in geometry.visible(in: rect, width: size.width, title: selectedTitle) {
                var path = Path()
                for ring in [outline.coordinates] + outline.holes {
                    guard let first = ring.first else { continue }
                    path.move(to: point(for: first))
                    for coordinate in ring.dropFirst() {
                        path.addLine(to: point(for: coordinate))
                    }
                    path.closeSubpath()
                }
                let appearance = style(outline)
                context.fill(path, with: .color(appearance.fill), style: FillStyle(eoFill: true))
                context.stroke(
                    path,
                    with: .color(appearance.stroke),
                    style: appearance.strokeStyle,
                )
            }
        }
        .background(Color(.secondarySystemBackground))
    }
}

#if DEBUG
    #Preview { RegionMapView.snapshotPreviews }
#endif
