import Foundation
import WhereCore

/// The user's response to the location-permission prompt, as we expose it to
/// the rest of the app. UI watches `authorizationStream` so it can drive the
/// permission flow without touching CoreLocation directly.
public enum LocationAuthorizationStatus: Sendable, Hashable {
    case notDetermined
    case denied
    case restricted
    case authorizedWhenInUse
    case authorizedAlways
}

/// Abstraction over the source of `LocationSample`s. `WhereController`
/// streams from `sampleStream`; production wires a `CoreLocationSource`
/// (Visits + significant-change), tests wire a `ScriptedLocationSource`.
public protocol LocationSource: Sendable {
    var sampleStream: AsyncStream<LocationSample> { get }
    var authorizationStream: AsyncStream<LocationAuthorizationStatus> { get }

    func start() async
    func stop() async
    func requestAlwaysAuthorization() async
}

/// Hand-driven `LocationSource` for tests and SwiftUI previews. Yield samples
/// with `emit(_:)`; close the stream with `finish()` when the test is done.
public final class ScriptedLocationSource: LocationSource, @unchecked Sendable {
    public let sampleStream: AsyncStream<LocationSample>
    public let authorizationStream: AsyncStream<LocationAuthorizationStatus>

    private let sampleContinuation: AsyncStream<LocationSample>.Continuation
    private let authContinuation: AsyncStream<LocationAuthorizationStatus>.Continuation

    public init(initialAuthorization: LocationAuthorizationStatus = .authorizedAlways) {
        var sampleCont: AsyncStream<LocationSample>.Continuation!
        sampleStream = AsyncStream { sampleCont = $0 }
        sampleContinuation = sampleCont

        var authCont: AsyncStream<LocationAuthorizationStatus>.Continuation!
        authorizationStream = AsyncStream { authCont = $0 }
        authContinuation = authCont

        authContinuation.yield(initialAuthorization)
    }

    public func start() async {}
    public func stop() async {}
    public func requestAlwaysAuthorization() async {
        authContinuation.yield(.authorizedAlways)
    }

    public func emit(_ sample: LocationSample) {
        sampleContinuation.yield(sample)
    }

    public func setAuthorization(_ status: LocationAuthorizationStatus) {
        authContinuation.yield(status)
    }

    public func finish() {
        sampleContinuation.finish()
        authContinuation.finish()
    }
}
