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
        exportMetadata: Data? = nil,
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
            exportMetadata: exportMetadata,
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

    @Test func filteredExportUsesPersistedPermissionsAndKeepsRawMessagesLocal() throws {
        let payload = Data(#"{"count":3,"sample_id":"sample-1","secret":"never-share"}"#.utf8)
        let metadata = try JSONEncoder().encode(LogExportMetadata(payload: .object([
            "count": .gated(.baseline(requiring: []), .value),
            "sample_id": .gated(.diagnostic(requiring: [.identifiers]), .value),
            "secret": .gated(.never, .value),
        ])))
        let snapshot = AmbientSnapshot(
            id: UUID(),
            values: [.network: ["private": "ambient-secret"]],
        )
        let event = stored(
            message: "never-share",
            date: date(1),
            payload: payload,
            exportMetadata: metadata,
            tags: [LogTag(key: LogTagKey("secret"), value: "tag-secret")],
            ambientSnapshotID: snapshot.id,
        )
        let session = makeSession(id: sessionID, attributes: [.commit: "session-secret"])
        let baseline = try NDJSONExporter.export(
            events: [event],
            scopes: scopes,
            sessions: [session],
            ambient: [snapshot.id: snapshot],
            mode: .filtered(.init(mode: .baseline, enabledControls: [])),
        )
        let object = try #require(try JSONSerialization
            .jsonObject(with: Data(baseline.utf8)) as? [String: Any])
        #expect(object["message"] as? String == "message")
        #expect(object["payload"] as? [String: Int] == ["count": 3])
        #expect(object["tags"] == nil)
        #expect(object["scopePath"] == nil)
        #expect(object["session"] == nil)
        #expect(object["ambient"] == nil)
        let identifiers = try NDJSONExporter.export(
            events: [event],
            scopes: scopes,
            sessions: [session],
            ambient: [snapshot.id: snapshot],
            mode: .filtered(.init(mode: .diagnostic, enabledControls: [.identifiers])),
        )
        #expect(identifiers.contains("sample-1"))
        #expect(identifiers.contains("never-share") == false)
        #expect(identifiers.contains("session-secret") == false)
        #expect(identifiers.contains("tag-secret") == false)
        let all = try NDJSONExporter.export(
            events: [event],
            scopes: scopes,
            sessions: [session],
            ambient: [snapshot.id: snapshot],
            mode: .filtered(.init(
                mode: .diagnostic,
                enabledControls: [.identifiers, .location, .userContent, .personalData],
            )),
        )
        #expect(all.contains("session-secret"))
        #expect(all.contains("tag-secret"))
        #expect(all.contains("never-share") == false)
        #expect(all.contains("ambient-secret") == false)
        let unfiltered = try NDJSONExporter.export(
            events: [event],
            scopes: scopes,
            sessions: [session],
            ambient: [snapshot.id: snapshot],
            mode: .unfiltered,
        )
        #expect(unfiltered.contains("never-share"))
        #expect(unfiltered.contains("ambient-secret"))
    }

    @Test func historicalRowsNeverFallBackToRawDataInFilteredMode() throws {
        let event = stored(
            message: "historical-secret",
            date: date(1),
            payload: Data(#"{"value":"historical-secret"}"#.utf8),
        )
        let export = try NDJSONExporter.export(
            events: [event],
            scopes: scopes,
            sessions: [makeSession(id: sessionID)],
            ambient: [:],
            mode: .filtered(.init(
                mode: .diagnostic,
                enabledControls: [.identifiers, .location, .userContent, .personalData],
            )),
        )
        let object = try #require(try JSONSerialization
            .jsonObject(with: Data(export.utf8)) as? [String: Any])
        #expect(Set(object.keys) == ["event", "version", "message", "level", "severity"])
        #expect(export.contains("historical-secret") == false)
    }

    @Test func invalidMetadataThrowsInsteadOfReturningAnUnfilteredFile() throws {
        let event = stored(
            message: "secret",
            date: date(1),
            payload: Data(#"{"secret":1}"#.utf8),
            exportMetadata: Data("invalid".utf8),
        )
        #expect(throws: DecodingError.self) {
            try NDJSONExporter.export(
                events: [event],
                scopes: scopes,
                sessions: [],
                ambient: [:],
                mode: .filtered(.init(mode: .diagnostic, enabledControls: [.personalData])),
            )
        }
    }

    @Test func exportsOneLinePerEventOldestFirst() throws {
        let export = try NDJSONExporter.export(
            events: [
                stored(message: "newest", date: date(2)),
                stored(message: "oldest", date: date(1)),
            ],
            scopes: scopes,
            sessions: [],
            ambient: [:],
            mode: .unfiltered,
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
        let export = try NDJSONExporter.export(
            events: [stored(message: "hello", date: date(1))],
            scopes: scopes,
            sessions: [unreferenced, session],
            ambient: [:],
            mode: .unfiltered,
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
        let payload = try JSONEncoder().encode(PhotoLogs(photoID: "p1"))
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
        #expect((object["payload"] as? [String: Any])?["photoID"] as? String == "p1")
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
            exportMetadata: nil,
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
