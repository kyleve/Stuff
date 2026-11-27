import Foundation
import Observation
import PeriscopeCore
import WhereCore

/// View-scoped model for the Settings backup section: export progress and the
/// error alert. Data Settings owns the model while it can present an export.
@MainActor
@Observable
public final class BackupModel {
    /// Where a backup export is in its lifecycle, so the UI can show a
    /// spinner and disable the relevant row while work is in flight.
    public enum BackupState: Equatable {
        case idle
        case exporting
    }

    public private(set) var backupState: BackupState = .idle

    /// Fraction (`0...1`) of the in-flight export that has completed, for
    /// a determinate progress bar. Reset to `0` whenever neither is running.
    public private(set) var backupProgress: Double = 0

    private var presentedError: String?

    /// Last backup failure, surfaced as an alert.
    public var backupError: String? {
        presentedError
    }

    /// Drives the backup-error alert. Reads `true` while `backupError` holds a
    /// message and clears it when dismissed, so the view can bind straight to it
    /// (`$backup.isShowingBackupError`).
    public var isShowingBackupError: Bool {
        get { backupError != nil }
        set {
            guard !newValue else { return }
            presentedError = nil
        }
    }

    private let services: WhereServices
    private static let logger = WhereLog.session(BackupModelLog.self)

    private enum ExportUpdate {
        case progress(Double)
        case archive(URL)
    }

    public init(services: WhereServices) {
        self.services = services
    }

    /// Build a backup `.zip` of the entire database and return its URL for the
    /// share sheet, or `nil` if the export failed (in which case `backupError` is
    /// set). The `BackupCoordinator` owns the temporary file's lifecycle — it
    /// reclaims the previous export's directory when the next export starts.
    ///
    /// Progress is streamed to `backupProgress` so the caller can show a
    /// determinate "Exporting…" bar.
    public func exportBackup() async -> URL? {
        guard backupState == .idle, !Task.isCancelled else { return nil }
        backupState = .exporting
        backupProgress = 0
        presentedError = nil
        defer {
            backupState = .idle
            backupProgress = 0
        }

        let (updates, continuation) = AsyncThrowingStream<ExportUpdate, any Error>.makeStream()
        let coordinator = services.backup
        let request = Task {
            do {
                let url = try await coordinator.exportBackup {
                    continuation.yield(.progress($0))
                }
                continuation.yield(.archive(url))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in
            request.cancel()
        }

        do {
            for try await update in updates {
                try Task.checkCancellation()
                switch update {
                    case let .progress(fraction): backupProgress = fraction
                    case let .archive(url):
                        Self.logger.exported()
                        return url
                }
            }
        } catch is CancellationError {
            return nil
        } catch {
            guard !Task.isCancelled else { return nil }
            presentBackupError(error)
            Self.logger.exportFailed(
                error: .restricted(.errorDetails, error),
            )
        }
        return nil
    }

    /// Delete the most recent export's temp file now — for a caller that's done
    /// offering it to share (e.g. its share affordance timed out). The
    /// `BackupCoordinator` owns the file, so deletion routes through it.
    public func discardExport() async {
        await services.backup.discardExport()
    }

    /// Surface an export error through the model's single presentation state.
    public func presentBackupError(_ error: any Error) {
        presentedError = error.localizedDescription
    }
}
