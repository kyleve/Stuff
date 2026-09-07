import Foundation
import ThrowCore

extension ProjectionPlaylistError {
    var localizedSettingsMessage: LocalizedStringResource {
        switch self {
            case .duplicateExperience:
                .viewsPlaylistDuplicate
            case .unknownExperience:
                .viewsPlaylistUnknown
            case .unavailableExperience:
                .viewsPlaylistUnavailable
            case .unconfiguredExperience:
                .viewsPlaylistUnconfigured
            case .invalidSelection:
                .viewsPlaylistSelectionInvalid
            case .invalidDwellDuration:
                .viewsPlaylistDwellInvalid
        }
    }

    var localizedSettingsDescription: String {
        String(localized: localizedSettingsMessage)
    }
}
