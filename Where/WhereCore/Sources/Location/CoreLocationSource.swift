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

    /// Each access returns an independent subscription (see
    /// `AuthorizationStatusBroadcaster`), so multiple or serial observers — e.g.
    /// a `WhereSession` rebuilt after a reset — each get their own stream rather
    /// than fighting over (and tearing down) a single shared one.
    public nonisolated var authorizationUpdates: AsyncStream<LocationAuthorizationStatus> {
        authorizationBroadcaster.subscribe()
    }

    private let manager: CLLocationManager
    private nonisolated let sampleContinuation: AsyncStream<LocationSample>.Continuation
    private nonisolated let authorizationBroadcaster = AuthorizationStatusBroadcaster()

    /// Continuations for in-flight `requestPermission()` calls. Overlapping
    /// callers (e.g. rapid taps, or the toggle and the "Grant" button racing)
    /// are coalesced: only the first call drives the system prompt, and every
    /// waiter is resumed together on the next authorization callback. Storing
    /// a single continuation here would let a second request overwrite — and
    /// thus permanently strand — the first.
    private var pendingPermissionContinuations: [CheckedContinuation<Void, Error>] = []

    /// Waiters for an in-flight `requestCurrentLocation()`. Overlapping callers
    /// coalesce onto the next delivered fix (or the shared timeout / failure);
    /// only the first triggers `requestLocation()`. Every waiter is resumed
    /// together, so a second caller can't strand the first.
    private var pendingLocationContinuations: [CheckedContinuation<LocationSample?, Never>] = []

    /// How long to wait for a one-shot fix before giving up and recording no
    /// captured location. Kept short so a manual entry's Save isn't held up.
    private static let currentLocationTimeout: Duration = .seconds(10)

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

    public func requestCurrentLocation() async -> LocationSample? {
        // Best-effort: without a granted status `requestLocation()` just fails,
        // so short-circuit to "no fix" rather than starting a doomed request.
        switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                break
            case .denied, .restricted, .notDetermined:
                return nil
            @unknown default:
                return nil
        }

        return await withCheckedContinuation { continuation in
            pendingLocationContinuations.append(continuation)
            guard pendingLocationContinuations.count == 1 else { return }
            manager.requestLocation()
            // Bound the wait so a Save never hangs on a slow/absent fix.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.currentLocationTimeout)
                self?.resolvePendingLocation(nil)
            }
        }
    }

    /// Resume (and clear) every coalesced one-shot location waiter with the same
    /// result. Cleared before resuming so a fix delivered after the timeout (or
    /// vice-versa) is a no-op rather than a double-resume.
    private func resolvePendingLocation(_ sample: LocationSample?) {
        guard !pendingLocationContinuations.isEmpty else { return }
        let waiters = pendingLocationContinuations
        pendingLocationContinuations.removeAll()
        for waiter in waiters {
            waiter.resume(returning: sample)
        }
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
        // Only the first concurrent caller triggers the system prompt; any
        // others simply join the waiter list and resume on the same callback.
        try await withCheckedThrowingContinuation { continuation in
            pendingPermissionContinuations.append(continuation)
            if pendingPermissionContinuations.count == 1 {
                manager.requestWhenInUseAuthorization()
            }
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
        guard !pendingPermissionContinuations.isEmpty else { return }
        switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                resumePendingPermission(with: .success(()))
            case .denied:
                resumePendingPermission(
                    with: .failure(LocationPermissionDeniedError(reason: .denied)),
                )
            case .restricted:
                resumePendingPermission(
                    with: .failure(LocationPermissionDeniedError(reason: .restricted)),
                )
            case .notDetermined:
                // Still waiting on the user; keep the continuations pending.
                break
            @unknown default:
                resumePendingPermission(
                    with: .failure(LocationPermissionDeniedError(reason: .denied)),
                )
        }
    }

    /// Resume (and clear) every coalesced permission waiter with the same
    /// outcome. Cleared before resuming so a re-entrant `requestPermission()`
    /// from a resumed continuation starts a fresh request rather than racing
    /// the list we're draining.
    private func resumePendingPermission(with result: Result<Void, Error>) {
        let waiters = pendingPermissionContinuations
        pendingPermissionContinuations.removeAll()
        for waiter in waiters {
            waiter.resume(with: result)
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
        var latest: LocationSample?
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
            latest = sample
        }
        // A one-shot `requestCurrentLocation()` is delivered here too; satisfy
        // any pending waiter with the freshest fix in this batch.
        if let latest {
            Task { @MainActor [weak self] in
                self?.resolvePendingLocation(latest)
            }
        }
    }

    public nonisolated func locationManager(
        _: CLLocationManager,
        didFailWithError _: any Error,
    ) {
        // `requestLocation()` reports failures here. Resolve any one-shot waiter
        // with "no fix" (best-effort audit capture) rather than leaving it to
        // wait out the full timeout.
        Task { @MainActor [weak self] in
            self?.resolvePendingLocation(nil)
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
        authorizationBroadcaster.send(Self.map(status))
        Task { @MainActor in
            self.resolvePendingPermission(for: status)
        }
    }
}
