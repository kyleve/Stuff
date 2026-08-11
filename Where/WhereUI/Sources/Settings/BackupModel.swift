import Foundation
import Observation
import PeriscopeCore
import WhereCore

/// The export seam consumed by ``BackupModel``. Production delegates to the
/// scope's `BackupCoordinator`; tests use a conforming scripted exporter so
/// progress, cancellation, and failure can be proved without timing.
protocol BackupExporting: Sendable {
    func exportBackup(onProgress: @Sendable (Double) -> Void) async throws -> URL
    func discardExport() async
}

private struct WhereBackupExporter: BackupExporting {
    let coordinator: BackupCoordinator

    func exportBackup(onProgress: @Sendable (Double) -> Void) async throws -> URL {
        try await coordinator.exportBackup(onProgress: onProgress)
    }

    func discardExport() async {
        await coordinator.discardExport()
    }
}

/// View-scoped owner of one backup-export operation and its complete public
/// presentation state. Cancellation invalidates the operation before it can
/// publish a ready URL, so a covered or dismissed sheet cannot emit a late
/// success state or haptic.
@MainActor
@Observable
public final class BackupModel {
    public enum ExportState: Equatable {
        case idle
        case preparing(progress: Double)
        case ready(URL)
        case failed(message: String)
    }

    public private(set) var exportState = ExportState.idle

    private let exporter: any BackupExporting
    private var exportTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var activeOperationID: UUID?
    private static let logger = WhereLog.session(BackupModelLog.self)

    public init(services: WhereServices) {
        exporter = WhereBackupExporter(coordinator: services.backup)
    }

    init(exporter: any BackupExporting) {
        self.exporter = exporter
    }

    /// Start one export, returning the owned task so tests and non-View callers
    /// can await the real operation. Repeated input while work is active joins
    /// the existing task rather than starting overlapping coordinator exports.
    @discardableResult
    public func prepareExport() -> Task<Void, Never> {
        if let exportTask { return exportTask }

        let operationID = UUID()
        activeOperationID = operationID
        exportState = .preparing(progress: 0)
        let task = Task { [weak self] in
            guard let self else { return }
            await performExport(operationID: operationID)
        }
        exportTask = task
        return task
    }

    /// Cooperatively cancel the active export. Its underlying coordinator may
    /// need to finish an opaque encode before observing cancellation, but all
    /// presentation updates stop immediately and readiness is never published.
    public func cancelExport() {
        exportTask?.cancel()
        progressTask?.cancel()
    }

    /// Return a terminal presentation to idle after its sheet is dismissed or
    /// before the user explicitly retries. Active work must finish cancellation
    /// first, so resetting can never make an overlapping export spellable.
    public func resetExport() {
        guard exportTask == nil else { return }
        exportState = .idle
    }

    private func performExport(operationID: UUID) async {
        let (progress, continuation) = AsyncStream<Double>.makeStream()
        let observer = Task { @MainActor [weak self] in
            for await fraction in progress {
                guard !Task.isCancelled else { return }
                self?.acceptProgress(fraction, operationID: operationID)
            }
        }
        progressTask = observer

        let result: Result<URL, any Error>
        do {
            result = try await .success(exporter.exportBackup { fraction in
                continuation.yield(fraction)
            })
        } catch {
            result = .failure(error)
        }
        continuation.finish()

        if Task.isCancelled {
            observer.cancel()
        }
        await observer.value

        guard activeOperationID == operationID else {
            if case .success = result { await exporter.discardExport() }
            return
        }

        progressTask = nil
        exportTask = nil
        activeOperationID = nil

        if Task.isCancelled {
            if case .success = result { await exporter.discardExport() }
            exportState = .idle
            return
        }

        switch result {
            case let .success(url):
                exportState = .ready(url)
                Self.logger { .exported }
            case let .failure(error) where error is CancellationError:
                exportState = .idle
            case let .failure(error):
                exportState = .failed(message: error.localizedDescription)
                Self.logger { .exportFailed(description: error.localizedDescription) }
        }
    }

    private func acceptProgress(_ fraction: Double, operationID: UUID) {
        guard activeOperationID == operationID,
              exportTask?.isCancelled == false
        else { return }
        exportState = .preparing(progress: min(max(fraction, 0), 1))
    }

    #if DEBUG
        /// Force a final presentation state for previews and image snapshots.
        func previewExport(_ state: ExportState) {
            exportState = state
        }
    #endif
}
