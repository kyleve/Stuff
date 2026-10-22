import Foundation
import SnapshotReviewCore
import Testing

struct SnapshotPathTests {
    @Test(arguments: [
        "",
        "/absolute.png",
        "../escape.png",
        "other/../escape.png",
        "other//x.png",
        "other\\x.png",
    ])
    func rejectsUnsafePaths(_ path: String) throws {
        #expect(throws: ReviewError.self) { try SnapshotPath(path) }
        let bytes = try JSONEncoder().encode(path)
        #expect(throws: ReviewError.self) { try ReviewJSON.decode(SnapshotPath.self, from: bytes) }
    }

    @Test func nestedPathRoundTrips() throws {
        let path = try SnapshotPath("other/view.Loaded_iPad_dark.png")
        #expect(try ReviewJSON.decode(SnapshotPath.self, from: ReviewJSON.encode(path)) == path)
    }
}
