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
        tags: [LogTag] = [],
        spanExitMode: SpanExit.Mode? = nil,
        ambientSnapshotID: UUID? = nil,
    ) -> StoredLogEvent {
        StoredLogEvent(
            id: UUID(),
            date: date,
            sequence: 0,
            level: .warning,
            eventName: "message",
            eventVersion: 1,
            message: message,
            payload: payload,
            scopes: [root.child(named: "photos").id],
            tags: tags,
            spanID: nil,
            spanExitMode: spanExitMode,
            callSite: nil,
            externalID: nil,
            attachments: [],
            sessionID: sessionID,
            ambientSnapshotID: ambientSnapshotID,
        )
    }

    @Test func unparseablePayloadsAreMarkedNotOmitted() throws {
        // Persisted payloads are JSONEncoder output, so garbage bytes mean
        // on-disk corruption — the export line must say a payload existed
        // and didn't survive, not silently drop the key.
        let line = NDJSONExporter.line(
            for: stored(message: "hello", date: date(1), payload: Data([0xFF, 0x00])),
            scopes: scopes,
            ambient: [:],
        )

        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
        )
        #expect(object["payload"] == nil)
        #expect(object["payloadError"] as? String == "unparseable (2 bytes)")
    }

    @Test func exportsOneLinePerEventOldestFirst() {
        let export = NDJSONExporter.export(
            events: [
                stored(message: "newest", date: date(2)),
                stored(message: "oldest", date: date(1)),
            ],
            scopes: scopes,
            sessions: [],
            ambient: [:],
        )

        let lines = export.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].contains("\"oldest\""))
        #expect(lines[1].contains("\"newest\""))
    }

    /// A duration in a bug report is only answerable when the export names
    /// the build it came from — the session header lines carry that, and
    /// only for sessions the events actually reference.
    @Test func referencedSessionsHeadTheExportWithTheirBuildAttribution() throws {
        let session = makeSession(
            id: sessionID,
            attributes: [.optimizationLevel: "-Onone", .commit: "abc123"],
        )
        let unreferenced = makeSession()
        let export = NDJSONExporter.export(
            events: [stored(message: "hello", date: date(1))],
            scopes: scopes,
            sessions: [unreferenced, session],
            ambient: [:],
        )

        let lines = export.split(separator: "\n")
        #expect(lines.count == 2)
        let header = try #require(
            try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any],
        )
        #expect(header["record"] as? String == "session")
        #expect(header["session"] as? String == sessionID.uuidString)
        #expect(header["appVersion"] as? String == session.appVersion)
        #expect(header["attributes"] as? [String: String] == [
            "optimization-level": "-Onone",
            "commit": "abc123",
        ])
        #expect(!export.contains(unreferenced.id.uuidString))
    }

    @Test func linesCarryTheEventFields() throws {
        let payload = try JSONEncoder().encode(makePhotoEvent("p1"))
        let line = NDJSONExporter.line(
            for: stored(
                message: "hello",
                date: date(1),
                payload: payload,
                tags: [LogTag(key: LogTagKey("payment-id"), value: "pay_1")],
            ),
            scopes: scopes,
            ambient: [:],
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
        #expect((object["payload"] as? [String: Any])?["photo_id"] as? String == "p1")
    }

    @Test func linesCarryTheSpanExitWhenPresent() throws {
        let line = NDJSONExporter.line(
            for: stored(message: "◀ save failed", date: date(1), spanExitMode: .failure),
            scopes: scopes,
            ambient: [:],
        )
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
        )
        #expect(object["spanExit"] as? String == "failure")
    }

    @Test func unknownScopesAndEmptyPayloadsExportCleanly() throws {
        let orphan = StoredLogEvent(
            id: UUID(),
            date: date(1),
            sequence: 0,
            level: .info,
            eventName: "message",
            eventVersion: 1,
            message: "bare",
            payload: Data(),
            scopes: [LogScope.root(named: "never-defined").id],
            tags: [],
            spanID: nil,
            spanExitMode: nil,
            callSite: nil,
            externalID: nil,
            attachments: [],
            sessionID: sessionID,
            ambientSnapshotID: nil,
        )

        let line = NDJSONExporter.line(for: orphan, scopes: scopes, ambient: [:])
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
        )
        #expect(object["scopePath"] == nil)
        #expect(object["payload"] == nil)
        #expect(object["message"] as? String == "bare")
    }

    @Test func linesCarryTheAmbientStateAsNestedObjects() throws {
        let snapshot = AmbientSnapshot(
            id: UUID(),
            values: [
                .network: ["status": "unsatisfied", "expensive": false],
                .powerMode: ["low-power": true],
            ],
        )
        let line = NDJSONExporter.line(
            for: stored(message: "offline", date: date(1), ambientSnapshotID: snapshot.id),
            scopes: scopes,
            ambient: [snapshot.id: snapshot],
        )

        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
        )
        let ambient = try #require(object["ambient"] as? [String: [String: Any]])
        #expect(ambient["network"]?["status"] as? String == "unsatisfied")
        #expect(ambient["network"]?["expensive"] as? Bool == false)
        #expect(ambient["power-mode"]?["low-power"] as? Bool == true)
    }

    /// Retention only drops unreferenced snapshots, so a referenced one
    /// going missing is an inconsistency the export must not render as
    /// "nothing was known about the system".
    @Test func missingAmbientSnapshotsAreMarkedNotOmitted() throws {
        let missing = UUID()
        let line = NDJSONExporter.line(
            for: stored(message: "offline", date: date(1), ambientSnapshotID: missing),
            scopes: scopes,
            ambient: [:],
        )

        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
        )
        #expect(object["ambient"] == nil)
        #expect(object["ambientError"] as? String == "snapshot \(missing.uuidString) not found")
    }
}
