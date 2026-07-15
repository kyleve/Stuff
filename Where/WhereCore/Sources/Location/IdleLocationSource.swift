import Foundation

/// A production `LocationSource` that does nothing: it never yields samples,
/// never reports an authorization change, and returns no one-shot fix.
///
/// It exists for processes that assemble `WhereServices` purely to read or make
/// user-asserted writes and must **not** start GPS — the App Intents layer
/// (Siri / Spotlight / Shortcuts), which builds its stack via
/// `WhereServices.forIntents()`. Unlike `CoreLocationSource`, it installs no
/// `CLLocationManager`; unlike `ScriptedLocationSource`, it has no test seams —
/// it's simply inert. `requestCurrentLocation()` returns `nil` (the same honest
/// "no fix" a manual entry records), so an intent-made manual day carries an
/// audit with no captured location rather than a faked one.
public final class IdleLocationSource: LocationSource {
    public init() {}

    /// An immediately-finished stream: an intent's ingestor is never started,
    /// but should it iterate, it simply completes with no samples.
    public var sampleStream: AsyncStream<LocationSample> {
        AsyncStream { $0.finish() }
    }

    public var authorizationUpdates: AsyncStream<LocationAuthorizationStatus> {
        AsyncStream { $0.finish() }
    }

    public func start() async {}
    public func stop() async {}

    public func requestCurrentLocation() async -> LocationSample? {
        nil
    }

    /// Reports `.notDetermined`: an inert source has never prompted, and intents
    /// don't act on authorization anyway.
    public func currentAuthorization() async -> LocationAuthorizationStatus {
        .notDetermined
    }

    public func requestPermission() async throws {}
}
