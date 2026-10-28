import Foundation
import PeriscopeCore
import Testing

@LogScope("Photos")
private enum PhotoLog {
    @LogEvent("uploaded")
    struct Uploaded {
        @LogField("photo_id", exposure: .restricted, kind: .identifier)
        var photoID: String

        @LogField("byte_count", exposure: .restricted, kind: .count)
        var byteCount: Int

        var message: String {
            "Uploaded photo \(photoID) (\(byteCount) bytes)"
        }
    }

    enum UploadKind: String, CaseIterable, Codable { case thumbnail }

    @LogEvent("approved-upload", message: "Uploaded")
    struct ApprovedUpload {
        @LogField("byte_count", exposure: .shareable, kind: .count)
        var byteCount: Int

        @LogField("kind", exposure: .shareable, kind: .category)
        var kind: UploadKind
    }

    @LogEvent("disk-full", level: .error, message: "Disk full", version: 2)
    struct DiskFull {}

    @LogEvent("all-fields", message: "All fields")
    struct AllFields {
        @LogField("boolean", exposure: .shareable, kind: .boolean)
        var boolean: Bool

        @LogField("count", exposure: .shareable, kind: .count)
        var count: Int

        @LogField("limit", exposure: .shareable, kind: .limit)
        var limit: Int

        @LogField("duration", exposure: .shareable, kind: .duration)
        var duration: Duration

        @LogField("category", exposure: .shareable, kind: .category)
        var category: UploadKind

        @LogField("json", exposure: .shareable, kind: .json)
        var json: JSONValue

        @LogField("optional_count", exposure: .shareable, kind: .count)
        var optionalCount: Int?

        @LogField("pii", exposure: .restricted, kind: .pii)
        var pii: String

        @LogField("identifier", exposure: .restricted, kind: .identifier)
        var identifier: String?

        @LogField("location", exposure: .restricted, kind: .location)
        var location: String

        @LogField("user_content", exposure: .restricted, kind: .userContent)
        var userContent: String

        @LogField("error_details", exposure: .restricted, kind: .errorDetails)
        var errorDetails: String

        @LogField("date_time", exposure: .restricted, kind: .dateTime)
        var dateTime: Date

        @LogField("path", exposure: .restricted, kind: .pathOrURL)
        var path: URL

        @LogField("arbitrary_text", exposure: .restricted, kind: .arbitraryText)
        var arbitraryText: String

        @LogField("domain_value", exposure: .restricted, kind: .domainValue)
        var domainValue: UploadKind

        @LogField("technical_state", exposure: .restricted, kind: .technicalState)
        var technicalState: Bool
    }
}

struct LogEventTests {
    @Test func eventNameCombinesStableScopeAndEventIDs() {
        #expect(PhotoLog.Uploaded.eventName == "Photos.uploaded")
        #expect(PhotoLog.DiskFull.eventName == "Photos.disk-full")
    }

    @Test func eventVersionsDefaultAndCanBeExplicit() {
        #expect(PhotoLog.Uploaded.eventVersion == 1)
        #expect(PhotoLog.DiskFull.eventVersion == 2)
    }

    @Test func levelsDefaultAndCanBeFixed() {
        let event = PhotoLog.Uploaded(
            photoID: .restricted(.identifier, "p1"),
            byteCount: .restricted(.count, 42),
        )
        #expect(event.level == .info)
        #expect(PhotoLog.DiskFull().level == .error)
    }

    @Test func classifiedFieldsCarryOnlyApprovedValues() {
        let event = PhotoLog.ApprovedUpload(
            byteCount: .shared(.count, 42),
            kind: .shared(.category, .thumbnail),
        )
        #expect(event.classifiedFields == [
            .shareable(key: LogFieldKey("byte_count"), kind: .count, value: .int(42)),
            .shareable(key: LogFieldKey("kind"), kind: .category, value: .string("thumbnail")),
        ])
    }

    @Test func payloadRoundTripsWithoutWrapperMetadata() throws {
        let event = PhotoLog.Uploaded(
            photoID: .restricted(.identifier, "p1"),
            byteCount: .restricted(.count, 42),
        )
        let data = try JSONEncoder().encode(event)
        #expect(String(decoding: data, as: UTF8.self).contains("exposure") == false)
        let decoded = try JSONDecoder().decode(PhotoLog.Uploaded.self, from: data)
        #expect(decoded.photoID == "p1")
        #expect(decoded.byteCount == 42)
        #expect(decoded.message == event.message)
    }

    @Test func everyClassificationProjectsWithItsDeclaredPolicy() {
        let event = PhotoLog.AllFields(
            boolean: .shared(.boolean, true),
            count: .shared(.count, 3),
            limit: .shared(.limit, 10),
            duration: .shared(.duration, .milliseconds(1500)),
            category: .shared(.category, .thumbnail),
            json: .shared(.json, .object(["complete": .bool(true)])),
            optionalCount: .shared(.count, nil),
            pii: .restricted(.pii, "private"),
            identifier: .restricted(.identifier, nil),
            location: .restricted(.location, "private"),
            userContent: .restricted(.userContent, "private"),
            errorDetails: .restricted(.errorDetails, "private"),
            dateTime: .restricted(.dateTime, .distantPast),
            path: .restricted(.pathOrURL, URL(filePath: "/private")),
            arbitraryText: .restricted(.arbitraryText, "private"),
            domainValue: .restricted(.domainValue, .thumbnail),
            technicalState: .restricted(.technicalState, true),
        )

        #expect(event.classifiedFields == [
            .shareable(key: LogFieldKey("boolean"), kind: .boolean, value: .bool(true)),
            .shareable(key: LogFieldKey("count"), kind: .count, value: .int(3)),
            .shareable(key: LogFieldKey("limit"), kind: .limit, value: .int(10)),
            .shareable(key: LogFieldKey("duration"), kind: .duration, value: .double(1500)),
            .shareable(
                key: LogFieldKey("category"),
                kind: .category,
                value: .string("thumbnail"),
            ),
            .shareable(
                key: LogFieldKey("json"),
                kind: .json,
                value: .json(.object(["complete": .bool(true)])),
            ),
            .restricted(key: LogFieldKey("pii"), kind: .pii),
            .restricted(key: LogFieldKey("identifier"), kind: .identifier),
            .restricted(key: LogFieldKey("location"), kind: .location),
            .restricted(key: LogFieldKey("user_content"), kind: .userContent),
            .restricted(key: LogFieldKey("error_details"), kind: .errorDetails),
            .restricted(key: LogFieldKey("date_time"), kind: .dateTime),
            .restricted(key: LogFieldKey("path"), kind: .pathOrURL),
            .restricted(key: LogFieldKey("arbitrary_text"), kind: .arbitraryText),
            .restricted(key: LogFieldKey("domain_value"), kind: .domainValue),
            .restricted(key: LogFieldKey("technical_state"), kind: .technicalState),
        ])
    }
}
