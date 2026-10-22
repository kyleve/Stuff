import Foundation
import SnapshotReviewCore
import Testing

struct ReviewFileStoreTests {
    @Test func detectsExternalEditWithoutOverwritingIt() throws {
        let folder = try ReviewTestFolder()
        defer { folder.remove() }
        let original = try ReviewFileStore.read(folder.suite)
        let saved = try ReviewFileStore.save(
            original.document,
            suite: folder.suite,
            expected: original.bytes,
        )
        let external = Data("{broken external edit}".utf8)
        let url = folder.suite.appendingPathComponent(ReviewDocument.filename)
        try external.write(to: url)
        #expect(throws: ReviewError.self) { try ReviewFileStore.save(
            saved.document,
            suite: folder.suite,
            expected: saved.bytes,
        ) }
        #expect(try Data(contentsOf: url) == external)
        #expect(throws: (any Error).self) { try ReviewFileStore.read(folder.suite) }
    }

    @Test func unchangedManifestDoesNotRewriteAndFilteredUpdatesPreserveEntries() throws {
        let folder = try ReviewTestFolder()
        defer { folder.remove() }
        let first = try SnapshotManifest.Entry(
            path: SnapshotPath("a.png"),
            testName: "test",
            caseName: "Name_with_underscores",
            referenceGroup: nil,
            configurationIdentifier: "iPhone",
            frame: "iPhone",
            configurationName: nil,
            layoutTraits: nil,
            variant: .light,
        )
        var second = first
        second.path = try SnapshotPath("other/b.png")
        try ReviewFileStore.updateManifest(first, suite: folder.suite)
        try ReviewFileStore.updateManifest(second, suite: folder.suite)
        let url = folder.suite.appendingPathComponent(SnapshotManifest.filename)
        let before = try Data(contentsOf: url)
        let date = Date(timeIntervalSince1970: 1000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        try ReviewFileStore.updateManifest(first, suite: folder.suite)
        #expect(try Data(contentsOf: url) == before)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let modificationDate = try #require(attributes[.modificationDate] as? Date)
        #expect(modificationDate == date)
        #expect(try ReviewJSON.decode(SnapshotManifest.self, from: before).entries.count == 2)
    }
}
