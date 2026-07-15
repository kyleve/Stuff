import Foundation
import PeriscopeCore
import Testing
#if canImport(UIKit)
    import UIKit
#endif

private struct DownloadFailure: Error {}

struct LogAttachmentTests {
    @Test func rawDataAttachmentKeepsItsFields() {
        let attachment = LogAttachment(
            name: "response",
            contentType: .other("application/octet-stream"),
            data: Data([1, 2, 3]),
        )
        #expect(attachment.name == "response")
        #expect(attachment.contentType.mimeType == "application/octet-stream")
        #expect(attachment.data == Data([1, 2, 3]))
    }

    @Test func contentTypesRoundTripThroughTheirMIMEStrings() {
        let known: [LogAttachment.ContentType] = [.json, .png, .jpeg, .plainText]
        for type in known {
            #expect(LogAttachment.ContentType(mimeType: type.mimeType) == type)
        }
        let uncommon = LogAttachment.ContentType(mimeType: "application/octet-stream")
        #expect(uncommon == .other("application/octet-stream"))
        #expect(uncommon.mimeType == "application/octet-stream")
    }

    @Test func errorAttachmentCapturesDescriptionDomainAndCode() throws {
        let error = NSError(domain: "com.stuff.test", code: 42, userInfo: nil)
        let attachment = LogAttachment.error(error, name: "failure")

        #expect(attachment.contentType == .json)
        let decoded = try JSONDecoder().decode([String: String].self, from: attachment.data)
        #expect(decoded["domain"] == "com.stuff.test")
        #expect(decoded["code"] == "42")
        #expect(decoded["description"]?.isEmpty == false)
    }

    @Test func swiftErrorsAttachToo() throws {
        let attachment = LogAttachment.error(DownloadFailure(), name: "failure")
        let decoded = try JSONDecoder().decode([String: String].self, from: attachment.data)
        #expect(decoded["description"]?.contains("DownloadFailure") == true)
    }

    @Test func jsonAttachmentRoundTripsEncodableValues() throws {
        let attachment = try LogAttachment.json(PhotoLogs(photoID: "p1"), name: "photo")
        #expect(attachment.contentType == .json)
        let decoded = try JSONDecoder().decode(PhotoLogs.self, from: attachment.data)
        #expect(decoded.photoID == "p1")
    }

    #if canImport(UIKit)
        @Test func imageAttachmentEncodesPNG() throws {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
            let image = renderer.image { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            }

            let attachment = try #require(LogAttachment.image(image, name: "screenshot"))
            #expect(attachment.contentType == .png)
            #expect(!attachment.data.isEmpty)
        }
    #endif
}
