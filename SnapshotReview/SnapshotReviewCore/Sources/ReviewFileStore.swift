import CryptoKit
import Foundation
import ImageIO

/// Coordinates file replacement with other file presenters and checks exact prior bytes.
public enum ReviewFileStore {
    public static func read(_ suite: URL) throws -> ReviewFile {
        let url = suite.appendingPathComponent(ReviewDocument.filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ReviewFile(document: ReviewDocument(images: []), bytes: nil)
        }
        let bytes = try Data(contentsOf: url)
        let document = try ReviewJSON.decode(ReviewDocument.self, from: bytes)
        try document.validate()
        return ReviewFile(document: document, bytes: bytes)
    }

    public static func save(
        _ document: ReviewDocument,
        suite: URL,
        expected: Data?,
    ) throws -> ReviewFile {
        try document.validate()
        let url = suite.appendingPathComponent(ReviewDocument.filename)
        let bytes = try ReviewJSON.encode(document)
        try coordinateWrite(url) { destination in
            let current = FileManager.default
                .fileExists(atPath: destination.path) ? try Data(contentsOf: destination) : nil
            guard current == expected else { throw ReviewError.externalChange }
            if current != bytes { try bytes.write(to: destination, options: .atomic) }
        }
        return ReviewFile(document: document, bytes: bytes)
    }

    public static func updateManifest(_ entry: SnapshotManifest.Entry, suite: URL) throws {
        let url = suite.appendingPathComponent(SnapshotManifest.filename)
        try coordinateWrite(url) { destination in
            let old = FileManager.default
                .fileExists(atPath: destination.path) ? try Data(contentsOf: destination) : nil
            var manifest = try old
                .map { try ReviewJSON.decode(SnapshotManifest.self, from: $0) } ??
                SnapshotManifest(entries: [])
            try manifest.validate()
            manifest.upsert(entry)
            let bytes = try ReviewJSON.encode(manifest)
            if old != bytes { try bytes.write(to: destination, options: .atomic) }
        }
    }

    public static func fingerprint(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    public static func inspect(_ url: URL) throws -> SnapshotImage.Content {
        let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        if bytes.starts(with: Data("version https://git-lfs.github.com/spec/v1".utf8)) {
            throw ReviewError
                .unavailableImage(
                    "This image is a Git LFS pointer. Run git lfs pull in the checkout, then refresh.",
                )
        }
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source,
                  0,
                  nil,
              ) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw ReviewError.unavailableImage("The PNG cannot be decoded.") }
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let modifiedAt = values.contentModificationDate
        else {
            throw ReviewError.unavailableImage("The image modification date is unavailable.")
        }
        return .init(
            fingerprint: fingerprint(bytes),
            modifiedAt: modifiedAt,
            pixels: .init(width: width, height: height),
        )
    }

    private static func coordinateWrite(_ url: URL, body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var result: Result<Void, any Error>?
        NSFileCoordinator().coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordinationError,
        ) { destination in
            result = Result { try body(destination) }
        }
        if let coordinationError { throw coordinationError }
        guard let result
        else { throw ReviewError.invalidDocument("File coordination did not complete.") }
        try result.get()
    }
}
