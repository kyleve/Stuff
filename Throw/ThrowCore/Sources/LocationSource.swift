import CoreLocation
import Foundation

public enum LocationAuthorization: String, Hashable, Sendable {
    case notDetermined
    case denied
    case restricted
    case whenInUse
    case always
}

public struct LocationFix: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let position: ObserverPosition
    public let horizontalAccuracyMeters: Double
    public let observedAt: Date

    public init(
        position: ObserverPosition,
        horizontalAccuracyMeters: Double,
        observedAt: Date,
    ) throws {
        guard horizontalAccuracyMeters.isFinite, horizontalAccuracyMeters >= 0 else {
            throw ThrowValidationError.outOfRange(
                field: "horizontalAccuracy",
                closedRange: 0 ... Double.greatestFiniteMagnitude,
            )
        }
        self.position = position
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.observedAt = observedAt
    }

    public var description: String {
        "<LocationFix position=<redacted>>"
    }

    public var debugDescription: String {
        description
    }
}

public enum LocationEvent: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    case authorization(LocationAuthorization)
    case fix(LocationFix)
    case trueHeadingHint(Bearing)
    case invalidSample
    case failed

    public var description: String {
        "<LocationEvent redacted>"
    }

    public var debugDescription: String {
        description
    }
}

@MainActor
public protocol ThrowLocationSource: AnyObject, Sendable {
    var events: AsyncStream<LocationEvent> { get }
    func requestWhenInUseAuthorization()
    func startUpdates()
    func stopUpdates()
}

/// Foreground-only Core Location source. Delegate callbacks expose only true
/// headings; an invalid true heading is ignored rather than using magnetic north.
@MainActor
public final class CoreLocationThrowSource: NSObject, ThrowLocationSource {
    public nonisolated let events: AsyncStream<LocationEvent>

    private let manager: CLLocationManager
    private nonisolated let continuation: AsyncStream<LocationEvent>.Continuation

    override public init() {
        let pair = AsyncStream.makeStream(
            of: LocationEvent.self,
            bufferingPolicy: .bufferingNewest(8),
        )
        events = pair.stream
        continuation = pair.continuation
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    public func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    public func startUpdates() {
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    public func stopUpdates() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    deinit {
        continuation.finish()
    }
}

extension CoreLocationThrowSource: CLLocationManagerDelegate {
    public nonisolated func locationManager(
        _: CLLocationManager,
        didUpdateLocations locations: [CLLocation],
    ) {
        guard let fix = LocationFixEvaluator.bestValidFix(
            from: locations,
            at: Date(),
        ) else {
            continuation.yield(.invalidSample)
            return
        }
        continuation.yield(.fix(fix))
    }

    public nonisolated func locationManager(
        _: CLLocationManager,
        didUpdateHeading newHeading: CLHeading,
    ) {
        guard newHeading.trueHeading >= 0 else { return }
        do {
            try continuation.yield(.trueHeadingHint(Bearing(degrees: newHeading.trueHeading)))
        } catch {
            continuation.yield(.invalidSample)
        }
    }

    public nonisolated func locationManager(
        _: CLLocationManager,
        didFailWithError _: any Error,
    ) {
        continuation.yield(.failed)
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        continuation.yield(.authorization(Self.authorization(manager.authorizationStatus)))
    }

    private nonisolated static func authorization(
        _ status: CLAuthorizationStatus,
    ) -> LocationAuthorization {
        switch status {
            case .notDetermined: .notDetermined
            case .restricted: .restricted
            case .denied: .denied
            case .authorizedAlways: .always
            case .authorizedWhenInUse: .whenInUse
            @unknown default: .notDetermined
        }
    }
}

public enum LocationFixDecision: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    case keepWaiting(best: LocationFix?)
    case acceptTarget(LocationFix)
    case offerBest(LocationFix?)

    public var description: String {
        "<LocationFixDecision redacted>"
    }

    public var debugDescription: String {
        description
    }
}

public enum LocationFixEvaluator {
    public static let targetAccuracyMeters = 100.0
    public static let maximumWait: TimeInterval = 20
    public static let maximumSampleAge: TimeInterval = 15
    public static let maximumFutureSkew: TimeInterval = 5

    public static func isValid(_ fix: LocationFix, at date: Date) -> Bool {
        let age = date.timeIntervalSince(fix.observedAt)
        return age >= -maximumFutureSkew && age <= maximumSampleAge
    }

    /// Selects by accuracy only after rejecting stale, future, and invalid samples.
    static func bestValidFix(from locations: [CLLocation], at date: Date) -> LocationFix? {
        var bestFix: LocationFix?
        for location in locations
            where location.horizontalAccuracy >= 0 && location.verticalAccuracy >= 0
        {
            let fix: LocationFix
            do {
                fix = try LocationFix(
                    position: ObserverPosition(
                        coordinate: GeoCoordinate(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude,
                        ),
                        altitude: Altitude(feet: location.altitude / 0.3048),
                    ),
                    horizontalAccuracyMeters: location.horizontalAccuracy,
                    observedAt: location.timestamp,
                )
            } catch {
                continue
            }
            guard isValid(fix, at: date) else { continue }
            if let bestFix,
               bestFix.horizontalAccuracyMeters <= fix.horizontalAccuracyMeters
            {
                continue
            }
            bestFix = fix
        }
        return bestFix
    }

    public static func decision(
        bestFix: LocationFix?,
        elapsed: TimeInterval,
        at date: Date,
    ) -> LocationFixDecision {
        let currentBestFix = bestFix.flatMap { fix in
            isValid(fix, at: date) ? fix : nil
        }
        if let currentBestFix,
           currentBestFix.horizontalAccuracyMeters <= targetAccuracyMeters
        {
            return .acceptTarget(currentBestFix)
        }
        if elapsed >= maximumWait {
            return .offerBest(currentBestFix)
        }
        return .keepWaiting(best: currentBestFix)
    }
}
