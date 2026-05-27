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

/// Abstraction over the source of `LocationSample`s. `WhereController`
/// streams from `sampleStream`; production wires a `CoreLocationSource`
/// (Visits + significant-change), tests wire a `ScriptedLocationSource`.
///
/// Class-only (`AnyObject`) because every concrete implementation owns
/// long-lived state (an `AsyncStream.Continuation`, a `CLLocationManager`)
/// that cannot be value-copied.
public protocol LocationSource: AnyObject, Sendable {
    var sampleStream: AsyncStream<LocationSample> { get }

    func start() async
    func stop() async

    /// Drive the permission flow to completion. Resolves successfully
    /// when the user has granted Always authorization. Throws
    /// `LocationPermissionDeniedError` on `.denied` / `.restricted`.
    /// Call once at app launch (or when re-entering a permission-gated
    /// screen) and `do/catch` the result — there is no separate stream
    /// to subscribe to.
    func requestPermission() async throws
}

/// Hand-driven `LocationSource` for tests and SwiftUI previews. Yield samples
/// with `emit(_:)`; close the stream with `finish()` when the test is done.
public final class ScriptedLocationSource: LocationSource, @unchecked Sendable {
    public let sampleStream: AsyncStream<LocationSample>

    private let sampleContinuation: AsyncStream<LocationSample>.Continuation
    private let permissionResult: Result<Void, LocationPermissionDeniedError>

    /// - Parameter permissionResult: what the next call to
    ///   `requestPermission()` returns. Defaults to success so existing
    ///   tests don't need to opt in.
    public init(
        permissionResult: Result<Void, LocationPermissionDeniedError> = .success(()),
    ) {
        var sampleCont: AsyncStream<LocationSample>.Continuation!
        sampleStream = AsyncStream { sampleCont = $0 }
        sampleContinuation = sampleCont
        self.permissionResult = permissionResult
    }

    public func start() async {}
    public func stop() async {}

    public func requestPermission() async throws {
        try permissionResult.get()
    }

    public func emit(_ sample: LocationSample) {
        sampleContinuation.yield(sample)
    }

    public func finish() {
        sampleContinuation.finish()
    }
}
