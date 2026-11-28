import MapKit
import RegionKit
import SnapshotKit
import SwiftUI
import WhereCore

struct RecordedMapLive: View {
    @Environment(\.stylesheet) private var stylesheet
    let data: RecordedMapData
    let bounds: MKMapRect
    let variant: WhereStylesheet.RegionMapStyle.Variant
    let tint: (RecordedMapPoint) -> Color
    let uncertaintyRadius: (RecordedMapPoint) -> CLLocationDistance?

    var body: some View {
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
                let tint = tint(pin.point)
                if let radius = uncertaintyRadius(pin.point) {
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

#if DEBUG
    #Preview { RecordedPointsMap(points: []).whereBroadwayRoot() }
#endif
