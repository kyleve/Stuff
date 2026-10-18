import Foundation
import InstallerKit

/// Where owns the localized Settings copy around InstallerKit state.
extension UpdateModel {
    var attentionTitle: String? {
        switch state.snapshot?.availability {
            case .available: String(localized: .updatesAvailable)
            case .retired: String(localized: .updatesRetiredTitle)
            case .local, .current, .unpublished, nil: nil
        }
    }
}
