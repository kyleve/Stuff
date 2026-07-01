import Foundation
import LogKit
import Observation
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
    }

    public private(set) var backupState: BackupState = .idle

    /// Fraction (`0...1`) of the in-flight import that has been written, for a
    /// determinate progress bar. Reset to `0` whenever an import isn't running.
    public private(set) var backupProgress: Double = 0

    /// Last backup failure, surfaced as an alert. Mutable so the alert binding
    /// can clear it on dismiss.
    public var backupError: String?

    /// Drives the backup-error alert. Reads `true` while `backupError` holds a
    /// message and clears it when dismissed, so the view can bind straight to it
    /// (`$backup.isShowingBackupError`). `backupError` stays the single source of
    /// truth.
    public var isShowingBackupError: Bool {
        get { backupError != nil }
        set { if !newValue { backupError = nil } }
    }

    /// Staging directory of the most recent export. The share sheet copies the
    /// file it needs out of our temporary directory, and `ShareLink` gives us no
    /// dismissal hook to clean up after, so the previous export is deleted lazily
    /// when the next one starts (bounding us to one stale archive).
    private var previousExportDirectory: URL?

    private let services: WhereServices
    private static let logger = WhereLog.channel(.session)

    public init(services: WhereServices) {
        self.services = services
    }

    /// Build a backup `.zip` of the entire database and return its URL for the
    /// share sheet, or `nil` if the export failed (in which case `backupError` is
    /// set). The caller is responsible for the returned temporary file.
    public func exportBackup() async -> URL? {
        if let previous = previousExportDirectory {
            try? FileManager.default.removeItem(at: previous)
            previousExportDirectory = nil
        }
        backupState = .exporting
        defer { backupState = .idle }
        do {
            let url = try await services.backup.exportBackup()
            previousExportDirectory = url.deletingLastPathComponent()
            Self.logger.info("Exported backup archive")
            return url
        } catch {
            backupError = error.localizedDescription
            Self.logger.warning("Backup export failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Import a backup file with the chosen merge/replace strategy. Returns the
    /// import summary on success, or `nil` on failure (with `backupError` set).
    /// The committed import pings the store-change signal, so the scene's
    /// `ReportModel` re-pulls the report + badge count — no inline refresh here.
    public func importBackup(
        from url: URL,
        strategy: BackupCoordinator.ImportStrategy,
    ) async -> BackupCoordinator.ImportSummary? {
        backupState = .importing
        backupProgress = 0
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
            let summary = try await services.backup.importBackup(from: url, strategy: strategy) {
                continuation.yield($0)
            }
            continuation.finish()
            await observer.value
            Self.logger.info(
                "Imported backup (\(summary.sampleCount) samples, \(summary.evidenceCount) evidence, \(summary.manualDayCount) manual days, \(summary.dismissedIssueCount) dismissals)",
            )
            return summary
        } catch {
            continuation.finish()
            backupError = error.localizedDescription
            Self.logger.warning("Backup import failed: \(error.localizedDescription)")
            return nil
        }
    }
}
