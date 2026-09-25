import Foundation
import PeriscopeCore
import Testing
@testable import Where
import WhereCore
import WhereCrashReporting

@MainActor
struct DiagnosticReportingControllerTests {
    @Test(arguments: [
        DiagnosticReportingConfiguration(
            sharesCrashReports: false,
            sharesSessionReplays: false,
            remoteLogging: .off,
        ),
        DiagnosticReportingConfiguration(
            sharesCrashReports: true,
            sharesSessionReplays: false,
            remoteLogging: .off,
        ),
        DiagnosticReportingConfiguration(
            sharesCrashReports: false,
            sharesSessionReplays: true,
            remoteLogging: .off,
        ),
        DiagnosticReportingConfiguration.defaults(isDebugBuild: true),
    ])
    func startupMatrix(configuration: DiagnosticReportingConfiguration) {
        let fixture = Fixture(configuration: configuration)

        fixture.controller.start()

        let shouldStart = configuration.sharesCrashReports
            || configuration.sharesSessionReplays
            || configuration.remoteLogging != .off
        #expect(fixture.client.hasStarted == shouldStart)
        if shouldStart {
            #expect(fixture.client.startConfiguration == BitdriftLaunchConfiguration(
                enablesFatalIssueReporting: configuration.sharesCrashReports,
                enablesSessionReplay: configuration.sharesSessionReplays,
            ))
        }
    }

    @Test func mapsLevelsAndFiltersBelowTheThreshold() async {
        let configuration = DiagnosticReportingConfiguration.defaults(isDebugBuild: true)
        let fixture = Fixture(configuration: configuration)
        fixture.controller.start()
        let log = Log<RemoteTestLog>(recorder: fixture.logSystem)

        emit(.debug, to: log)
        emit(.warning, to: log)
        emit(.error, to: log)
        emit(.fault, to: log)
        await fixture.logSystem.flush()

        let entries = await fixture.writer.entries
        #expect(entries.map(\.level) == [.warning, .error, .error])
    }

    @Test func mapsEveryAcceptedStandardLevel() async {
        let configuration = DiagnosticReportingConfiguration(
            sharesCrashReports: false,
            sharesSessionReplays: false,
            remoteLogging: .enabled(minimumLevel: .debug, metadataPolicy: .approvedFields),
        )
        let fixture = Fixture(configuration: configuration)
        fixture.controller.start()
        let log = Log<RemoteTestLog>(recorder: fixture.logSystem)

        for level in LogLevel.standardLevels {
            emit(level, to: log)
        }
        await fixture.logSystem.flush()

        #expect(await fixture.writer.entries.map(\.level) == [
            .debug,
            .info,
            .info,
            .warning,
            .error,
            .error,
        ])
    }

    @Test func enabledPolicyDoesNotRetroactivelyExportOlderRecords() async {
        let writer = RecordingBitdriftWriter()
        let effectiveFrom = Date(timeIntervalSinceReferenceDate: 200)
        let sink = BitdriftRemoteLogSink(
            configuration: .enabled(
                minimumLevel: .debug,
                metadataPolicy: .approvedFields,
            ),
            effectiveFrom: effectiveFrom,
            writer: writer,
        )

        await sink.write([
            LogRecord(
                date: effectiveFrom.addingTimeInterval(-0.001),
                event: remoteTestEvent(level: .warning),
                scopes: [],
            ),
            LogRecord(
                date: effectiveFrom,
                event: remoteTestEvent(level: .warning),
                scopes: [],
            ),
        ])

        #expect(await writer.entries.count == 1)
    }

    @Test func approvedExportExcludesPrivateContext() async throws {
        let configuration = DiagnosticReportingConfiguration.defaults(isDebugBuild: true)
        let fixture = Fixture(configuration: configuration)
        fixture.controller.start()
        let tagged = Log<RemoteTestLog>(recorder: fixture.logSystem)
            .tagged(LogTagKey("private-tag"), "private-value")
        let log = tagged(for: "private-scope")

        log.event(
            level: .restricted(.technicalState, .warning),
            count: .shared(.count, 7),
            attachments: [LogAttachment(
                name: "private-name",
                contentType: .plainText,
                data: Data("private-bytes".utf8),
            )],
        )
        await fixture.logSystem.flush()

        let entry = try #require(await fixture.writer.entries.first)
        #expect(entry.message == "RemoteTest.event")
        #expect(entry.fields["event.count"] == .integer(7))
        #expect(entry.fields["event.payload"] == nil)
        #expect(entry.fields["context.tags"] == nil)
        #expect(entry.fields["context.scopes"] == nil)
        #expect(entry.fields["context.external_id"] == nil)
        #expect(entry.fields["attachments.metadata"] == nil)
        #expect(entry.fields.values.contains(.string("private-value")) == false)
        #expect(entry.fields.values.contains(.string("private-scope")) == false)
    }

    @Test func jsonExportsCanonicallyAsOneField() async throws {
        let writer = RecordingBitdriftWriter()
        let sink = BitdriftRemoteLogSink(
            configuration: .enabled(minimumLevel: .debug, metadataPolicy: .approvedFields),
            effectiveFrom: .distantPast,
            writer: writer,
        )
        let event = RemoteTestLog.InvalidJSON(json: .shared(
            .json,
            .object(["z": .array([.int(1), .bool(true)]), "a": .string("value")]),
        ))

        await sink.write([LogRecord(date: .now, event: event, scopes: [])])

        let entry = try #require(await writer.entries.first)
        #expect(entry.fields["event.json"] == .string(#"{"a":"value","z":[1,true]}"#))
        #expect(entry.fields.keys.contains("event.json.a") == false)
    }

    @Test func jsonEncodingFailureSkipsTheCompleteRecordAndIncrementsTheCounter() async {
        let writer = RecordingBitdriftWriter()
        let sink = BitdriftRemoteLogSink(
            configuration: .enabled(minimumLevel: .debug, metadataPolicy: .approvedFields),
            effectiveFrom: .distantPast,
            writer: writer,
        )
        let event = RemoteTestLog.InvalidJSON(json: .shared(.json, .double(.nan)))

        await sink.write([LogRecord(date: .now, event: event, scopes: [])])

        #expect(await writer.entries.isEmpty)
        #expect(await sink.encodingFailureCount == 1)
    }

    @Test func freeformTextIsExcludedFromBaselineExport() async throws {
        let writer = RecordingBitdriftWriter()
        let sink = BitdriftRemoteLogSink(
            configuration: .enabled(minimumLevel: .debug, metadataPolicy: .approvedFields),
            effectiveFrom: .distantPast,
            writer: writer,
        )
        let event = Message(
            level: .restricted(.technicalState, .info),
            text: .restricted(.arbitraryText, "private freeform text"),
        )

        await sink.write([LogRecord(date: .now, event: event, scopes: [])])

        let entry = try #require(await writer.entries.first)
        #expect(entry.message == "message.message")
        #expect(entry.fields.values.contains(.string("private freeform text")) == false)
    }

    #if DEBUG
        @Test func fullMetadataIncludesContextButNeverAttachmentBytes() async throws {
            let configuration = DiagnosticReportingConfiguration(
                sharesCrashReports: false,
                sharesSessionReplays: false,
                remoteLogging: .enabled(
                    minimumLevel: .warning,
                    metadataPolicy: .allMetadataExcludingAttachmentData,
                ),
            )
            let fixture = Fixture(configuration: configuration)
            fixture.controller.start()
            let tagged = Log<RemoteTestLog>(recorder: fixture.logSystem)
                .tagged(LogTagKey("private-tag"), "private-value")
            let log = tagged(for: "private-scope")

            log.event(
                level: .restricted(.technicalState, .warning),
                count: .shared(.count, 7),
                attachments: [LogAttachment(
                    name: "diagnostic.txt",
                    contentType: .plainText,
                    data: Data("never-transmit-these-bytes".utf8),
                )],
            )
            await fixture.logSystem.flush()

            let entry = try #require(await fixture.writer.entries.first)
            #expect(entry.fields["event.payload"] != nil)
            #expect(entry.fields["context.tags"] != nil)
            #expect(entry.fields["context.scopes"] != nil)
            #expect(entry.fields["context.external_id"] == .string("private-external-id"))
            #expect(entry.fields["attachments.metadata"] == .string("diagnostic.txt:text/plain"))
            #expect(entry.fields.values.contains(.string("never-transmit-these-bytes")) == false)
        }

        @Test func fullMetadataEncodingFailureNeverSubstitutesAnEmptyObject() async {
            let writer = RecordingBitdriftWriter()
            let sink = BitdriftRemoteLogSink(
                configuration: .enabled(
                    minimumLevel: .debug,
                    metadataPolicy: .allMetadataExcludingAttachmentData,
                ),
                effectiveFrom: .distantPast,
                writer: writer,
            )
            let event = RemoteTestLog.InvalidDebug(
                value: .restricted(.technicalState, .nan),
            )

            await sink.write([LogRecord(date: .now, event: event, scopes: [])])

            #expect(await writer.entries.isEmpty)
            #expect(await sink.encodingFailureCount == 1)
        }
    #endif

    @Test func detachDrainsThenSleepsWhenLaunchChannelsAreOff() async throws {
        let configuration = DiagnosticReportingConfiguration(
            sharesCrashReports: false,
            sharesSessionReplays: false,
            remoteLogging: .off,
        )
        let fixture = Fixture(configuration: configuration)

        try await fixture.controller.applyRemoteLogging(
            .enabled(minimumLevel: .info, metadataPolicy: .approvedFields),
            revision: 1,
        )
        let log = Log<RemoteTestLog>(recorder: fixture.logSystem)
        emit(.info, to: log)
        try await fixture.controller.applyRemoteLogging(.off, revision: 2)

        #expect(await fixture.writer.entries.count == 1)
        #expect(fixture.client.sleepStates.last == true)
    }

    @Test func olderRevisionCannotReenableLoggingAfterOff() async throws {
        let fixture = Fixture(configuration: DiagnosticReportingConfiguration(
            sharesCrashReports: false,
            sharesSessionReplays: false,
            remoteLogging: .off,
        ))

        try await fixture.controller.applyRemoteLogging(.off, revision: 4)
        try await fixture.controller.applyRemoteLogging(
            .enabled(minimumLevel: .debug, metadataPolicy: .approvedFields),
            revision: 3,
        )

        #expect(fixture.client.hasStarted == false)
    }

    @Test func providerStartFailurePropagatesFromImmediateApply() async {
        let fixture = Fixture(configuration: DiagnosticReportingConfiguration(
            sharesCrashReports: false,
            sharesSessionReplays: false,
            remoteLogging: .off,
        ))
        fixture.client.startError = .startup

        await #expect(throws: FakeBitdriftClient.Failure.startup) {
            try await fixture.controller.applyRemoteLogging(
                .enabled(minimumLevel: .warning, metadataPolicy: .approvedFields),
                revision: 1,
            )
        }
    }

    @Test func providerGatePreventsImmediateSinkAttachment() async {
        let fixture = Fixture(configuration: DiagnosticReportingConfiguration(
            sharesCrashReports: false,
            sharesSessionReplays: false,
            remoteLogging: .off,
        ))
        fixture.client.allowsStart = false

        await #expect(throws: DiagnosticReportingController.Failure.providerUnavailable) {
            try await fixture.controller.applyRemoteLogging(
                .enabled(minimumLevel: .warning, metadataPolicy: .approvedFields),
                revision: 1,
            )
        }
        let log = Log<RemoteTestLog>(recorder: fixture.logSystem)
        emit(.warning, to: log)
        await fixture.logSystem.flush()

        #expect(await fixture.writer.entries.isEmpty)
    }

    @Test func asynchronousProviderFailureDetachesTheRemoteSink() async {
        let fixture = Fixture(configuration: .defaults(isDebugBuild: true))
        fixture.controller.start()

        await fixture.controller.providerDidFail()
        let log = Log<RemoteTestLog>(recorder: fixture.logSystem)
        emit(.warning, to: log)
        await fixture.logSystem.flush()

        #expect(await fixture.writer.entries.isEmpty)
    }
}

