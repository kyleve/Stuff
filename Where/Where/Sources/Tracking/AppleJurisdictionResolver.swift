import CoreLocation
import Foundation
import WhereCore

actor AppleJurisdictionResolver: JurisdictionResolving {
    private let geocoder = CLGeocoder()

    func jurisdiction(for event: TrackingWakeEvent) async -> TaxJurisdiction {
        let location = CLLocation(
            latitude: event.latitude,
            longitude: event.longitude,
        )

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else {
                return .unknown
            }

            guard placemark.isoCountryCode == "US" else {
                return .unknown
            }

            guard
                let administrativeArea = placemark.administrativeArea,
                let state = USState(rawValue: administrativeArea.uppercased())
            else {
                return .unknown
            }

            return .state(state)
        } catch {
            return .unknown
        }
    }
}
