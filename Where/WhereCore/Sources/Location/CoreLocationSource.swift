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
    public nonisolated let authorizationUpdates: AsyncStream<LocationAuthorizationStatus>

    private let manager: CLLocationManager
    private nonisolated let sampleContinuation: AsyncStream<LocationSample>.Continuation
    private nonisolated let authorizationContinuation: AsyncStream<LocationAuthorizationStatus>
        .Continuation

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

        var authCont: AsyncStream<LocationAuthorizationStatus>.Continuation!
        // Keep only the latest status so a subscriber that attaches slightly
        // after launch still sees the current value.
        authorizationUpdates = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { authCont = $0 }
        authorizationContinuation = authCont

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

    public func currentAuthorization() async -> LocationAuthorizationStatus {
        Self.map(manager.authorizationStatus)
    }

    public func requestPermission() async throws {
        switch manager.authorizationStatus {
            case .authorizedAlways:
                return
            case .denied:
                throw LocationPermissionDeniedError(reason: .denied)
            case .restricted:
                throw LocationPermissionDeniedError(reason: .restricted)
            case .authorizedWhenInUse:
                // Already have foreground access. Nudge the Always upgrade;
                // iOS defers this prompt to the next background transition, so
                // don't block — the authorization stream reports the result.
                manager.requestAlwaysAuthorization()
                return
            case .notDetermined:
                break
            @unknown default:
                return
        }

        // Drive the initial prompt and wait for the user's first decision.
        try await withCheckedThrowingContinuation { continuation in
            pendingPermissionContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }

        // If we only got When-In-Use, kick off the (deferred) Always upgrade
        // without blocking; observers learn the outcome via the stream.
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    /// Resume the in-flight `requestPermission()` continuation, if any,
    /// based on the manager's new authorization status. Called from the
    /// `nonisolated` delegate method after it hops back to `@MainActor`.
    ///
    /// Any granted status (When-In-Use or Always) resolves successfully — the
    /// caller inspects `currentAuthorization()` to decide whether Always was
    /// obtained. This avoids hanging on the deferred Always prompt, which may
    /// never deliver a follow-up callback if the user leaves it at When-In-Use.
    fileprivate func resolvePendingPermission(for status: CLAuthorizationStatus) {
        guard let continuation = pendingPermissionContinuation else { return }
        switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                pendingPermissionContinuation = nil
                continuation.resume()
            case .denied:
                pendingPermissionContinuation = nil
                continuation.resume(throwing: LocationPermissionDeniedError(reason: .denied))
            case .restricted:
                pendingPermissionContinuation = nil
                continuation.resume(throwing: LocationPermissionDeniedError(reason: .restricted))
            case .notDetermined:
                // Still waiting on the user; keep the continuation pending.
                break
            @unknown default:
                pendingPermissionContinuation = nil
                continuation.resume(throwing: LocationPermissionDeniedError(reason: .denied))
        }
    }

    fileprivate nonisolated static func map(_ status: CLAuthorizationStatus)
        -> LocationAuthorizationStatus
    {
        switch status {
            case .authorizedAlways: .always
            case .authorizedWhenInUse: .whenInUse
            case .denied: .denied
            case .restricted: .restricted
            case .notDetermined: .notDetermined
            @unknown default: .notDetermined
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
        // Broadcast every change so observers (the UI) stay in sync, including
        // changes made in the Settings app while we were backgrounded.
        authorizationContinuation.yield(Self.map(status))
        Task { @MainActor in
            self.resolvePendingPermission(for: status)
        }
    }
}
