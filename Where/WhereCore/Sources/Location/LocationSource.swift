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
    public let authorizationUpdates: AsyncStream<LocationAuthorizationStatus>

    private let sampleContinuation: AsyncStream<LocationSample>.Continuation
    private let authorizationContinuation: AsyncStream<LocationAuthorizationStatus>.Continuation
    private let permissionResult: Result<Void, LocationPermissionDeniedError>

    private let lock = NSLock()
    private var _status: LocationAuthorizationStatus

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

        var authCont: AsyncStream<LocationAuthorizationStatus>.Continuation!
        authorizationUpdates = AsyncStream { authCont = $0 }
        authorizationContinuation = authCont

        self.permissionResult = permissionResult
        _status = authorizationStatus
    }

    public func start() async {}
    public func stop() async {}

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
        authorizationContinuation.yield(status)
    }

    public func finish() {
        sampleContinuation.finish()
        authorizationContinuation.finish()
    }
}
