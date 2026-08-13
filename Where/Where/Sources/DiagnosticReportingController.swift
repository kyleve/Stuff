import Foundation
import PeriscopeCore
import WhereCore
import WhereCrashReporting

@MainActor
protocol BitdriftReportingClientProtocol: AnyObject {
    var writer: any BitdriftLogWriting { get }
    var hasStarted: Bool { get }
    func start(configuration: BitdriftLaunchConfiguration) throws
    func setSleeping(_ isSleeping: Bool)
}

extension BitdriftReportingClient: BitdriftReportingClientProtocol {}

/// Reconciles launch-only reporting channels with the live Periscope export sink.
@MainActor
final class DiagnosticReportingController: WhereReportingController {
    enum Failure: Error, Equatable {
        case providerUnavailable
    }

    let launchConfiguration: DiagnosticReportingConfiguration

    private let client: any BitdriftReportingClientProtocol
    private let logSystem: Periscope
    private let now: @MainActor () -> Date
    private var remoteSink: BitdriftRemoteLogSink?
    private var remoteSinkToken: Periscope.SinkToken?
    private var latestRevision: UInt64 = 0

    init(
        launchConfiguration: DiagnosticReportingConfiguration,
        client: any BitdriftReportingClientProtocol,
        logSystem: Periscope,
        now: @escaping @MainActor () -> Date,
    ) {
        self.launchConfiguration = launchConfiguration
        self.client = client
        self.logSystem = logSystem
        self.now = now
    }

    func start() {
        guard launchConfiguration.requiresProvider else { return }
        do {
            try startProviderIfNeeded()
        } catch {
            assertionFailure("Could not start diagnostic reporting: \(error)")
            return
        }
        guard client.hasStarted else { return }
        if case .enabled = launchConfiguration.remoteLogging {
            attachRemoteSink(configuration: launchConfiguration.remoteLogging)
        }
    }

    func applyRemoteLogging(
        _ configuration: RemoteLoggingConfiguration,
        revision: UInt64,
    ) async throws {
        guard revision >= latestRevision else { return }
        latestRevision = revision

        if configuration == .off,
           launchConfiguration.sharesCrashReports || launchConfiguration.sharesSessionReplays
        {
            try startProviderIfNeeded()
        }

        switch configuration {
            case .off:
                guard let token = remoteSinkToken else {
                    sleepIfUnused(revision: revision)
                    return
                }
                remoteSinkToken = nil
                remoteSink = nil
                await logSystem.remove(token)
                guard revision == latestRevision else { return }
                sleepIfUnused(revision: revision)

            case .enabled:
                try startProviderIfNeeded()
                guard client.hasStarted else { throw Failure.providerUnavailable }
                client.setSleeping(false)
                if let remoteSink {
                    await remoteSink.update(configuration: configuration, effectiveFrom: now())
                    guard revision == latestRevision else { return }
                } else {
                    attachRemoteSink(configuration: configuration)
                }
        }
    }

    /// Reconciles an asynchronous SDK startup failure with the sink that may
    /// have been attached while the provider was still starting.
    func providerDidFail() async {
        latestRevision &+= 1
        guard let token = remoteSinkToken else { return }
        remoteSinkToken = nil
        remoteSink = nil
        await logSystem.remove(token)
    }

    private func startProviderIfNeeded() throws {
        guard !client.hasStarted else { return }
        try client.start(configuration: BitdriftLaunchConfiguration(
            enablesFatalIssueReporting: launchConfiguration.sharesCrashReports,
            enablesSessionReplay: launchConfiguration.sharesSessionReplays,
        ))
    }

    private func attachRemoteSink(configuration: RemoteLoggingConfiguration) {
        guard remoteSinkToken == nil else { return }
        let sink = BitdriftRemoteLogSink(
            configuration: configuration,
            effectiveFrom: now(),
            writer: client.writer,
        )
        remoteSink = sink
        remoteSinkToken = logSystem.add(sink: sink)
    }

    private func sleepIfUnused(revision: UInt64) {
        guard revision == latestRevision,
              !launchConfiguration.sharesCrashReports,
              !launchConfiguration.sharesSessionReplays
        else { return }
        client.setSleeping(true)
    }
}

extension DiagnosticReportingConfiguration {
    fileprivate var requiresProvider: Bool {
        sharesCrashReports || sharesSessionReplays || remoteLogging != .off
    }
}

