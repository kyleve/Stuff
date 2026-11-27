import CoreLocation
import RegionKit
import WhereCore

extension Coordinate {
    /// The CoreLocation/MapKit representation. `Coordinate` deliberately
    /// stays CoreLocation-free in the model layer, so this bridge — used
    /// by every map view (`RegionDaysView` pins, `RegionMapView`
    /// polygons) — lives here in the UI layer instead.
    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension Sequence<Coordinate> {
    /// The receiver mapped to CoreLocation coordinates, e.g. for
    /// `MapPolygon(coordinates:)`.
    var clLocationCoordinates: [CLLocationCoordinate2D] {
        map(\.clLocationCoordinate)
    }
}