@LogScope("RemoteTest")
private enum RemoteTestLog {
    @LogEvent("event")
    struct Event {
        @LogField("level", exposure: .restricted, kind: .technicalState)
        var level: LogLevel

        @LogField("count", exposure: .shareable, kind: .count)
        var count: Int

        var message: String {
            "PII-free test event"
        }

        var externalID: String? {
            "private-external-id"
        }
    }

    @LogEvent("invalid-json", message: "Invalid JSON")
    struct InvalidJSON {
        @LogField("json", exposure: .shareable, kind: .json)
        var json: JSONValue
    }

    @LogEvent("invalid-debug", message: "Invalid debug payload")
    struct InvalidDebug {
        @LogField("value", exposure: .restricted, kind: .technicalState)
        var value: Double
    }
}

private func remoteTestEvent(level: LogLevel) -> RemoteTestLog.Event {
    RemoteTestLog.Event(
        level: .restricted(.technicalState, level),
        count: .shared(.count, 7),
    )
}

private func emit(_ level: LogLevel, to log: Log<RemoteTestLog>) {
    log.event(
        level: .restricted(.technicalState, level),
        count: .shared(.count, 7),
    )
}

@MainActor
private struct Fixture {
    let writer = RecordingBitdriftWriter()
    let client: FakeBitdriftClient
    let logSystem = Periscope(configuration: .init(), sinks: [])
    let controller: DiagnosticReportingController

    init(configuration: DiagnosticReportingConfiguration) {
        let client = FakeBitdriftClient(writer: writer)
        self.client = client
        controller = DiagnosticReportingController(
            launchConfiguration: configuration,
            client: client,
            logSystem: logSystem,
            now: Date.init,
        )
    }
}

private actor RecordingBitdriftWriter: BitdriftLogWriting {
    private(set) var entries: [BitdriftLogEntry] = []

    func write(_ entry: BitdriftLogEntry) {
        entries.append(entry)
    }
}

@MainActor
private final class FakeBitdriftClient: BitdriftReportingClientProtocol {
    enum Failure: Error { case startup }

    let writer: any BitdriftLogWriting
    private(set) var hasStarted = false
    private(set) var startConfiguration: BitdriftLaunchConfiguration?
    private(set) var sleepStates: [Bool] = []
    var startError: Failure?
    var allowsStart = true

    init(writer: any BitdriftLogWriting) {
        self.writer = writer
    }

    func start(configuration: BitdriftLaunchConfiguration) throws {
        if let startError { throw startError }
        guard allowsStart else { return }
        hasStarted = true
        startConfiguration = configuration
    }

    func setSleeping(_ isSleeping: Bool) {
        sleepStates.append(isSleeping)
    }
}
