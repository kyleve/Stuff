import CoreLocation
import Foundation
import WhereCore
import WhereData

@MainActor
final class AppleLocationBridge: NSObject, CLLocationManagerDelegate, LocationAuthorizationProviding, LocationWakeSource {
    private let locationManager: CLLocationManager
    private weak var trackingController: BackgroundTrackingController?
    private let regionRadius: CLLocationDistance = 150_000

    init(
        locationManager: CLLocationManager = CLLocationManager(),
        trackingController: BackgroundTrackingController? = nil,
    ) {
        self.locationManager = locationManager
        self.trackingController = trackingController
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        self.locationManager.allowsBackgroundLocationUpdates = true
        self.locationManager.pausesLocationUpdatesAutomatically = true
    }

    func attach(trackingController: BackgroundTrackingController) {
        self.trackingController = trackingController
    }

    func currentAuthorizationStatus() async -> TrackingAuthorizationStatus {
        map(locationManager.authorizationStatus)
    }

    func requestAlwaysAuthorization() async {
        locationManager.requestAlwaysAuthorization()
    }

    func startMonitoring(configuration: TrackingMonitoringConfiguration) async {
        if configuration.wantsSignificantLocationChanges {
            locationManager.startMonitoringSignificantLocationChanges()
        }

        if configuration.wantsVisitMonitoring {
            locationManager.startMonitoringVisits()
        }

        refreshRegions(configuration: configuration)
    }

    func refreshRegionMonitoring(configuration: TrackingMonitoringConfiguration) async {
        refreshRegions(configuration: configuration)
    }

    func stopMonitoring() async {
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopMonitoringVisits()

        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let trackingController else { return }
        let status = map(manager.authorizationStatus)
        Task {
            await trackingController.handleAuthorizationStatusChange(status)
        }
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let trackingController, let location = locations.last else { return }

        let event = TrackingWakeEvent(
            timestamp: location.timestamp,
            reason: .significantLocationChange,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
        )

        Task {
            await trackingController.handleWakeEvent(event)
        }
    }

    func locationManager(_: CLLocationManager, didVisit visit: CLVisit) {
        guard let trackingController else { return }

        let event = TrackingWakeEvent(
            timestamp: visit.arrivalDate == .distantPast ? Date() : visit.arrivalDate,
            reason: .visit,
            latitude: visit.coordinate.latitude,
            longitude: visit.coordinate.longitude,
            horizontalAccuracy: visit.horizontalAccuracy,
        )

        Task {
            await trackingController.handleWakeEvent(event)
        }
    }

    func locationManager(_: CLLocationManager, didEnterRegion region: CLRegion) {
        handleRegionWake(region: region)
    }

    func locationManager(_: CLLocationManager, didExitRegion region: CLRegion) {
        handleRegionWake(region: region)
    }

    private func refreshRegions(configuration: TrackingMonitoringConfiguration) {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }

        for jurisdiction in configuration.jurisdictionRegions.prefix(20) {
            guard let region = circularRegion(for: jurisdiction) else { continue }
            locationManager.startMonitoring(for: region)
        }
    }

    private func circularRegion(for jurisdiction: TaxJurisdiction) -> CLCircularRegion? {
        let coordinate: CLLocationCoordinate2D

        switch jurisdiction {
            case .state(.california):
                coordinate = CLLocationCoordinate2D(latitude: 36.7783, longitude: -119.4179)
            case .state(.newYork):
                coordinate = CLLocationCoordinate2D(latitude: 42.9538, longitude: -75.5268)
            case .state, .unknown:
                return nil
        }

        let region = CLCircularRegion(
            center: coordinate,
            radius: regionRadius,
            identifier: jurisdiction.abbreviation,
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        return region
    }

    private func handleRegionWake(region: CLRegion) {
        guard
            let trackingController,
            let circularRegion = region as? CLCircularRegion
        else {
            return
        }

        let event = TrackingWakeEvent(
            timestamp: Date(),
            reason: .regionBoundary,
            latitude: circularRegion.center.latitude,
            longitude: circularRegion.center.longitude,
        )

        Task {
            await trackingController.handleWakeEvent(event)
        }
    }

    private func map(_ status: CLAuthorizationStatus) -> TrackingAuthorizationStatus {
        switch status {
            case .notDetermined:
                .notDetermined
            case .restricted:
                .restricted
            case .denied:
                .denied
            case .authorizedWhenInUse:
                .authorizedWhenInUse
            case .authorizedAlways:
                .authorizedAlways
            @unknown default:
                .restricted
        }
    }
}
