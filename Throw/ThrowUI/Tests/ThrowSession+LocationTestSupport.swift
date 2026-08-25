import Foundation
import ThrowCore

@MainActor
final class ControlledThrowLocationSource: ThrowLocationSource {
    nonisolated let events: AsyncStream<LocationEvent>

    private nonisolated let continuation: AsyncStream<LocationEvent>.Continuation
    private var awaitedStartCount = 0
    private var awaitedStopCount = 0
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var stopWaiter: CheckedContinuation<Void, Never>?
    private(set) var requestAuthorizationCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var stopCountAtEachStart: [Int] = []

    init() {
        let pair = AsyncStream.makeStream(
            of: LocationEvent.self,
            bufferingPolicy: .bufferingNewest(8),
        )
        events = pair.stream
        continuation = pair.continuation
    }

    func requestWhenInUseAuthorization() {
        requestAuthorizationCount += 1
    }

    func startUpdates() {
        startCount += 1
        stopCountAtEachStart.append(stopCount)
        if startCount >= awaitedStartCount {
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func stopUpdates() {
        stopCount += 1
        if stopCount >= awaitedStopCount {
            stopWaiter?.resume()
            stopWaiter = nil
        }
    }

    func send(_ event: LocationEvent) {
        continuation.yield(event)
    }

    func waitForStartCount(_ expectedCount: Int) async {
        guard startCount < expectedCount else { return }
        awaitedStartCount = expectedCount
        await withCheckedContinuation { continuation in
            startWaiter = continuation
        }
    }

    func waitForStopCount(_ expectedCount: Int) async {
        guard stopCount < expectedCount else { return }
        awaitedStopCount = expectedCount
        await withCheckedContinuation { continuation in
            stopWaiter = continuation
        }
    }

    deinit {
        continuation.finish()
    }
}

enum ThrowSessionLocationTestFixture {
    static let now = Date(timeIntervalSince1970: 1_787_594_400)

    static func fix(
        latitude: Double,
        longitude: Double,
        accuracyMeters: Double,
    ) throws -> LocationFix {
        try LocationFix(
            position: ObserverPosition(
                coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
                altitude: Altitude(feet: 75),
            ),
            horizontalAccuracyMeters: accuracyMeters,
            observedAt: now,
        )
    }
}
