import CoreLocation
import Foundation
import WhereCore

/// `LocationSource` driven by `CLLocationManager` using the two low-power
/// signals appropriate for "what state am I in today" tracking:
///
/// - `startMonitoringSignificantLocationChanges()` — wakes the app when the
///   user moves a significant distance, even after termination, with no
///   bespoke background runtime.
/// - `startMonitoringVisits()` — wakes the app on confirmed arrivals and
///   departures at the same location, again across launches.
///
/// Neither runs on a heartbeat; both are appropriate for the "did I cross a
/// state line today" question while keeping battery impact negligible.
///
/// Authorization changes are surfaced on `authorizationStream` so the UI
/// layer can drive the prompt without importing CoreLocation.
public final class CoreLocationSource: NSObject, LocationSource, @unchecked Sendable {
    public let sampleStream: AsyncStream<LocationSample>
    public let authorizationStream: AsyncStream<LocationAuthorizationStatus>

    private let manager: CLLocationManager
    private let sampleContinuation: AsyncStream<LocationSample>.Continuation
    private let authContinuation: AsyncStream<LocationAuthorizationStatus>.Continuation

    override public init() {
        var sampleCont: AsyncStream<LocationSample>.Continuation!
        sampleStream = AsyncStream { sampleCont = $0 }
        sampleContinuation = sampleCont

        var authCont: AsyncStream<LocationAuthorizationStatus>.Continuation!
        authorizationStream = AsyncStream { authCont = $0 }
        authContinuation = authCont

        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        authContinuation.yield(Self.status(for: manager.authorizationStatus))
    }

    public func start() async {
        manager.startMonitoringSignificantLocationChanges()
        manager.startMonitoringVisits()
    }

    public func stop() async {
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
    }

    public func requestAlwaysAuthorization() async {
        manager.requestAlwaysAuthorization()
    }

    fileprivate static func status(for raw: CLAuthorizationStatus) -> LocationAuthorizationStatus {
        switch raw {
            case .notDetermined: .notDetermined
            case .restricted: .restricted
            case .denied: .denied
            case .authorizedAlways: .authorizedAlways
            case .authorizedWhenInUse: .authorizedWhenInUse
            @unknown default: .notDetermined
        }
    }
}

extension CoreLocationSource: CLLocationManagerDelegate {
    public func locationManager(
        _: CLLocationManager,
        didUpdateLocations locations: [CLLocation],
    ) {
        for location in locations {
            let sample = LocationSample(
                timestamp: location.timestamp,
                coordinate: Coordinate(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                ),
                horizontalAccuracy: location.horizontalAccuracy,
                source: .gpsSignificantChange,
            )
            sampleContinuation.yield(sample)
        }
    }

    public func locationManager(
        _: CLLocationManager,
        didVisit visit: CLVisit,
    ) {
        let timestamp: Date = if visit.arrivalDate == .distantPast {
            Date()
        } else {
            visit.arrivalDate
        }
        let sample = LocationSample(
            timestamp: timestamp,
            coordinate: Coordinate(
                latitude: visit.coordinate.latitude,
                longitude: visit.coordinate.longitude,
            ),
            horizontalAccuracy: visit.horizontalAccuracy,
            source: .gpsVisit,
        )
        sampleContinuation.yield(sample)
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authContinuation.yield(Self.status(for: manager.authorizationStatus))
    }
}
