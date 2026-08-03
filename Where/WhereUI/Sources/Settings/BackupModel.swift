import Foundation
import Observation
import PeriscopeCore
import WhereCore

/// View-scoped model for the Settings backup section: export/import progress and
/// the error alert. Owned as `@State` by `SettingsView`, so it's created when the
/// Settings tab is first shown and torn down with it — nothing here needs to
/// outlive the screen that drives it.
@MainActor
@Observable
public final class BackupModel {
    /// Where a backup export/import is in its lifecycle, so the UI can show a
    /// spinner and disable the relevant row while work is in flight.
    public enum BackupState: Equatable {
        case idle
        case exporting
        case importing
        case recoveringImportCleanup
    }

    /// UI mirror of the long-lived coordinator's committed-import recovery gate. A newly
    /// created Settings model starts by checking rather than assuming imports are safe.
    public enum ImportRecoveryState: Equatable {
        case checking
        case ready
        case cleanupRequired(BackupCoordinator.ImportSummary)
    }

    /// The honest result of an import attempt. A committed cleanup failure is
    /// still a successful data import: keeping it distinct from `nil` prevents
    /// callers from offering a retry that would apply the archive twice.
    public enum ImportResult: Equatable {
        case imported(BackupCoordinator.ImportSummary)
        case committedWithCleanupFailure(BackupCoordinator.ImportSummary)

        public var summary: BackupCoordinator.ImportSummary {
            switch self {
                case let .imported(summary), let .committedWithCleanupFailure(summary):
                    summary
            }
        }

        public var requiresCleanupRecovery: Bool {
            if case .committedWithCleanupFailure = self { true } else { false }
        }
    }

    /// One pending acknowledgment at a time. Import success, committed partial
    /// success, and an operation failure cannot overlap in the presentation
    /// layer even if a caller starts another operation programmatically.
    private enum PresentedResult: Equatable {
        case failed(String)
        case importCompleted(ImportResult)
    }

    public private(set) var backupState: BackupState = .idle
    public private(set) var importRecoveryState: ImportRecoveryState = .checking

    public var importCleanupRecoverySummary: BackupCoordinator.ImportSummary? {
        if case let .cleanupRequired(summary) = importRecoveryState { summary } else { nil }
    }

    public var canImport: Bool {
        backupState == .idle && importRecoveryState == .ready
    }

    /// Fraction (`0...1`) of the in-flight export/import that has completed, for
    /// a determinate progress bar. Reset to `0` whenever neither is running.
    public private(set) var backupProgress: Double = 0

    private var presentedResult: PresentedResult?

    /// Last backup failure, surfaced as an alert.
    public var backupError: String? {
        guard case let .failed(message)? = presentedResult else { return nil }
        return message
    }

    /// Drives the backup-error alert. Reads `true` while `backupError` holds a
    /// message and clears it when dismissed, so the view can bind straight to it
    /// (`$backup.isShowingBackupError`).
    public var isShowingBackupError: Bool {
        get { backupError != nil }
        set {
            guard !newValue, case .failed? = presentedResult else { return }
            presentedResult = nil
        }
    }

    /// Result of the most recent committed import, surfaced as a confirmation
    /// or partial-success alert. Owned here so acknowledgment survives the
    /// backup screen being popped mid-import.
    public var lastImportResult: ImportResult? {
        guard case let .importCompleted(result)? = presentedResult else { return nil }
        return result
    }

    public var lastImportSummary: BackupCoordinator.ImportSummary? {
        lastImportResult?.summary
    }

    /// Drives the import-result alert for both complete and partial success.
    public var isShowingImportResult: Bool {
        get { lastImportResult != nil }
        set {
            guard !newValue, case .importCompleted? = presentedResult else { return }
            presentedResult = nil
        }
    }

    private let services: WhereServices
    private static let logger = WhereLog.session(BackupModelLog.self)

    public init(services: WhereServices) {
        self.services = services
    }

    /// Synchronize the view-scoped mirror with the coordinator that outlives Settings. This is
    /// called when the section appears and before programmatic imports, so recreating the model
    /// cannot forget a committed cleanup failure.
    public func refreshImportRecoveryState() async {
        do {
            importRecoveryState = switch try await services.backup.importRecoveryState() {
                case .ready: .ready
                case let .cleanupRequired(summary),
                     let .onboardingAcknowledgementRequired(summary):
                    .cleanupRequired(summary)
            }
        } catch {
            importRecoveryState = .checking
            presentBackupError(error)
        }
    }

