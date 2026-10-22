import Foundation

public struct SnapshotImage: Identifiable, Sendable {
    public struct ID: Hashable, Codable, Sendable {
        public var suite: URL
        public var path: SnapshotPath
        public init(suite: URL, path: SnapshotPath) {
            self.suite = suite; self.path = path
        }
    }

    public struct Pixels: Equatable, Sendable {
        public var width: Int
        public var height: Int
        public init(width: Int, height: Int) {
            self.width = width; self.height = height
        }
    }

    public struct Content: Sendable {
        public var fingerprint: String
        public var modifiedAt: Date
        public var pixels: Pixels
        public init(fingerprint: String, modifiedAt: Date, pixels: Pixels) {
            self.fingerprint = fingerprint; self.modifiedAt = modifiedAt; self.pixels = pixels
        }
    }

    public var id: ID
    public var metadata: SnapshotManifest.Entry?
    public var content: Result<Content, any Error>
    public var url: URL {
        id.suite.appendingPathComponent(id.path.value)
    }

    public init(id: ID, metadata: SnapshotManifest.Entry?, content: Result<Content, any Error>) {
        self.id = id; self.metadata = metadata; self.content = content
    }
}

public struct SnapshotSuite: Identifiable, Sendable {
    public var id: URL
    public var name: String
    public var images: [SnapshotImage]
    public var reviews: Result<ReviewFile, any Error>
    public var manifestError: (any Error)?
    public init(
        id: URL,
        name: String,
        images: [SnapshotImage],
        reviews: Result<ReviewFile, any Error>,
        manifestError: (any Error)?,
    ) {
        self.id = id; self.name = name; self.images = images; self.reviews = reviews; self
            .manifestError = manifestError
    }
}

public struct ReviewFile: Sendable {
    public var document: ReviewDocument
    public var bytes: Data?
    public init(document: ReviewDocument, bytes: Data?) {
        self.document = document; self.bytes = bytes
    }
}
