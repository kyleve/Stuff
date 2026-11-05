import Foundation
import Observation
import RegionKit

/// An unsaved, explicit map or coordinate selection. Opening the picker selects no new point.
@MainActor
@Observable
final class RecordingPlaceLocationModel: Identifiable {
    struct ID: Hashable { let value = UUID() }
    let id = ID()
    let initialCoordinate: Coordinate?
    var latitude: Double?
    var longitude: Double?

    init(coordinate: Coordinate?) {
        initialCoordinate = coordinate
        latitude = coordinate?.latitude
        longitude = coordinate?.longitude
    }

    var coordinate: Coordinate? {
        guard let latitude, let longitude, latitude.isFinite, longitude.isFinite,
              (-90 ... 90).contains(latitude), (-180 ... 180).contains(longitude)
        else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    func select(_ coordinate: Coordinate) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }
}
