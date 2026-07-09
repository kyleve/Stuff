import Foundation
#if canImport(UIKit)
    import UIKit
#endif

/// Arbitrary data attached to a log event — an error, a response body, a
/// screenshot, any payload that gives the event context. Attachments
/// persist with `@Attribute(.externalStorage)`, so large blobs live beside
/// the database rather than inside event rows.
public struct LogAttachment: Hashable, Sendable {
    public let name: String
    /// MIME type, e.g. `"application/json"`, `"image/png"`.
    public let contentType: String
    public let data: Data

    public init(name: String, contentType: String, data: Data) {
        self.name = name
        self.contentType = contentType
        self.data = data
    }
}

extension LogAttachment {
    /// An error, captured as JSON (description, domain, code).
    public static func error(_ error: any Error, name: String) -> LogAttachment {
        let bridged = error as NSError
        let payload: [String: String] = [
            "description": String(describing: error),
            "domain": bridged.domain,
            "code": String(bridged.code),
        ]
        // Encoding [String: String] cannot fail today; if a refactor ever
        // makes it possible, debug builds should stop rather than persist
        // an attachment that reads as a successful capture.
        let data: Data
        do {
            data = try JSONEncoder().encode(payload)
        } catch {
            assertionFailure("Encoding the error payload failed: \(error)")
            data = Data("{}".utf8)
        }
        return LogAttachment(name: name, contentType: "application/json", data: data)
    }

    /// Any `Encodable` value, captured as JSON.
    public static func json(_ value: some Encodable, name: String) throws -> LogAttachment {
        try LogAttachment(
            name: name,
            contentType: "application/json",
            data: JSONEncoder().encode(value),
        )
    }

    #if canImport(UIKit)
        /// An image, captured as PNG. Returns `nil` for images with no
        /// bitmap representation.
        public static func image(_ image: UIImage, name: String) -> LogAttachment? {
            guard let data = image.pngData() else { return nil }
            return LogAttachment(name: name, contentType: "image/png", data: data)
        }
    #endif
}

/// Attachment metadata as carried on queried events — the blob itself loads
/// on demand through `PeriscopeStore.attachments(forEvent:)`.
public struct LogAttachmentInfo: Hashable, Sendable {
    public let name: String
    public let contentType: String

    public init(name: String, contentType: String) {
        self.name = name
        self.contentType = contentType
    }
}
