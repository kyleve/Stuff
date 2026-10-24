import Foundation
import ThrowCore

/// The process launch state that gates every controller and projection surface.
public enum ThrowSessionLaunchState: Equatable, Sendable {
    case loading
    case onboarding(ThrowOnboardingSetup)
    case ready(ThrowConfiguredSetup)
    case failed(ThrowSessionLaunchFailure)

    var isOperational: Bool {
        switch self {
            case .onboarding, .ready:
                true
            case .loading, .failed:
                false
        }
    }

    static func loaded(_ setupState: ThrowSetupState) -> Self {
        switch setupState {
            case let .onboarding(setup): .onboarding(setup)
            case let .configured(setup): .ready(setup)
        }
    }

    func replacingLoadedSetup(with setupState: ThrowSetupState) -> Self {
        guard isOperational else { return self }
        return .loaded(setupState)
    }
}

/// A recoverable cold-launch error with its failed storage boundary.
public enum ThrowSessionLaunchFailure: Error, Equatable, Sendable {
    case preferences
    case credential(id: AircraftCredentialID)

    var userMessage: LocalizedStringResource {
        switch self {
            case .preferences:
                .launchFailurePreferences
            case .credential:
                .launchFailureCredential
        }
    }
}

struct LoadedAircraftCredentialStates: Equatable {
    let rapidAPI: CredentialState
    let flightradar24: CredentialState
}
