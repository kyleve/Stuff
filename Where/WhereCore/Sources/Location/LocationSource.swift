import Foundation

/// Thrown by `LocationSource.requestPermission()` when the user has denied
/// or restricted Always-location access. The app requires Always to do its
/// "what state was I in today" work, so callers treat this as a hard
/// failure (typically by surfacing a Settings deep-link).
public struct LocationPermissionDeniedError: Error, Sendable, Hashable {
    /// Whether the denial came from the user (`denied`) or from a
    /// device-level restriction such as parental controls
    /// (`restricted`).
    public enum Reason: Sendable, Hashable {
        case denied
        case restricted
    }

    public let reason: Reason

    public init(reason: Reason) {
        self.reason = reason
    }
}

/// Abstraction over the source of `LocationSample`s. `LocationIngestor`
/// streams from `sampleStream`; production wires a `CoreLocationSource`
/// (Visits + significant-change), tests wire a `ScriptedLocationSource`.
///
/// Class-only (`AnyObject`) because every concrete implementation owns
/// long-lived state (an `AsyncStream.Continuation`, a `CLLocationManager`)
/// that cannot be value-copied.
public protocol LocationSource: AnyObject, Sendable {
    var sampleStream: AsyncStream<LocationSample> { get }

    /// A stream of authorization-status changes. Yields whenever the system
    /// reports a new status (including the deferred "upgrade to Always"
    /// decision), so the UI can stay in sync with Settings changes made
    /// outside the app. Read `currentAuthorization()` for the value at a
    /// point in time.
    var authorizationUpdates: AsyncStream<LocationAuthorizationStatus> { get }

    func start() async
    func stop() async

    /// Best-effort one-shot GPS fix for "where is the device *right now*".
    ///
    /// Unlike the passive `sampleStream` (Visits + significant-change, which can
    /// be minutes stale), this actively asks for a fresh fix — used to stamp a
    /// manual entry's audit trail with where it was made. Returns `nil` rather
    /// than throwing when a fix can't be obtained (permission not granted,
    /// timeout, or a location error): the capture is audit metadata, so an
    /// absent fix is recorded honestly instead of blocking the entry.
    func requestCurrentLocation() async -> LocationSample?

    /// The current authorization status, read on demand.
    func currentAuthorization() async -> LocationAuthorizationStatus

    /// Drive the permission flow. From `.notDetermined` this presents the
    /// system prompt and resolves once the user decides; it then nudges the
    /// (iOS-deferred) Always upgrade without blocking on it. Resolves
    /// successfully for any granted status and throws
    /// `LocationPermissionDeniedError` on `.denied` / `.restricted`. Callers
    /// should read `currentAuthorization()` afterwards (or observe
    /// `authorizationUpdates`) since "granted" may mean only When-In-Use.
    func requestPermission() async throws
}

/// Hand-driven `LocationSource` for tests and SwiftUI previews. Yield samples
/// with `emit(_:)`; close the stream with `finish()` when the test is done.
/// Drive authorization with `emitAuthorization(_:)`.
public final class ScriptedLocationSource: LocationSource, @unchecked Sendable {
    public let sampleStream: AsyncStream<LocationSample>

    /// Each access returns an independent subscription, mirroring
    /// `CoreLocationSource`, so a test driving several serial observers (e.g. a
    /// session rebuilt after a reset) doesn't have them share one stream.
    public var authorizationUpdates: AsyncStream<LocationAuthorizationStatus> {
        authorizationBroadcaster.subscribe()
    }

    private let sampleContinuation: AsyncStream<LocationSample>.Continuation
    private let authorizationBroadcaster = AuthorizationStatusBroadcaster()
    private let permissionResult: Result<Void, LocationPermissionDeniedError>

    private let lock = NSLock()
    private var _status: LocationAuthorizationStatus
    /// What the next `requestCurrentLocation()` returns. Defaults to `nil` (no
    /// fix available) so tests opt in to a captured location explicitly.
    private var _nextRequestedLocation: LocationSample?

    /// - Parameters:
    ///   - permissionResult: what the next call to `requestPermission()`
    ///     returns. Defaults to success so existing tests don't need to opt in.
    ///   - authorizationStatus: the initial status reported by
    ///     `currentAuthorization()`. Defaults to `.always` so tracking-oriented
    ///     tests see a granted source.
    public init(
        permissionResult: Result<Void, LocationPermissionDeniedError> = .success(()),
        authorizationStatus: LocationAuthorizationStatus = .always,
    ) {
        var sampleCont: AsyncStream<LocationSample>.Continuation!
        sampleStream = AsyncStream { sampleCont = $0 }
        sampleContinuation = sampleCont

        self.permissionResult = permissionResult
        _status = authorizationStatus
    }

    public func start() async {}
    public func stop() async {}

    public func requestCurrentLocation() async -> LocationSample? {
        lock.withLock { _nextRequestedLocation }
    }

    /// Set the fix the next `requestCurrentLocation()` will return (or `nil` to
    /// simulate no fix). Mirrors how `emit(_:)` scripts the passive stream.
    public func setNextRequestedLocation(_ sample: LocationSample?) {
        lock.withLock { _nextRequestedLocation = sample }
    }

    public func currentAuthorization() async -> LocationAuthorizationStatus {
        lock.withLock { _status }
    }

    public func requestPermission() async throws {
        try permissionResult.get()
    }

    public func emit(_ sample: LocationSample) {
        sampleContinuation.yield(sample)
    }

    /// Update the reported authorization status and notify observers, the way
    /// CoreLocation would after a prompt or a Settings change.
    public func emitAuthorization(_ status: LocationAuthorizationStatus) {
        lock.withLock { _status = status }
        authorizationBroadcaster.send(status)
    }

    public func finish() {
        sampleContinuation.finish()
        authorizationBroadcaster.finishAll()
    }
}
