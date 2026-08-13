import Foundation
import Observation
import WhereCore

/// Observable saved-versus-effective diagnostic reporting state for Settings.
@MainActor
@Observable
public final class DiagnosticReportingSettingsModel {
    public enum ApplyState: Equatable {
        case idle
        case applying
        case failed(message: String)
    }

    public typealias ApplyRemoteLogging = @MainActor @Sendable (
        RemoteLoggingConfiguration,
        UInt64,
    ) async throws -> Void

    public private(set) var savedConfiguration: DiagnosticReportingConfiguration
    public private(set) var effectiveRemoteLogging: RemoteLoggingConfiguration
    public private(set) var applyState: ApplyState = .idle
    public var isMetadataConfirmationPresented = false

    private let launchCrashReports: Bool
    private let launchSessionReplays: Bool
    private var effectiveCrashReports: Bool
    private var effectiveSessionReplays: Bool
    private let preferences: WherePreferences
    private let applyRemoteLogging: ApplyRemoteLogging
    private var revision: UInt64 = 0
    private var applyTask: Task<Void, Never>?

    public init(
        preferences: WherePreferences,
        effectiveConfiguration: DiagnosticReportingConfiguration,
        applyRemoteLogging: @escaping ApplyRemoteLogging,
    ) {
        self.preferences = preferences
        savedConfiguration = preferences.diagnosticReportingConfiguration
        launchCrashReports = effectiveConfiguration.sharesCrashReports
        launchSessionReplays = effectiveConfiguration.sharesSessionReplays
        effectiveCrashReports = effectiveConfiguration.sharesCrashReports
        effectiveSessionReplays = effectiveConfiguration.sharesSessionReplays
        effectiveRemoteLogging = effectiveConfiguration.remoteLogging
        self.applyRemoteLogging = applyRemoteLogging
    }

    public var effectiveConfiguration: DiagnosticReportingConfiguration {
        DiagnosticReportingConfiguration(
            sharesCrashReports: effectiveCrashReports,
            sharesSessionReplays: effectiveSessionReplays,
            remoteLogging: effectiveRemoteLogging,
        )
    }

    public var sharesCrashReports: Bool {
        get { savedConfiguration.sharesCrashReports }
        set {
            guard newValue != savedConfiguration.sharesCrashReports else { return }
            savedConfiguration.sharesCrashReports = newValue
            persist()
        }
    }

    public var sharesSessionReplays: Bool {
        get { savedConfiguration.sharesSessionReplays }
        set {
            guard newValue != savedConfiguration.sharesSessionReplays else { return }
            savedConfiguration.sharesSessionReplays = newValue
            persist()
        }
    }

    public var selectedRemoteLevel: RemoteLogLevel? {
        get { savedConfiguration.remoteLogging.minimumLevel }
        set { selectRemoteLevel(newValue) }
    }

    public var includesAllLogMetadata: Bool {
        savedConfiguration.remoteLogging.metadataPolicy == .allMetadataExcludingAttachmentData
    }

    public var includeAllMetadataToggle: Bool {
        get { includesAllLogMetadata }
        set {
            if newValue {
                guard !includesAllLogMetadata else { return }
                isMetadataConfirmationPresented = true
            } else {
                disableAllLogMetadata()
            }
        }
    }

    public var crashReportsPendingNextLaunch: Bool {
        savedConfiguration.sharesCrashReports != effectiveCrashReports
    }

    public var sessionReplaysPendingNextLaunch: Bool {
        savedConfiguration.sharesSessionReplays != effectiveSessionReplays
    }

    public func selectRemoteLevel(_ level: RemoteLogLevel?) {
        let metadataPolicy: RemoteLogMetadataPolicy
        #if DEBUG
            metadataPolicy = level == nil
                ? .approvedFields
                : savedConfiguration.remoteLogging.metadataPolicy
        #else
            metadataPolicy = .approvedFields
        #endif
        let configuration: RemoteLoggingConfiguration = if let level {
            .enabled(minimumLevel: level, metadataPolicy: metadataPolicy)
        } else {
            .off
        }
        guard configuration != savedConfiguration.remoteLogging else { return }
        savedConfiguration.remoteLogging = configuration
        persistAndApply(configuration)
    }

    public func enableAllLogMetadata() {
        guard let level = savedConfiguration.remoteLogging.minimumLevel else { return }
        let configuration = RemoteLoggingConfiguration.enabled(
            minimumLevel: level,
            metadataPolicy: .allMetadataExcludingAttachmentData,
        )
        guard configuration != savedConfiguration.remoteLogging else { return }
        savedConfiguration.remoteLogging = configuration
        persistAndApply(configuration)
    }

    public func confirmAllLogMetadata() {
        isMetadataConfirmationPresented = false
        enableAllLogMetadata()
    }

    public func disableAllLogMetadata() {
        guard let level = savedConfiguration.remoteLogging.minimumLevel else { return }
        let configuration = RemoteLoggingConfiguration.enabled(
            minimumLevel: level,
            metadataPolicy: .approvedFields,
        )
        guard configuration != savedConfiguration.remoteLogging else { return }
        savedConfiguration.remoteLogging = configuration
        persistAndApply(configuration)
    }

    public func retryRemoteLogging() {
        persistAndApply(savedConfiguration.remoteLogging)
    }

    public func recordRuntimeFailure(_ message: String) {
        effectiveCrashReports = false
        effectiveSessionReplays = false
        effectiveRemoteLogging = .off
        applyState = .failed(message: message)
    }

    /// Refreshes the saved mirror after the owning preferences removed every key.
    /// The new build default is applied live without writing those keys back.
    public func preferencesDidReset() {
        savedConfiguration = preferences.diagnosticReportingConfiguration
        isMetadataConfirmationPresented = false
        requestApply(savedConfiguration.remoteLogging, persist: false)
    }

    private func persistAndApply(_ configuration: RemoteLoggingConfiguration) {
        requestApply(configuration, persist: true)
    }

    private func requestApply(
        _ configuration: RemoteLoggingConfiguration,
        persist shouldPersist: Bool,
    ) {
        if shouldPersist {
            persist()
        }
        revision &+= 1
        let requestedRevision = revision
        applyTask?.cancel()
        applyState = .applying
        applyTask = Task { [weak self, applyRemoteLogging] in
            do {
                try await applyRemoteLogging(configuration, requestedRevision)
                try Task.checkCancellation()
                guard let self, revision == requestedRevision else { return }
                effectiveCrashReports = launchCrashReports
                effectiveSessionReplays = launchSessionReplays
                effectiveRemoteLogging = configuration
                applyState = .idle
            } catch is CancellationError {
                return
            } catch {
                guard let self, revision == requestedRevision else { return }
                applyState = .failed(message: String(describing: error))
            }
        }
    }

    private func persist() {
        preferences.diagnosticReportingConfiguration = savedConfiguration
    }
}
