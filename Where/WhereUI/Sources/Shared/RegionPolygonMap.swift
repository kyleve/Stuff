import MapKit
import RegionKit
import SwiftUI

/// Indexes polygon bounds once at
/// load. The exact source rings remain available as the camera approaches an island.
final class RegionMapGeometry: Sendable {
    private struct Part {
        let outline: RegionOutline
        let bounds: MKMapRect
        let extent: Double
    }

    private let parts: [Part]
    private let details = DetailCache()

    init(outlines: [RegionOutline]) {
        parts = outlines.compactMap { outline in
            guard let box = BoundingBox.enclosing([outline]) else { return nil }
            let northWest = MKMapPoint(CLLocationCoordinate2D(
                latitude: box.maxLatitude,
                longitude: box.minLongitude,
            ))
            let southEast = MKMapPoint(CLLocationCoordinate2D(
                latitude: box.minLatitude,
                longitude: box.maxLongitude,
            ))
            var bounds = MKMapRect(
                x: northWest.x,
                y: northWest.y,
                width: southEast.x - northWest.x,
                height: southEast.y - northWest.y,
            )
            if box.maxLongitude - box.minLongitude > 180,
               let longitude = LongitudeSpan.enclosing(outline.coordinates.lazy.map(\.longitude))
            {
                let worldWidth = MKMapSize.world.width
                bounds.origin
                    .x = (longitude.center - longitude.degrees / 2 + 180) / 360 * worldWidth
                bounds.size.width = longitude.degrees / 360 * worldWidth
            }
            return Part(
                outline: outline,
                bounds: bounds,
                extent: max(bounds.width, bounds.height),
            )
        }.sorted { $0.extent > $1.extent }
    }

    /// Within each power-of-two zoom band keep all land at least a screen
    /// point across. At high zoom also cull the offscreen islands.
    func visible(in rect: MKMapRect, width: CGFloat, title: String? = nil) -> [RegionOutline] {
        guard let extent = minimumExtent(in: rect, width: width) else { return [] }
        return visibleParts(in: rect, title: title, minimumExtent: extent).map(\.outline)
    }

    func drawableOutlines(
        in rect: MKMapRect,
        width: CGFloat,
        title: String?,
    ) async throws -> [RegionOutline] {
        try await details.outlines(for: self, in: rect, width: width, title: title)
    }

    fileprivate func minimumExtent(in rect: MKMapRect, width: CGFloat) -> Double? {
        guard width > 0, rect.width > 0, rect.width.isFinite else { return nil }
        return pow(2, floor(log2(rect.width / width)))
    }

    private func visibleParts(in rect: MKMapRect, title: String?, minimumExtent: Double) -> [Part] {
        let visible = rect.insetBy(dx: -rect.width / 4, dy: -rect.height / 4)
        let west = visible.offsetBy(dx: -MKMapSize.world.width, dy: 0)
        let east = visible.offsetBy(dx: MKMapSize.world.width, dy: 0)
        return parts.prefix(while: { $0.extent >= minimumExtent }).filter { part in
            (title == nil || title == part.outline.title)
                &&
                (visible.intersects(part.bounds) || west.intersects(part.bounds) || east
                    .intersects(part.bounds))
        }
    }

    /// Retain the detailed coastlines at the current zoom while the map pans.
    /// Smaller rings are cheap to draw at their complete source fidelity.
    private actor DetailCache {
        private var zoomExtent: Double?
        private var simplified: [RegionOutline.ID: RegionOutline] = [:]

        func outlines(
            for geometry: RegionMapGeometry,
            in rect: MKMapRect,
            width: CGFloat,
            title: String?,
        ) throws -> [RegionOutline] {
            guard let extent = geometry.minimumExtent(in: rect, width: width) else { return [] }
            if extent != zoomExtent {
                simplified.removeAll(keepingCapacity: true)
                zoomExtent = extent
            }
            let visible = geometry.visibleParts(in: rect, title: title, minimumExtent: extent)
            return try visible.map { part in
                try Task.checkCancellation()
                let outline = part.outline
                guard outline.coordinates.count > 256 || outline.holes
                    .contains(where: { $0.count > 256 }) else { return outline }
                if let cached = simplified[outline.id] {
                    return cached
                }
                let rendered = try RegionGeometrySimplifier.simplify(
                    [outline],
                    tolerance: extent / (4 * part.extent),
                ).first ?? outline
                simplified[outline.id] = rendered
                return rendered
            }
        }
    }
}

