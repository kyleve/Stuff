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
///
/// Confined to `@MainActor` because `CLLocationManager` must be created and
/// driven on a thread with a run loop. Delegate callbacks land on the run
/// loop of the thread the manager was constructed on (the main thread here),
/// so the `CLLocationManagerDelegate` methods stay main-actor isolated too.
@MainActor
public final class CoreLocationSource: NSObject, LocationSource {
    public nonisolated let sampleStream: AsyncStream<LocationSample>
    public nonisolated let authorizationStream: AsyncStream<LocationAuthorizationStatus>

    private let manager: CLLocationManager
    private nonisolated let sampleContinuation: AsyncStream<LocationSample>.Continuation
    private nonisolated let authContinuation: AsyncStream<LocationAuthorizationStatus>.Continuation

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

    fileprivate nonisolated static func status(for raw: CLAuthorizationStatus)
        -> LocationAuthorizationStatus
    {
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

/// Delegate methods are intentionally `nonisolated`: they only yield to the
/// (thread-safe) `AsyncStream.Continuation`s, never touch the `@MainActor`
/// state, and satisfy a non-isolated `@objc` protocol. CoreLocation still
/// delivers callbacks on the main run loop (the manager was constructed on
/// `@MainActor`), so the manager API contract is respected.
extension CoreLocationSource: CLLocationManagerDelegate {
    public nonisolated func locationManager(
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

    public nonisolated func locationManager(
        _: CLLocationManager,
        didVisit visit: CLVisit,
    ) {
        // Core Location may deliver visits late or with only one of the two
        // timestamps populated. Prefer arrival; fall back to departure before
        // resorting to "now", since "now" would attribute the visit to the
        // delivery time and could land it on the wrong day/year.
        let timestamp: Date = if visit.arrivalDate != .distantPast {
            visit.arrivalDate
        } else if visit.departureDate != .distantPast {
            visit.departureDate
        } else {
            Date()
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

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authContinuation.yield(Self.status(for: manager.authorizationStatus))
    }
}
