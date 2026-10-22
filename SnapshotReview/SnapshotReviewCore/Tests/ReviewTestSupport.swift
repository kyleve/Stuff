import Foundation
import SnapshotReviewCore
import Testing
import UIKit

struct ReviewTestFolder {
    let root: URL
    let suite: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suite = root.appendingPathComponent("Module/SnapshotTests/__Snapshots__/ExampleTests")
        try FileManager.default.createDirectory(at: suite, withIntermediateDirectories: true)
    }

    func remove() {
        do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) }
    }

    @MainActor func image(_ relative: String = "example.Loaded_iPhone.png") throws -> URL {
        let url = suite.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60))
            .pngData { context in
                UIColor.systemBlue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
            }
        try bytes.write(to: url)
        return url
    }
}