extension RegionOutline {
    /// MapKit uses explicit interior polygons, independent of ring winding.
    var mapPolygon: MKPolygon {
        let world = MKMapSize.world.width
        let anchor = coordinates.first.map { MKMapPoint($0.clLocationCoordinate).x } ?? 0
        func points(in ring: [Coordinate]) -> [MKMapPoint] {
            ring.map { coordinate in
                var point = MKMapPoint(coordinate.clLocationCoordinate)
                // Keep both sides of an Aleutian island in the same copy of the map.
                if point.x - anchor > world / 2 {
                    point.x -= world
                }
                if anchor - point.x > world / 2 {
                    point.x += world
                }
                return point
            }
        }
        let interiors = holes.map { ring in
            MKPolygon(points: points(in: ring), count: ring.count)
        }
        return MKPolygon(
            points: points(in: coordinates),
            count: coordinates.count,
            interiorPolygons: interiors,
        )
    }
}

/// The map camera filters the outlines drawn in its viewport.
struct RegionPolygonMap: View {
    let geometry: RegionMapGeometry
    var selectedTitle: String?
    @Binding var position: MapCameraPosition
    let style: (RegionOutline) -> RegionMapOverlayStyle
    @State private var visibleRect = MKMapRect.world
    @State private var width: CGFloat = 0
    @State private var drawing = Drawing()

    private struct Drawing {
        struct Detail: Equatable {
            let geometry: ObjectIdentifier
            let zoomExtent: Double?
        }

        var detail: Detail?
        var polygons: [DisplayedPolygon] = []
    }

    private struct DisplayedPolygon: Identifiable {
        let outline: RegionOutline
        let polygon: MKPolygon
        var id: RegionOutline.ID {
            outline.id
        }
    }

    private struct Request: Equatable {
        let geometry: ObjectIdentifier
        let viewport: CGRect
        let width: CGFloat
        let title: String?
    }

    var body: some View {
        let request = Request(geometry: ObjectIdentifier(geometry), viewport: CGRect(
            x: visibleRect.minX,
            y: visibleRect.minY,
            width: visibleRect.width,
            height: visibleRect.height,
        ), width: width, title: selectedTitle)
        Map(position: $position) {
            ForEach(drawing.polygons) { part in
                let appearance = style(part.outline)
                MapPolygon(part.polygon)
                    .foregroundStyle(appearance.fill)
                    .stroke(appearance.stroke, style: appearance.strokeStyle)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onMapCameraChange(frequency: .onEnd) { visibleRect = $0.rect }
        .task(id: request) {
            do {
                let visible = try await geometry.drawableOutlines(
                    in: visibleRect,
                    width: width,
                    title: selectedTitle,
                )
                try Task.checkCancellation()
                let detail = Drawing.Detail(
                    geometry: request.geometry,
                    zoomExtent: geometry.minimumExtent(in: visibleRect, width: width),
                )
                // Panning keeps coastlines at the same fidelity. Retain the
                // native polygon for every component that stayed in view.
                let previous = drawing.detail == detail
                    ? Dictionary(uniqueKeysWithValues: drawing.polygons.map { ($0.id, $0) }) : [:]
                drawing = Drawing(detail: detail, polygons: visible.map {
                    previous[$0.id] ?? DisplayedPolygon(outline: $0, polygon: $0.mapPolygon)
                })
            } catch is CancellationError {
                return
            } catch {
                assertionFailure("Unexpected map geometry simplification failure: \(error)")
            }
        }
    }
}

struct RegionMapOverlayStyle {
    let fill: Color
    let stroke: Color
    let lineWidth: CGFloat

    var strokeStyle: StrokeStyle {
        .regionOutline(lineWidth: lineWidth)
    }
}

#if DEBUG
    #Preview("California") { CaliforniaPolygonPreview() }

    private struct CaliforniaPolygonPreview: View {
        @State private var position = MapCameraPosition.region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37, longitude: -119),
            span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12),
        ))
        @State private var geometry: RegionMapGeometry?

        var body: some View {
            Group {
                if let geometry {
                    RegionPolygonMap(geometry: geometry, position: $position) { _ in
                        RegionMapOverlayStyle(
                            fill: .accentColor.opacity(0.25),
                            stroke: .accentColor,
                            lineWidth: 1,
                        )
                    }
                } else {
                    ProgressView()
                }
            }
            .task {
                geometry = await RegionMapGeometry(outlines: RegionGeometryCatalog
                    .displayOutlines(for: .california))
            }
        }
    }

#endif
