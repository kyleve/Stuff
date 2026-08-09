import Foundation

public struct NormalizedRectangle: Hashable, Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) throws {
        guard x >= 0, y >= 0, width > 0, height > 0,
              x + width <= 1, y + height <= 1
        else {
            throw SnapshotAnnotationError.invalidRectangle
        }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum SnapshotAnnotationTag: String, Codable, Sendable {
    case problem = "P"
    case question = "Q"
    case expectedChange = "E"
    case nit = "N"
}

public enum SnapshotAnnotationTarget: String, Codable, Sendable {
    case base = "B"
    case head = "H"
}

/// The interoperable payload appended to a normal GitHub file-level comment.
public struct SnapshotAnnotationV1: Hashable, Codable, Sendable {
    public static let markerPrefix = "<!-- patchlight-snapshot:v1:"

    public let path: String
    public let target: SnapshotAnnotationTarget
    public let blobOID: GitObjectID
    public let rectangle: NormalizedRectangle
    public let sourceWidth: Int
    public let sourceHeight: Int
    public let tag: SnapshotAnnotationTag?

    public init(
        path: String,
        target: SnapshotAnnotationTarget,
        blobOID: GitObjectID,
        rectangle: NormalizedRectangle,
        sourceWidth: Int,
        sourceHeight: Int,
        tag: SnapshotAnnotationTag?,
    ) {
        precondition(sourceWidth > 0 && sourceHeight > 0, "Source dimensions must be positive")
        self.path = path
        self.target = target
        self.blobOID = blobOID
        self.rectangle = rectangle
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.tag = tag
    }

    public func marker() throws -> String {
        let data = try JSONEncoder.patchlight.encode(self)
        return "\(Self.markerPrefix)\(data.base64URLEncodedString()) -->"
    }

    /// Unknown marker versions return nil and remain ordinary visible comments.
    public static func parseMarker(in comment: String) throws -> SnapshotAnnotationV1? {
        guard let prefixRange = comment.range(of: markerPrefix) else { return nil }
        let payloadStart = prefixRange.upperBound
        guard let suffixRange = comment[payloadStart...].range(of: " -->") else {
            throw SnapshotAnnotationError.malformedMarker
        }
        let payload = String(comment[payloadStart ..< suffixRange.lowerBound])
        guard let data = Data(base64URLString: payload) else {
            throw SnapshotAnnotationError.malformedMarker
        }
        return try JSONDecoder().decode(Self.self, from: data)
    }
}

public enum SnapshotAnnotationError: LocalizedError, Equatable, Sendable {
    case invalidRectangle
    case malformedMarker

    public var errorDescription: String? {
        switch self {
            case .invalidRectangle:
                "Snapshot annotation rectangles must be positive and normalized to the image."
            case .malformedMarker:
                "The Patchlight snapshot annotation marker is malformed."
        }
    }
}

extension JSONEncoder {
    fileprivate static var patchlight: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension Data {
    fileprivate init?(base64URLString: String) {
        var value = base64URLString.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        self.init(base64Encoded: value)
    }

    fileprivate func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
