import Foundation
import Testing
import UIKit

/// An isolated reference directory and deterministic images for storage tests.
struct SnapshotReferenceTestFixture {
    let directory: URL

    init() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SnapshotReferenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var testFilePath: String {
        directory.appendingPathComponent("ExampleSnapshotTests.swift").path
    }

    func remove() {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record(error)
        }
    }

    @MainActor
    func image(_ color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format)
            .image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            }
    }
}
