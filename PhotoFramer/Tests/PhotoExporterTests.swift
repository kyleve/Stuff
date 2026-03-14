import CoreGraphics
import Foundation
import Testing

@testable import PhotoFramer

@Suite
struct PhotoExporterTests {

    private func makeTestImage() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        return context.makeImage()!
    }

    @Test func saveAsJPEGCreatesFile() throws {
        let image = makeTestImage()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).jpg")
        defer { try? FileManager.default.removeItem(at: url) }

        try PhotoExporter.saveToFile(image, url: url, format: .jpeg(quality: 0.9))
        #expect(FileManager.default.fileExists(atPath: url.path()))
    }

    @Test func saveAsPNGCreatesFile() throws {
        let image = makeTestImage()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }

        try PhotoExporter.saveToFile(image, url: url, format: .png)
        #expect(FileManager.default.fileExists(atPath: url.path()))
    }

    @Test func savedJPEGHasNonZeroSize() throws {
        let image = makeTestImage()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).jpg")
        defer { try? FileManager.default.removeItem(at: url) }

        try PhotoExporter.saveToFile(image, url: url, format: .jpeg(quality: 0.9))
        let data = try Data(contentsOf: url)
        #expect(data.count > 0)
    }

    @Test func savedPNGHasNonZeroSize() throws {
        let image = makeTestImage()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }

        try PhotoExporter.saveToFile(image, url: url, format: .png)
        let data = try Data(contentsOf: url)
        #expect(data.count > 0)
    }
}
