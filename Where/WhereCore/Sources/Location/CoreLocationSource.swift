import CoreLocation
import Foundation
import RegionKit

/// System-facing controls for one bounded foreground fix. Tests replace the
/// Core Location implementation without changing the request coordinator.
@MainActor
@_spi(Testing) public protocol CurrentLocationRequestDriving: AnyObject {
    var authorization: LocationAuthorizationStatus { get }
    var hasPreciseLocation: Bool { get }
    var timeout: Duration { get }

    func requestLocation()
    func stopLocation()
}

@MainActor
private final class SystemCurrentLocationRequestDriver: CurrentLocationRequestDriving {
    private let manager: CLLocationManager

    init(manager: CLLocationManager) {
        self.manager = manager
    }

    var authorization: LocationAuthorizationStatus {
        CoreLocationSource.map(manager.authorizationStatus)
    }

    var hasPreciseLocation: Bool {
        manager.accuracyAuthorization == .fullAccuracy
    }

    var timeout: Duration {
        .seconds(10)
    }

    func requestLocation() {
        manager.requestLocation()
    }

    func stopLocation() {
        manager.stopUpdatingLocation()
    }
}

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
/// is safe here because they yield through thread-safe stream continuations
/// and explicitly hop to `MainActor` before touching one-shot request state.
/// Core Location still delivers callbacks on the main run loop in practice.
@MainActor
public final class CoreLocationSource: NSObject, LocationSource {
    private struct PendingCurrentLocationRequest {
        let id: UUID
        var waiters: [UUID: CheckedContinuation<CurrentLocationResult, Never>]
        let timeoutTask: Task<Void, Never>
    }

    private enum CurrentLocationRequestState {
        case idle
        case pending(PendingCurrentLocationRequest)
    }

    public nonisolated let sampleStream: AsyncStream<LocationSample>

    /// Each access returns an independent subscription (see
    /// `AuthorizationStatusBroadcaster`), so multiple or serial observers — e.g.
    /// a `WhereSession` rebuilt after a reset — each get their own stream rather
    /// than fighting over (and tearing down) a single shared one.
    public nonisolated var authorizationUpdates: AsyncStream<LocationAuthorizationStatus> {
        authorizationBroadcaster.subscribe()
    }

    private let manager: CLLocationManager
    private var currentLocationDriver: any CurrentLocationRequestDriving
    private nonisolated let sampleContinuation: AsyncStream<LocationSample>.Continuation
    private nonisolated let authorizationBroadcaster = AuthorizationStatusBroadcaster()

    /// Continuations for in-flight `requestPermission()` calls. Overlapping
    /// callers (e.g. rapid taps, or the toggle and the "Grant" button racing)
    /// are coalesced: only the first call drives the system prompt, and every
    /// waiter is resumed together on the next authorization callback. Storing
    /// a single continuation here would let a second request overwrite — and
    /// thus permanently strand — the first.
    private var pendingPermissionContinuations: [CheckedContinuation<Void, Error>] = []

    /// Only a pending request owns waiters and a timeout. Concurrent callers
    /// join that request; each cancellation removes just its own waiter.
    private var currentLocationRequestState: CurrentLocationRequestState = .idle

    private static let maximumCurrentLocationAge: TimeInterval = 60

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

        let manager = CLLocationManager()
        self.manager = manager
        currentLocationDriver = SystemCurrentLocationRequestDriver(manager: manager)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    public func start() async {
        manager.startMonitoringSignificantLocationChanges()
        manager.startMonitoringVisits()
    }

    public func stop() async {
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
    }

