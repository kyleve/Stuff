import Foundation
import SnapshotReviewCore

/// Owns the workspace's access lifetime and one encoded navigation preference.
@MainActor final class ReviewSessionStore {
    private enum Key: String { case session = "snapshotReview.session" }
    private let preferences: UserDefaults
    private var scopedURL: URL?
    private var bookmark: Data?

    init(preferences: UserDefaults) {
        self.preferences = preferences
    }

    deinit { scopedURL?.stopAccessingSecurityScopedResource() }

    func makeBookmark(_ url: URL) throws -> Data {
        #if targetEnvironment(macCatalyst)
            try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil,
            )
        #else
            try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    func adopt(_ url: URL, bookmark: Data, accessed: Bool) {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = accessed ? url : nil
        self.bookmark = bookmark
    }

    func load() throws -> ReviewSession? {
        guard let bytes = preferences.data(forKey: Key.session.rawValue) else { return nil }
        return try ReviewJSON.decode(ReviewSession.self, from: bytes)
    }

    func resolve(_ session: ReviewSession) throws -> URL {
        var stale = false
        #if targetEnvironment(macCatalyst)
            return try URL(
                resolvingBookmarkData: session.bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale,
            )
        #else
            return try URL(
                resolvingBookmarkData: session.bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale,
            )
        #endif
    }

    func save(
        root: URL,
        location: ReviewSession.Location?,
        appearance: SnapshotVariant.Appearance,
        other: SnapshotVariant?,
        filter: ReviewFilter,
        search: String,
    ) throws {
        guard let bookmark else { return }
        let session = ReviewSession(
            bookmark: bookmark,
            root: root,
            location: location,
            appearance: appearance,
            other: other,
            filter: filter,
            search: search,
        )
        try preferences.set(ReviewJSON.encode(session), forKey: Key.session.rawValue)
    }
}
