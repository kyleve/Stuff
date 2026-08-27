import Foundation
import ThrowCore

extension ProjectionPlaylistError {
    var localizedSettingsDescription: String {
        switch self {
            case .duplicateExperience:
                String(localized: .viewsPlaylistDuplicate)
            case .unknownExperience:
                String(localized: .viewsPlaylistUnknown)
            case .unavailableExperience:
                String(localized: .viewsPlaylistUnavailable)
            case .unconfiguredExperience:
                String(localized: .viewsPlaylistUnconfigured)
            case .invalidSelection:
                String(localized: .viewsPlaylistSelectionInvalid)
            case .invalidDwellDuration:
                String(localized: .viewsPlaylistDwellInvalid)
        }
    }
}
