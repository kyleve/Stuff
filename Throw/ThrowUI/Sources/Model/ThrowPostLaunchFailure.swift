import Foundation
import ThrowCore

/// A recoverable operation error that occurs after Throw becomes operational.
enum ThrowPostLaunchFailure: Equatable, Identifiable {
    enum Owner: CaseIterable, Hashable {
        case preferencePersistence
        case aircraftSource
        case rapidAPICredential
        case flightradar24Credential
        case location
        case playlist
        case onboarding
        case projectionPreparation
        case projectionRendering
    }

    enum LocationReason: Equatable {
        case gpsFixRequired
        case persistence
    }

    enum PresentationSurface: Equatable {
        case dashboard
        case settings
        case appearance
        case aircraftSource
        case location
        case quietHours
        case calibration
        case labels
        case playlist
        case onboarding
    }

    case preferencePersistence
    case aircraftSource
    case rapidAPICredential
    case flightradar24Credential
    case location(LocationReason)
    case playlist(ProjectionPlaylistError?)
    case onboarding
    case projectionPreparation
    case projectionRendering

    var id: Owner {
        owner
    }

    var owner: Owner {
        switch self {
            case .preferencePersistence: .preferencePersistence
            case .aircraftSource: .aircraftSource
            case .rapidAPICredential: .rapidAPICredential
            case .flightradar24Credential: .flightradar24Credential
            case .location: .location
            case .playlist: .playlist
            case .onboarding: .onboarding
            case .projectionPreparation: .projectionPreparation
            case .projectionRendering: .projectionRendering
        }
    }

    var userMessage: LocalizedStringResource {
        switch self {
            case .preferencePersistence:
                .postLaunchFailurePreferencePersistence
            case .aircraftSource:
                .postLaunchFailureAircraftSource
            case .rapidAPICredential:
                .postLaunchFailureRapidAPICredential
            case .flightradar24Credential:
                .postLaunchFailureFlightradar24Credential
            case let .location(reason):
                switch reason {
                    case .gpsFixRequired: .locationGpsFixRequired
                    case .persistence: .postLaunchFailureLocationPersistence
                }
            case let .playlist(error):
                error?.localizedSettingsMessage ?? .viewsPlaylistApplyFailed
            case .onboarding:
                .postLaunchFailureOnboarding
            case .projectionPreparation:
                .postLaunchFailureProjectionPreparation
            case .projectionRendering:
                .postLaunchFailureProjectionRendering
        }
    }

    func isRelevant(to surface: PresentationSurface) -> Bool {
        switch self {
            case .preferencePersistence:
                switch surface {
                    case .dashboard, .settings, .appearance, .quietHours, .calibration,
                         .labels, .playlist:
                        true
                    case .aircraftSource, .location, .onboarding:
                        false
                }
            case .aircraftSource, .rapidAPICredential, .flightradar24Credential:
                surface == .dashboard || surface == .settings || surface == .aircraftSource
                    || surface == .onboarding
            case .location:
                surface == .dashboard || surface == .settings || surface == .location
                    || surface == .onboarding
            case .playlist:
                surface == .dashboard || surface == .settings || surface == .playlist
            case .onboarding:
                surface == .onboarding
            case .projectionPreparation, .projectionRendering:
                surface == .dashboard
        }
    }
}
