import CoreLocation
import Foundation

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
/// Authorization is exposed via a single throwing `requestPermission()`.
/// Always-authorization is required for this app, so the call resolves
/// successfully only when the user grants Always, and otherwise throws a
/// `LocationPermissionDeniedError` the UI can `do/catch` on.
///
/// The class is `@MainActor` so `CLLocationManager` is created on a thread
/// that has a run loop (CoreLocation requires this). The
/// `CLLocationManagerDelegate` methods are marked `nonisolated` because the
/// `@objc` protocol contract doesn't permit `@MainActor` requirements; that
/// is safe here because the delegate code paths only `yield` to
/// `AsyncStream.Continuation` (thread-safe by construction) and never touch
/// `@MainActor` state. CoreLocation still delivers callbacks on the main
/// run loop, so no actual cross-thread hop occurs at runtime.
@MainActor
public final class CoreLocationSource: NSObject, LocationSource {
    public nonisolated let sampleStream: AsyncStream<LocationSample>

    private let manager: CLLocationManager
    private nonisolated let sampleContinuation: AsyncStream<LocationSample>.Continuation

    /// Continuation for the in-flight `requestPermission()` call. Set
    /// when the call begins and consumed on the next
    /// `locationManagerDidChangeAuthorization` callback.
    private var pendingPermissionContinuation: CheckedContinuation<Void, Error>?

    override public init() {
        // The "create stream, capture its continuation" two-step is
        // the idiomatic Swift `AsyncStream` initializer pattern when
        // the continuation needs to live alongside the stream as a
        // stored property. The escaping init closure runs synchronously
        // inside `AsyncStream.init`, so `sampleCont` is guaranteed to
        // be assigned before the next line reads it.
        var sampleCont: AsyncStream<LocationSample>.Continuation!
        sampleStream = AsyncStream { sampleCont = $0 }
        sampleContinuation = sampleCont

        manager = CLLocationManager()
        super.init()
        manager.delegate = self
    }

    public func start() async {
        manager.startMonitoringSignificantLocationChanges()
        manager.startMonitoringVisits()
    }

    public func stop() async {
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
    }

    public func requestPermission() async throws {
        // If the user has already answered, resolve synchronously
        // without re-prompting.
        switch manager.authorizationStatus {
            case .authorizedAlways:
                return
            case .denied:
                throw LocationPermissionDeniedError(reason: .denied)
            case .restricted:
                throw LocationPermissionDeniedError(reason: .restricted)
            case .authorizedWhenInUse, .notDetermined:
                break
            @unknown default:
                break
        }

        // Otherwise drive the prompt and wait for the next
        // `locationManagerDidChangeAuthorization` callback.
        try await withCheckedThrowingContinuation { continuation in
            pendingPermissionContinuation = continuation
            manager.requestAlwaysAuthorization()
        }
    }

    /// Resume the in-flight `requestPermission()` continuation, if any,
    /// based on the manager's new authorization status. Called from the
    /// `nonisolated` delegate method after it hops back to `@MainActor`.
    fileprivate func resolvePendingPermission(for status: CLAuthorizationStatus) {
        guard let continuation = pendingPermissionContinuation else { return }
        pendingPermissionContinuation = nil
        switch status {
            case .authorizedAlways:
                continuation.resume()
            case .authorizedWhenInUse:
                // The user picked While-Using; the app needs Always to
                // do its job. Treat as denied so the UI shows the
                // upgrade-to-Always Settings link rather than silently
                // hanging.
                continuation.resume(
                    throwing: LocationPermissionDeniedError(reason: .denied),
                )
            case .denied:
                continuation.resume(
                    throwing: LocationPermissionDeniedError(reason: .denied),
                )
            case .restricted:
                continuation.resume(
                    throwing: LocationPermissionDeniedError(reason: .restricted),
                )
            case .notDetermined:
                // Still waiting on the user; do not resume. The next
                // authorization change will land us here again.
                pendingPermissionContinuation = continuation
            @unknown default:
                continuation.resume(
                    throwing: LocationPermissionDeniedError(reason: .denied),
                )
        }
    }
}

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
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.resolvePendingPermission(for: status)
        }
    }
}
