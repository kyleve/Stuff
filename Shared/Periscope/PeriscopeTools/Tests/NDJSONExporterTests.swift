import Foundation
import PeriscopeCore
@testable import PeriscopeTools
import Testing

struct NDJSONExporterTests {
    private let root = LogScope.root(named: "app")
    private let sessionID = UUID()

    private var scopes: [ScopeID: LogScope] {
        let photos = root.child(named: "photos")
        return [root.id: root, photos.id: photos]
    }

    private func stored(
        message: String,
        date: Date,
        payload: Data = Data(),
        tags: [LogTagKey: String] = [:],
    ) -> StoredLogEvent {
        StoredLogEvent(
            id: UUID(),
            date: date,
            level: .warning,
            eventName: "message",
            eventVersion: 1,
            message: message,
            payload: payload,
            scopes: [root.child(named: "photos").id],
            tags: tags,
            spanID: nil,
            attachments: [],
            sessionID: sessionID,
        )
    }

    @Test func exportsOneLinePerEventOldestFirst() {
        let export = NDJSONExporter.export(
            events: [
                stored(message: "newest", date: date(2)),
                stored(message: "oldest", date: date(1)),
            ],
            scopes: scopes,
        )

        let lines = export.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].contains("\"oldest\""))
        #expect(lines[1].contains("\"newest\""))
    }

    @Test func linesCarryTheEventFields() throws {
        let payload = try JSONEncoder().encode(PhotoLogs(photoID: "p1"))
        let line = NDJSONExporter.line(
            for: stored(
                message: "hello",
                date: date(1),
                payload: payload,
                tags: [LogTagKey("payment-id"): "pay_1"],
            ),
            scopes: scopes,
        )

        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
        )
        #expect(object["message"] as? String == "hello")
        #expect(object["level"] as? String == "warning")
        #expect(object["severity"] as? Int == LogLevel.warning.severity)
        #expect(object["scopePath"] as? String == "app/photos")
        #expect(object["session"] as? String == sessionID.uuidString)
        #expect((object["tags"] as? [String: String])?["payment-id"] == "pay_1")
        #expect((object["payload"] as? [String: Any])?["photoID"] as? String == "p1")
    }

    @Test func unknownScopesAndEmptyPayloadsExportCleanly() throws {
        let orphan = StoredLogEvent(
            id: UUID(),
            date: date(1),
            level: .info,
            eventName: "message",
            eventVersion: 1,
            message: "bare",
            payload: Data(),
            scopes: [LogScope.root(named: "never-defined").id],
            tags: [:],
            spanID: nil,
            attachments: [],
            sessionID: sessionID,
        )

        let line = NDJSONExporter.line(for: orphan, scopes: scopes)
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
        )
        #expect(object["scopePath"] == nil)
        #expect(object["payload"] == nil)
        #expect(object["message"] as? String == "bare")
    }
}
