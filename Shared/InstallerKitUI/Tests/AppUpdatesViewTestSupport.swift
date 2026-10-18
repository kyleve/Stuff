import Foundation
import InstallerKit

@MainActor
final class UpdatePagePreferences: UpdatePreferencesStoring {
    var installerUpdates = UpdatePreferences(cached: nil)
}

@MainActor
final class UpdatePageClient: UpdateFetching {
    let catalog: UpdateCatalog
    private(set) var requests = 0

    init(catalog: UpdateCatalog) {
        self.catalog = catalog
    }

    func fetch(from _: URL) async throws -> UpdateCatalog {
        requests += 1
        return catalog
    }
}

@MainActor
final class UpdatePageClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
}
