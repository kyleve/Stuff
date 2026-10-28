import Foundation

/// Device-local update metadata is one encoded preference.
public struct UpdatePreferences: Codable, Equatable {
    public struct Cached: Codable, Equatable {
        public let feedURL: URL
        public let checkedAt: Date
        public let catalog: UpdateCatalog

        public init(feedURL: URL, checkedAt: Date, catalog: UpdateCatalog) {
            self.feedURL = feedURL
            self.checkedAt = checkedAt
            self.catalog = catalog
        }
    }

    public var cached: Cached?

    public init(cached: Cached?) {
        self.cached = cached
    }
}

/// The host supplies device-local storage. Corrupt data must be reported, then discarded.
public protocol UpdatePreferencesStoring: AnyObject {
    var installerUpdates: UpdatePreferences { get set }
}
