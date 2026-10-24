import Foundation
import ThrowCore

enum ThrowSessionLaunchTestFailure: Error, LocalizedError {
    case preferences
    case credential

    var errorDescription: String? {
        switch self {
            case .preferences: "The fixture preferences are unavailable."
            case .credential: "The fixture credential is unavailable."
        }
    }
}

actor ThrowSessionLaunchPreferenceStore: ThrowPreferenceStore {
    enum LoadResult {
        case value(ThrowPreferences)
        case failure
    }

    private let result: LoadResult
    private var suspendsLoad: Bool
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var loadStartedContinuation: CheckedContinuation<Void, Never>?
    private(set) var loadCallCount = 0

    init(result: LoadResult, suspendsLoad: Bool) {
        self.result = result
        self.suspendsLoad = suspendsLoad
    }

    func load() async throws -> ThrowPreferences {
        loadCallCount += 1
        loadStartedContinuation?.resume()
        loadStartedContinuation = nil
        if suspendsLoad {
            await withCheckedContinuation { continuation in
                loadContinuation = continuation
            }
        }
        switch result {
            case let .value(preferences): return preferences
            case .failure: throw ThrowSessionLaunchTestFailure.preferences
        }
    }

    func save(_: ThrowPreferences) {}

    func waitForLoadToStart() async {
        guard loadCallCount == 0 else { return }
        await withCheckedContinuation { continuation in
            loadStartedContinuation = continuation
        }
    }

    func resumeLoad() {
        suspendsLoad = false
        loadContinuation?.resume()
        loadContinuation = nil
    }
}

actor ThrowSessionLaunchCredentialStore: AircraftCredentialStore {
    private let failingID: AircraftCredentialID?
    private let states: [AircraftCredentialID: CredentialState]

    init(
        failingID: AircraftCredentialID?,
        states: [AircraftCredentialID: CredentialState],
    ) {
        self.failingID = failingID
        self.states = states
    }

    func state(for id: AircraftCredentialID) throws -> CredentialState {
        if id == failingID { throw ThrowSessionLaunchTestFailure.credential }
        return states[id] ?? .missing
    }

    func credential(for _: AircraftCredentialID) -> AircraftCredential? {
        nil
    }

    func save(_: AircraftCredential, for _: AircraftCredentialID) {}

    func delete(_: AircraftCredentialID) {}
}
