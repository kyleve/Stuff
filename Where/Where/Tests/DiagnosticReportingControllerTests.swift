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
        let log = Log<RemoteTestEvent>(recorder: fixture.logSystem)

        log { RemoteTestEvent(level: .debug) }
        log { RemoteTestEvent(level: .warning) }
        log { RemoteTestEvent(level: .error) }
        log { RemoteTestEvent(level: .fault) }
        await fixture.logSystem.flush()

        let entries = await fixture.writer.entries
        #expect(entries.map(\.level) == [.warning, .error, .error])
    }

    @Test func approvedExportExcludesPrivateContext() async throws {
        let configuration = DiagnosticReportingConfiguration.defaults(isDebugBuild: true)
        let fixture = Fixture(configuration: configuration)
        fixture.controller.start()
        let tagged = Log<RemoteTestEvent>(recorder: fixture.logSystem)
            .tagged(LogTagKey("private-tag"), "private-value")
        let log = tagged(for: "private-scope")

        log(
            attachments: [LogAttachment(
                name: "private-name",
                contentType: .plainText,
                data: Data("private-bytes".utf8),
            )],
        ) { RemoteTestEvent(level: .warning) }
        await fixture.logSystem.flush()

        let entry = try #require(await fixture.writer.entries.first)
        #expect(entry.message == "PII-free test event")
        #expect(entry.fields["event.count"] == .integer(7))
        #expect(entry.fields["event.payload"] == nil)
        #expect(entry.fields["context.tags"] == nil)
        #expect(entry.fields["context.scopes"] == nil)
        #expect(entry.fields["context.external_id"] == nil)
        #expect(entry.fields["attachments.metadata"] == nil)
        #expect(entry.fields.values.contains(.string("private-value")) == false)
        #expect(entry.fields.values.contains(.string("private-scope")) == false)
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
            let tagged = Log<RemoteTestEvent>(recorder: fixture.logSystem)
                .tagged(LogTagKey("private-tag"), "private-value")
            let log = tagged(for: "private-scope")

            log(attachments: [LogAttachment(
                name: "diagnostic.txt",
                contentType: .plainText,
                data: Data("never-transmit-these-bytes".utf8),
            )]) { RemoteTestEvent(level: .warning) }
            await fixture.logSystem.flush()

            let entry = try #require(await fixture.writer.entries.first)
            #expect(entry.fields["event.payload"] != nil)
            #expect(entry.fields["context.tags"] != nil)
            #expect(entry.fields["context.scopes"] != nil)
            #expect(entry.fields["context.external_id"] == .string("private-external-id"))
            #expect(entry.fields["attachments.metadata"] == .string("diagnostic.txt:text/plain"))
            #expect(entry.fields.values.contains(.string("never-transmit-these-bytes")) == false)
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
        let log = Log<RemoteTestEvent>(recorder: fixture.logSystem)
        log { RemoteTestEvent(level: .info) }
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

    @Test func asynchronousProviderFailureDetachesTheRemoteSink() async {
        let fixture = Fixture(configuration: .defaults(isDebugBuild: true))
        fixture.controller.start()

        await fixture.controller.providerDidFail()
        let log = Log<RemoteTestEvent>(recorder: fixture.logSystem)
        log { RemoteTestEvent(level: .warning) }
        await fixture.logSystem.flush()

        #expect(await fixture.writer.entries.isEmpty)
    }
}

private struct RemoteTestEvent: LogEvent {
    let level: LogLevel
    let count = 7
    var message: String {
        "PII-free test event"
    }

    var remoteMessage: String {
        message
    }

    var externalID: String? {
        "private-external-id"
    }

    var remoteFields: [RemoteLogField] {
        [RemoteLogField(key: RemoteLogFieldKey("count"), value: .count(count))]
    }
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

    init(writer: any BitdriftLogWriting) {
        self.writer = writer
    }

    func start(configuration: BitdriftLaunchConfiguration) throws {
        if let startError { throw startError }
        hasStarted = true
        startConfiguration = configuration
    }

    func setSleeping(_ isSleeping: Bool) {
        sleepStates.append(isSleeping)
    }
}