    /// Build a backup `.zip` of the entire database and return its URL for the
    /// share sheet, or `nil` if the export failed (in which case `backupError` is
    /// set). The `BackupCoordinator` owns the temporary file's lifecycle — it
    /// reclaims the previous export's directory when the next export starts.
    ///
    /// Progress is streamed to `backupProgress` so the caller can show a
    /// determinate "Exporting…" bar, using the same ordered-stream marshaling as
    /// `importBackup` (see there for why).
    public func exportBackup() async -> URL? {
        backupState = .exporting
        backupProgress = 0
        presentedResult = nil
        defer {
            backupState = .idle
            backupProgress = 0
        }

        let (progress, continuation) = AsyncStream<Double>.makeStream()
        let observer = Task { @MainActor [weak self] in
            for await fraction in progress {
                self?.backupProgress = fraction
            }
        }
        defer { observer.cancel() }

        do {
            let url = try await services.backup.exportBackup { continuation.yield($0) }
            continuation.finish()
            await observer.value
            Self.logger { .exported }
            return url
        } catch {
            continuation.finish()
            presentBackupError(error)
            Self.logger { .exportFailed(description: error.localizedDescription) }
            return nil
        }
    }

    /// Delete the most recent export's temp file now — for a caller that's done
    /// offering it to share (e.g. its share affordance timed out). The
    /// `BackupCoordinator` owns the file, so deletion routes through it.
    public func discardExport() async {
        await services.backup.discardExport()
    }

    /// Import a backup file with the chosen merge/replace strategy. Returns a
    /// committed result for complete or cleanup-partial success, or `nil` when
    /// the data transaction failed (with `backupError` set). A partial success
    /// is never flattened into failure: the archive is already applied and must
    /// not be imported again.
    ///
    /// The committed import pings the store-change signal, so the scene's
    /// `YearReportModel` re-pulls the report + badge count — no inline refresh here.
    public func importBackup(
        from url: URL,
        strategy: BackupCoordinator.ImportStrategy,
    ) async -> ImportResult? {
        await refreshImportRecoveryState()
        guard case .ready = importRecoveryState else {
            if let summary = importCleanupRecoverySummary {
                let result = ImportResult.committedWithCleanupFailure(summary)
                presentedResult = .importCompleted(result)
                return result
            }
            return nil
        }
        backupState = .importing
        backupProgress = 0
        presentedResult = nil
        defer {
            backupState = .idle
            backupProgress = 0
        }

        // The backup coordinator reports progress from its own executor; funnel
        // it through an ordered stream and apply it on the main actor so SwiftUI
        // sees in-order, hop-free updates.
        let (progress, continuation) = AsyncStream<Double>.makeStream()
        let observer = Task { @MainActor [weak self] in
            for await fraction in progress {
                self?.backupProgress = fraction
            }
        }
        defer { observer.cancel() }

        do {
            let summary = try await services.backup.importBackup(
                from: url,
                strategy: strategy,
                purpose: .settings,
            ) {
                continuation.yield($0)
            }
            continuation.finish()
            await observer.value
            logImported(summary)
            let result = ImportResult.imported(summary)
            importRecoveryState = .ready
            presentedResult = .importCompleted(result)
            return result
        } catch let error as BackupCoordinator.CommittedImportCleanupError {
            continuation.finish()
            await observer.value
            logImported(error.summary)
            Self.logger(attachments: [.error(error.underlying, name: "cleanup-error")]) {
                .importCleanupFailed(description: error.underlying.localizedDescription)
            }
            let result = ImportResult.committedWithCleanupFailure(error.summary)
            importRecoveryState = .cleanupRequired(error.summary)
            presentedResult = .importCompleted(result)
            return result
        } catch let error as BackupCoordinator.ImportRecoveryRequiredError {
            continuation.finish()
            await observer.value
            let result = ImportResult.committedWithCleanupFailure(error.summary)
            importRecoveryState = .cleanupRequired(error.summary)
            presentedResult = .importCompleted(result)
            return result
        } catch {
            continuation.finish()
            presentBackupError(error)
            Self.logger { .importFailed(description: error.localizedDescription) }
            return nil
        }
    }

    /// Retry only the post-commit cleanup retained by the coordinator. The archive transaction
    /// is never replayed; success reopens importing and failure leaves the durable in-process
    /// gate in place for another retry.
    public func retryImportCleanup() async {
        guard backupState == .idle, importCleanupRecoverySummary != nil else { return }
        backupState = .recoveringImportCleanup
        presentedResult = nil
        defer { backupState = .idle }

        do {
            try await services.backup.retryImportCleanup()
            importRecoveryState = .ready
        } catch {
            await refreshImportRecoveryState()
            presentBackupError(error)
            Self.logger(attachments: [.error(error, name: "cleanup-retry-error")]) {
                .importCleanupFailed(description: error.localizedDescription)
            }
        }
    }

    /// Surface a file-selection or operation error through the model's single
    /// presentation state.
    public func presentBackupError(_ error: any Error) {
        presentedResult = .failed(error.localizedDescription)
    }

    private func logImported(_ summary: BackupCoordinator.ImportSummary) {
        Self.logger {
            .imported(
                sampleCount: summary.sampleCount,
                evidenceCount: summary.evidenceCount,
                manualDayCount: summary.manualDayCount,
                dismissedIssueCount: summary.dismissedIssueCount,
                trackedRegionCount: summary.trackedRegionCount,
            )
        }
    }
}
