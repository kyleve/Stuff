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

enum ControlledThrowPreferenceStoreFailure: Error {
    case save
}

enum ControlledThrowPreferenceSaveStep {
    case suspendThenSucceed
    case succeed
    case fail
    case cancel
}

enum ReconciledPreferenceRetryInterruption: CaseIterable {
    case failure
    case cancellation

    var saveSteps: [ControlledThrowPreferenceSaveStep] {
        switch self {
            case .failure:
                [.suspendThenSucceed, .fail, .succeed]
            case .cancellation:
                [.suspendThenSucceed, .cancel, .succeed]
        }
    }
}

actor ControlledThrowPreferenceStore: ThrowPreferenceStore {
    private struct SaveCountWaiter {
        let expectedCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    enum SaveBehavior {
        case suspended
        case failing
        case scripted([ControlledThrowPreferenceSaveStep])
    }

    private var preferences: ThrowPreferences
    private let saveBehavior: SaveBehavior
    private var savedPreferences: [ThrowPreferences] = []
    private var saveCount = 0
    private var saveCountWaiters: [SaveCountWaiter] = []
    private var saveContinuation: CheckedContinuation<Void, Never>?

    init(
        initialValue: ThrowPreferences = .defaultValue,
        saveBehavior: SaveBehavior,
    ) {
        preferences = initialValue
        self.saveBehavior = saveBehavior
    }

    func load() -> ThrowPreferences {
        preferences
    }

    func save(_ preferences: ThrowPreferences) async throws {
        saveCount += 1
        resumeSaveCountWaiters()
        switch saveStep(for: saveCount) {
            case .suspendThenSucceed:
                await suspendSave()
                self.preferences = preferences
                savedPreferences.append(preferences)
            case .succeed:
                self.preferences = preferences
                savedPreferences.append(preferences)
            case .fail:
                throw ControlledThrowPreferenceStoreFailure.save
            case .cancel:
                throw CancellationError()
        }
    }

    private func suspendSave() async {
        await withCheckedContinuation { continuation in
            saveContinuation = continuation
        }
    }

    private func saveStep(for attempt: Int) -> ControlledThrowPreferenceSaveStep {
        switch saveBehavior {
            case .suspended:
                attempt == 1 ? .suspendThenSucceed : .succeed
            case .failing:
                .fail
            case let .scripted(steps):
                if steps.indices.contains(attempt - 1) {
                    steps[attempt - 1]
                } else {
                    .succeed
                }
        }
    }

    func waitForSaveToStart() async {
        await waitForSaveCount(1)
    }

    func waitForSaveCount(_ expectedCount: Int) async {
        guard saveCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            saveCountWaiters.append(SaveCountWaiter(
                expectedCount: expectedCount,
                continuation: continuation,
            ))
        }
    }

    func resumeSave() {
        saveContinuation?.resume()
        saveContinuation = nil
    }

    func persistedPreferences() -> ThrowPreferences {
        preferences
    }

    func successfulSaves() -> [ThrowPreferences] {
        savedPreferences
    }

    func saveAttemptCount() -> Int {
        saveCount
    }

    private func resumeSaveCountWaiters() {
        let ready = saveCountWaiters.filter { $0.expectedCount <= saveCount }
        saveCountWaiters.removeAll { $0.expectedCount <= saveCount }
        ready.forEach { $0.continuation.resume() }
    }
}
