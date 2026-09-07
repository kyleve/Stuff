import Foundation
import PeriscopeCore
import Testing

private struct PhotoUploaded: LogEvent {
    var photoID: String
    var byteCount: Int
    var message: String {
        "Uploaded photo \(photoID) (\(byteCount) bytes)"
    }
}

private enum UploadKind: String, CaseIterable {
    case thumbnail
}

private struct ApprovedUpload: LogEvent {
    let byteCount: Int
    var message: String {
        "Uploaded"
    }

    var remoteFields: [RemoteLogField] {
        [
            RemoteLogField(key: RemoteLogFieldKey("byte_count"), value: .count(byteCount)),
            RemoteLogField(
                key: RemoteLogFieldKey("kind"),
                value: .category(RemoteLogCategory(UploadKind.thumbnail)),
            ),
        ]
    }
}

private struct DiskFull: LogEvent {
    static let eventName = "disk-full"
    static let eventVersion = 2
    var level: LogLevel {
        .error
    }

    var message: String {
        "Disk full"
    }
}

struct LogEventTests {
    @Test func eventNameDefaultsToTypeName() {
        #expect(PhotoUploaded.eventName == "PhotoUploaded")
    }

    @Test func eventNameCanBeOverridden() {
        #expect(DiskFull.eventName == "disk-full")
    }

    @Test func eventVersionDefaultsToOne() {
        #expect(PhotoUploaded.eventVersion == 1)
        #expect(DiskFull.eventVersion == 2)
    }

    @Test func levelDefaultsToInfo() {
        let event = PhotoUploaded(photoID: "p1", byteCount: 42)
        #expect(event.level == .info)
        #expect(DiskFull().level == .error)
    }

    @Test func remoteFieldsDefaultToEmpty() {
        #expect(PhotoUploaded(photoID: "private-id", byteCount: 42).remoteFields.isEmpty)
    }

    @Test func remoteFieldsCarryOnlyApprovedTypedValues() {
        #expect(ApprovedUpload(byteCount: 42).remoteFields == [
            RemoteLogField(key: RemoteLogFieldKey("byte_count"), value: .count(42)),
            RemoteLogField(
                key: RemoteLogFieldKey("kind"),
                value: .category(RemoteLogCategory(UploadKind.thumbnail)),
            ),
        ])
    }

    @Test func payloadRoundTripsThroughCodable() throws {
        let event = PhotoUploaded(photoID: "p1", byteCount: 42)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(PhotoUploaded.self, from: data)
        #expect(decoded.photoID == "p1")
        #expect(decoded.byteCount == 42)
        #expect(decoded.message == event.message)
    }
}
