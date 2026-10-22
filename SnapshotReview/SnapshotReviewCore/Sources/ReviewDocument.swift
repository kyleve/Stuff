import Foundation

public struct ReviewDocument: Codable, Equatable, Sendable {
    public static let filename = "snapshot-reviews.json"
    public var version: Int = 1
    public var images: [ImageReview]
    public init(images: [ImageReview]) {
        self.images = images
    }

    public func review(for path: SnapshotPath) -> ImageReview {
        images.first { $0.path == path } ?? ImageReview(path: path, reviewed: nil, annotations: [])
    }

    public mutating func set(_ review: ImageReview) {
        images.removeAll { $0.path == review.path }
        images.append(review)
        images.sort { $0.path < $1.path }
    }

    public func validate() throws {
        guard version == 1 else { throw ReviewError.unsupportedVersion(version) }
        guard Set(images.map(\.path)).count == images.count
        else { throw ReviewError.invalidDocument("Duplicate image paths.") }
        for image in images {
            guard Set(image.annotations.map(\.id)).count == image.annotations.count,
                  image.annotations.allSatisfy({ $0.point?.isValid != false })
            else {
                throw ReviewError
                    .invalidDocument("Duplicate annotation IDs or invalid point coordinates.")
            }
        }
    }
}

public struct ImageReview: Codable, Equatable, Sendable {
    public var path: SnapshotPath
    public var reviewed: Revision?
    public var annotations: [ReviewAnnotation]

    public init(path: SnapshotPath, reviewed: Revision?, annotations: [ReviewAnnotation]) {
        self.path = path
        self.reviewed = reviewed
        self.annotations = annotations
    }

    public struct Revision: Codable, Equatable, Sendable {
        public var date: Date
        public var fingerprint: String
        public var modifiedAt: Date
        public init(date: Date, fingerprint: String, modifiedAt: Date) {
            self.date = date; self.fingerprint = fingerprint; self.modifiedAt = modifiedAt
        }
    }

    public func needsReview(fingerprint: String) -> Bool {
        reviewed?.fingerprint != fingerprint
    }

    public var openTodoCount: Int {
        annotations.count(where: { $0.status == .open })
    }
}