/// Actor-isolated mapping from Periscope's live records to Bitdrift fields.
actor BitdriftRemoteLogSink: LogSink {
    private var configuration: RemoteLoggingConfiguration
    private var effectiveFrom: Date
    private let writer: any BitdriftLogWriting
    private var scopes: [ScopeID: LogScope] = [:]

    init(
        configuration: RemoteLoggingConfiguration,
        effectiveFrom: Date,
        writer: any BitdriftLogWriting,
    ) {
        self.configuration = configuration
        self.effectiveFrom = effectiveFrom
        self.writer = writer
    }

    func update(configuration: RemoteLoggingConfiguration, effectiveFrom: Date) {
        self.configuration = configuration
        self.effectiveFrom = effectiveFrom
    }

    func defineScopes(_ scopes: [LogScope]) {
        for scope in scopes {
            self.scopes[scope.id] = scope
        }
    }

    func write(_ records: [LogRecord]) async {
        guard case let .enabled(minimumLevel, metadataPolicy) = configuration else { return }
        for record in records
            where record.date >= effectiveFrom && record.level >= minimumLevel.periscopeLevel
        {
            await writer.write(entry(for: record, metadataPolicy: metadataPolicy))
        }
    }

    func flush() async {}

    private func entry(
        for record: LogRecord,
        metadataPolicy: RemoteLogMetadataPolicy,
    ) -> BitdriftLogEntry {
        var fields: [String: BitdriftLogValue] = [
            "event.name": .string(record.eventName),
            "event.version": .integer(record.eventVersion),
            "severity": .string(record.level.name),
        ]
        if let primaryScope = record.scopes.first,
           let root = LogScope.ancestry(of: primaryScope, resolve: { scopes[$0] }).first
        {
            fields["scope.root"] = .string(root.name)
        }
        if let callSite = record.callSite {
            fields["source.file"] = .string(callSite.fileID)
            fields["source.function"] = .string(callSite.function)
        }
        for field in record.event.remoteFields {
            fields["event.\(field.key.rawValue)"] = field.value.bitdriftValue
        }

        #if DEBUG
            if metadataPolicy == .allMetadataExcludingAttachmentData {
                addFullMetadata(from: record, to: &fields)
            }
        #endif

        return BitdriftLogEntry(
            level: record.level.bitdriftLevel,
            message: record.event.remoteMessage,
            fields: fields,
            file: record.callSite?.fileID,
            function: record.callSite?.function,
        )
    }

    #if DEBUG
        private func addFullMetadata(
            from record: LogRecord,
            to fields: inout [String: BitdriftLogValue],
        ) {
            fields["event.payload"] = encodedString(record.event)
            fields["context.tags"] = encodedString(record.tags)
            fields["context.scopes"] = .string(record.scopes.compactMap { id in
                let path = LogScope.ancestry(of: id, resolve: { scopes[$0] })
                return path.isEmpty ? nil : path.map(\.name).joined(separator: "/")
            }.joined(separator: ","))
            if let ambient = record.ambient {
                fields["context.ambient"] = encodedString(ambient)
            }
            if let externalID = record.externalID {
                fields["context.external_id"] = .string(externalID)
            }
            if !record.attachments.isEmpty {
                fields["attachments.metadata"] = .string(record.attachments.map {
                    "\($0.name):\($0.contentType.mimeType)"
                }.joined(separator: ","))
            }
        }

        private func encodedString(_ value: some Encodable) -> BitdriftLogValue {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                return try .string(String(decoding: encoder.encode(value), as: UTF8.self))
            } catch {
                assertionFailure("Could not encode full diagnostic metadata: \(error)")
                return .string("{}")
            }
        }
    #endif
}

extension LogLevel {
    fileprivate var bitdriftLevel: BitdriftLogLevel {
        switch self {
            case let level where level >= .error: .error
            case let level where level >= .warning: .warning
            case let level where level >= .notice: .info
            case let level where level >= .info: .info
            default: .debug
        }
    }
}

extension RemoteLogFieldValue {
    fileprivate var bitdriftValue: BitdriftLogValue {
        switch self {
            case let .boolean(value): .boolean(value)
            case let .count(value): .integer(value)
            case let .durationMilliseconds(value): .double(value)
            case let .category(value): .string(value.rawValue)
        }
    }
}
