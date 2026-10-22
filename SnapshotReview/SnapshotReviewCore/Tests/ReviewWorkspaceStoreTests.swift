import Foundation
import SnapshotReviewCore
import Testing

@MainActor struct ReviewWorkspaceStoreTests {
    @Test func retainsTodosWhenEveryImageInTheSuiteIsMissing() async throws {
        let folder = try ReviewTestFolder()
        defer { folder.remove() }
        let path = try SnapshotPath("deleted.png")
        let review = ImageReview(path: path, reviewed: nil, annotations: [
            .init(
                text: "Keep this follow-up",
                status: .open,
                point: nil,
                fingerprint: "old",
                date: Date(),
            ),
        ])
        _ = try ReviewFileStore.save(.init(images: [review]), suite: folder.suite, expected: nil)
        let suites = try await ReviewWorkspaceStore().scan(root: folder.root)
        #expect(suites.count == 1)
        #expect(suites.first?.images.isEmpty == true)
        let markdown = try ReviewMarkdown.export(suites: suites, root: folder.root, imageIDs: nil)
        #expect(markdown.contains("Keep this follow-up"))
        #expect(markdown.contains("unavailable"))
    }

    @Test func selectingOnlyOtherRequiresAccessToTheSuite() async throws {
        let folder = try ReviewTestFolder()
        defer { folder.remove() }
        _ = try folder.image("other/example.png")
        await #expect(throws: ReviewError.self) {
            try await ReviewWorkspaceStore()
                .scan(root: folder.suite.appendingPathComponent("other"))
        }
    }

    @Test func discoversOtherAndReportsPointersAndMalformedReviewFiles() async throws {
        let folder = try ReviewTestFolder()
        defer { folder.remove() }
        _ = try folder.image()
        _ = try folder.image("other/example.Loaded_iPhone_dark.png")
        try Data("version https://git-lfs.github.com/spec/v1\n".utf8)
            .write(to: folder.suite.appendingPathComponent("pointer.png"))
        try Data("broken".utf8)
            .write(to: folder.suite.appendingPathComponent(ReviewDocument.filename))
        let suites = try await ReviewWorkspaceStore().scan(root: folder.root)
        #expect(suites.count == 1)
        let suite = try #require(suites.first)
        #expect(suite.images.count == 3)
        #expect(suite.images.contains { $0.id.path.value.hasPrefix("other/") })
        #expect(throws: (any Error).self) { try suite.reviews.get() }
        let pointer = try #require(suite.images.first { $0.id.path.value == "pointer.png" })
        #expect(throws: ReviewError.self) { try pointer.content.get() }
    }

    @Test func changedTimestampKeepsIdentityButChangedBytesRejectSave() async throws {
        let folder = try ReviewTestFolder()
        defer { folder.remove() }
        let url = try folder.image()
        let store = ReviewWorkspaceStore()
        let first = try await store.scan(root: folder.root)
        let original = try #require(first.first?.images.first)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1000)],
            ofItemAtPath: url.path,
        )
        let second = try await store.scan(root: folder.root)
        let refreshed = try #require(second.first?.images.first)
        #expect(try original.content.get().fingerprint == refreshed.content.get().fingerprint)
        try Data("changed".utf8).write(to: url)
        await #expect(throws: (any Error).self) { try await store.save(
            ReviewDocument(images: []),
            suite: folder.suite,
            expected: nil,
            image: original,
        ) }
        #expect(!FileManager.default
            .fileExists(atPath: folder.suite.appendingPathComponent(ReviewDocument.filename).path))
    }
}
