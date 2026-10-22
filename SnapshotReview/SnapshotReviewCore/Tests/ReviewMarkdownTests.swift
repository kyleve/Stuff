import Foundation
import SnapshotReviewCore
import Testing

struct ReviewMarkdownTests {
    @Test func exportsMissingImagesAndOnlyOpenTodos() throws {
        let root = URL(fileURLWithPath: "/workspace")
        let suiteURL = root.appendingPathComponent("__Snapshots__/Example")
        let path = try SnapshotPath("other/image.png")
        let note = ReviewAnnotation(
            text: "An observation",
            status: .note,
            point: nil,
            fingerprint: "old",
            date: Date(),
        )
        let todo = ReviewAnnotation(
            text: "Fix title\nKeep spacing",
            status: .open,
            point: .init(x: 0.5, y: 0.2),
            fingerprint: "old",
            date: Date(),
        )
        let document = ReviewDocument(images: [.init(
            path: path,
            reviewed: nil,
            annotations: [note, todo],
        )])
        let suite = SnapshotSuite(
            id: suiteURL,
            name: "Example",
            images: [],
            reviews: .success(.init(document: document, bytes: nil)),
            manifestError: nil,
        )
        let markdown = try ReviewMarkdown.export(suites: [suite], root: root, imageIDs: nil)
        #expect(markdown.contains("- [ ] Fix title\n  Keep spacing"))
        #expect(markdown.contains("x=0.5, y=0.2"))
        #expect(markdown.contains("[image unavailable]"))
        #expect(!markdown.contains("An observation"))
    }
}
