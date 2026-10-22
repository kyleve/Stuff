import Foundation
import SnapshotReviewCore
@testable import SnapshotReviewUI
import Testing

@MainActor struct ReviewSessionStoreTests {
    @Test func restoresCoupledNavigationPreferencesAndBookmark() throws {
        let name = "SnapshotReviewSessionTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let store = ReviewSessionStore(preferences: preferences)
        #expect(try store.load() == nil)
        let root = FileManager.default.temporaryDirectory
        let bookmark = try store.makeBookmark(root)
        store.adopt(root, bookmark: bookmark, accessed: false)
        let location = try ReviewSession.Location(
            group: .init(
                suite: root.appendingPathComponent("__Snapshots__/Example"),
                testName: "test",
                caseName: "Loaded",
            ),
            image: SnapshotPath("image.png"),
        )
        try store.save(
            root: root,
            location: location,
            appearance: .dark,
            other: nil,
            filter: .needsReview,
            search: "Loaded",
        )
        let restored = try #require(try ReviewSessionStore(preferences: preferences).load())
        #expect(restored.bookmark == bookmark)
        #expect(restored.location?.group == location.group)
        #expect(restored.location?.image == location.image)
        #expect(restored.appearance == .dark)
        #expect(restored.filter == .needsReview)
        #expect(restored.search == "Loaded")
        #expect(try store.resolve(restored).standardizedFileURL == root.standardizedFileURL)
    }
}