    public func requestCurrentLocation() async -> CurrentLocationResult {
        let authorization = currentLocationDriver.authorization
        switch authorization {
            case .always, .whenInUse:
                break
            case .denied, .restricted, .notDetermined:
                return .unavailable(.authorizationUnavailable(authorization))
        }
        guard currentLocationDriver.hasPreciseLocation else {
            return .unavailable(.preciseLocationDisabled)
        }
        guard !Task.isCancelled else { return .unavailable(.cancellation) }

        let requestID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                registerLocationWaiter(continuation, id: requestID)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelLocationWaiter(id: requestID)
            }
        }
    }

    private func registerLocationWaiter(
        _ continuation: CheckedContinuation<CurrentLocationResult, Never>,
        id: UUID,
    ) {
        guard !Task.isCancelled else {
            continuation.resume(returning: .unavailable(.cancellation))
            return
        }
        switch currentLocationRequestState {
            case .idle:
                let requestID = id
                let timeout = currentLocationDriver.timeout
                let timeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    self?.timeoutCurrentLocationRequest(id: requestID)
                }
                currentLocationRequestState = .pending(PendingCurrentLocationRequest(
                    id: requestID,
                    waiters: [id: continuation],
                    timeoutTask: timeoutTask,
                ))
                currentLocationDriver.requestLocation()
            case var .pending(request):
                request.waiters[id] = continuation
                currentLocationRequestState = .pending(request)
        }
    }

    private func cancelLocationWaiter(id: UUID) {
        guard case var .pending(request) = currentLocationRequestState,
              let waiter = request.waiters.removeValue(forKey: id)
        else { return }
        if request.waiters.isEmpty {
            currentLocationRequestState = .idle
            request.timeoutTask.cancel()
            currentLocationDriver.stopLocation()
        } else {
            currentLocationRequestState = .pending(request)
        }
        waiter.resume(returning: .unavailable(.cancellation))
    }

    private func timeoutCurrentLocationRequest(id: UUID) {
        guard case let .pending(request) = currentLocationRequestState,
              request.id == id
        else { return }
        resolvePendingLocation(.unavailable(.timeout))
        currentLocationDriver.stopLocation()
    }

    /// Resume (and clear) every coalesced one-shot location waiter with the same
    /// result. Cleared before resuming so a fix delivered after the timeout (or
    /// vice-versa) is a no-op rather than a double-resume.
    private func resolvePendingLocation(_ result: CurrentLocationResult) {
        guard case let .pending(request) = currentLocationRequestState else { return }
        currentLocationRequestState = .idle
        request.timeoutTask.cancel()
        for waiter in request.waiters.values {
            waiter.resume(returning: result)
        }
    }

    private func resolvePendingLocationIfFresh(_ samples: [LocationSample]) {
        guard case .pending = currentLocationRequestState else { return }
        let now = Date()
        guard let freshest = samples
            .filter({ abs(now.timeIntervalSince($0.timestamp)) <= Self.maximumCurrentLocationAge })
            .max(by: { $0.timestamp < $1.timestamp })
        else { return }
        resolvePendingLocation(.success(freshest))
    }

    #if DEBUG
        /// Replaces the system-facing driver for deterministic tests.
        @_spi(Testing) public func configureCurrentLocationForTesting(
            driver: any CurrentLocationRequestDriving,
        ) {
            currentLocationDriver = driver
        }

        /// Delivers a test batch through the same freshness gate as Core Location.
        @_spi(Testing) public func deliverCurrentLocationsForTesting(
            _ samples: [LocationSample],
        ) {
            resolvePendingLocationIfFresh(samples.filter { $0.horizontalAccuracy >= 0 })
        }

        /// Delivers a provider failure to every current one-shot waiter.
        @_spi(Testing) public func failCurrentLocationForTesting() {
            resolvePendingLocation(.unavailable(.providerFailure))
        }
    #endif

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

    /// Normalize unavailable CLLocation measurements at the system boundary.
    nonisolated static func motion(from location: CLLocation) -> LocationMotion? {
        let speed: LocationMotion.Speed? = if location.speed.isFinite,
                                              location.speed >= 0,
                                              location.speedAccuracy.isFinite,
                                              location.speedAccuracy >= 0
        {
            .init(metersPerSecond: location.speed, accuracyMetersPerSecond: location.speedAccuracy)
        } else {
            nil
        }
        let altitude: LocationMotion.Altitude? = if location.altitude.isFinite,
                                                    location.verticalAccuracy.isFinite,
                                                    location.verticalAccuracy > 0
        {
            .init(meters: location.altitude, accuracyMeters: location.verticalAccuracy)
        } else {
            nil
        }
        guard speed != nil || altitude != nil else { return nil }
        return LocationMotion(speed: speed, altitude: altitude)
    }
}

extension CoreLocationSource: CLLocationManagerDelegate {
    public nonisolated func locationManager(
        _: CLLocationManager,
        didUpdateLocations locations: [CLLocation],
    ) {
        var validSamples: [LocationSample] = []
        for location in locations {
            guard location.horizontalAccuracy >= 0 else { continue }
            let sample = LocationSample(
                timestamp: location.timestamp,
                coordinate: Coordinate(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                ),
                horizontalAccuracy: location.horizontalAccuracy,
                source: .gpsSignificantChange,
                motion: Self.motion(from: location),
            )
            sampleContinuation.yield(sample)
            validSamples.append(sample)
        }
        // A one-shot `requestCurrentLocation()` is delivered here too; satisfy
        // any pending waiter with the freshest fix in this batch.
        if !validSamples.isEmpty {
            Task { @MainActor [weak self] in
                self?.resolvePendingLocationIfFresh(validSamples)
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
            self?.resolvePendingLocation(.unavailable(.providerFailure))
        }
    }

    public nonisolated func locationManager(
        _: CLLocationManager,
        didVisit visit: CLVisit,
    ) {
        guard visit.horizontalAccuracy >= 0 else { return }
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
