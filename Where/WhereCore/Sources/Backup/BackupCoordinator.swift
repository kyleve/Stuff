import Foundation
import PeriscopeCore
import RegionKit

/// Owns backup export/import over the `BackupService` and the store. Its lifecycle seam lets the
/// composition root pause recording before the transaction, restore the local choice after a
/// rollback, and reconcile all derived state after a commit.
///
/// Public so its `ImportStrategy` / `ImportSummary` types stay nameable from the
/// UI directly through `WhereServices.backup`; construction stays in-module via
/// the internal `init`.
public actor BackupCoordinator {
    /// How an imported backup combines with whatever is already on the device.
    public enum ImportStrategy: Sendable, Hashable {
        /// Upsert the imported rows into the existing data (by `id` for
        /// samples/evidence, by day key for manual days), leaving anything not
        /// present in the file untouched. Local recording consent is not stored in the archive.
        case merge
        /// Replace synced user history and settings with the file. Local recording consent is
        /// untouched, and existing removals are retained so restore cannot reactivate a device.
        case replace
    }

    /// Counts of what an import wrote, for a user-facing confirmation.
    public struct ImportSummary: Sendable, Hashable {
        public let sampleCount: Int
        public let evidenceCount: Int
        public let manualDayCount: Int
        public let dismissedIssueCount: Int
        public let trackedRegionCount: Int
        public let recordingDeviceCount: Int
        public let recordingDeviceRemovalCount: Int

        public init(
            sampleCount: Int,
            evidenceCount: Int,
            manualDayCount: Int,
            dismissedIssueCount: Int,
            trackedRegionCount: Int,
            recordingDeviceCount: Int,
            recordingDeviceRemovalCount: Int,
        ) {
            self.sampleCount = sampleCount
            self.evidenceCount = evidenceCount
            self.manualDayCount = manualDayCount
            self.dismissedIssueCount = dismissedIssueCount
            self.trackedRegionCount = trackedRegionCount
            self.recordingDeviceCount = recordingDeviceCount
            self.recordingDeviceRemovalCount = recordingDeviceRemovalCount
        }
    }

    /// Whether a committed import still needs its privacy-critical post-commit cleanup retried.
    public enum ImportRecoveryState: Sendable, Hashable {
        case ready
        case cleanupRequired(ImportSummary)
        case onboardingAcknowledgementRequired(ImportSummary)
    }

    private enum ImportRecoveryPhase {
        case ready
        case importing(UUID)
        case recoveryRequired(DurableImportRecovery)
        case retrying(DurableImportRecovery)

        var recovery: DurableImportRecovery? {
            switch self {
                case .ready, .importing: nil
                case let .recoveryRequired(recovery), let .retrying(recovery): recovery
            }
        }
    }

    /// Cross-collaborator work around an import transaction. Once the store commits, a
    /// `didCommit` failure is retained as an explicitly recoverable partial success rather than
    /// reported as though the transaction rolled back.
    struct ImportLifecycle {
        let prepare: @Sendable (ImportStrategy) async throws -> Void
        /// May throw only for privacy-critical cleanup after the data commit. The coordinator
        /// wraps that as an explicitly committed partial-success error and never runs rollback.
        let didCommit: @Sendable (ImportStrategy) async throws -> Void
        let didRollBack: @Sendable (ImportStrategy) async -> Void
    }

    private let store: any WhereStore
    private let backupService = BackupService()
    private let importLifecycle: ImportLifecycle
    private let importRecoveryPersistence: any BackupImportRecoveryPersisting
    private let currentDeviceID: RecordingDeviceID
    private let now: @Sendable () -> Date
    private static let logger = WhereLog.backup(BackupCoordinatorLog.self)

    private var importRecoveryPhase = ImportRecoveryPhase.ready
    private var hasHydratedImportRecovery = false
    private var isHydratingImportRecovery = false
    private var importRecoveryHydrationWaiters: [CheckedContinuation<Void, Never>] = []

    /// Staging directory of the most recent export. Each archive lands in its
    /// own temporary directory; the share sheet copies the file it needs out of
    /// ours and gives no dismissal hook to clean up after, so we purge the
    /// previous export lazily when the next one starts (bounding us to one stale
    /// archive on disk). Actor-isolated, so it survives the UI that triggered
    /// the export being torn down.
    private var previousExportDirectory: URL?

    init(
        store: any WhereStore,
        currentDeviceID: RecordingDeviceID,
        now: @escaping @Sendable () -> Date,
        importLifecycle: ImportLifecycle,
        importRecoveryPersistence: any BackupImportRecoveryPersisting,
    ) {
        self.store = store
        self.importLifecycle = importLifecycle
        self.importRecoveryPersistence = importRecoveryPersistence
        self.currentDeviceID = currentDeviceID
        self.now = now
    }

    /// Fraction of the export the evidence-blob load accounts for. The load is
    /// the only per-item loop we can subdivide, so it drives the determinate
    /// leg; the opaque encode + zip that follows has no sub-progress, so we hold
    /// here and jump to `1` once the archive file exists.
    private static let exportBlobLoadFraction = 0.8

    /// Serialize the entire store (all four tables plus evidence blobs) to a
    /// `.zip` in a fresh temporary directory and return its URL, first purging
    /// the previous export's directory. The caller shares the file; the next
    /// export (or process exit) reclaims the disk.
    ///
    /// `onProgress` is invoked with a fraction in `0...1` as the export
    /// advances, throttled to whole-percent changes so a large export doesn't
    /// flood the caller. Only the evidence-blob load reports incrementally (it's
    /// the one per-item loop); the JSON encode + zip is a single opaque step, so
    /// the fraction climbs to `exportBlobLoadFraction` during the load and then
    /// jumps to `1` once the archive is written. It runs on this actor's
    /// executor; a UI caller should marshal it back to the main actor (e.g. via
    /// an `AsyncStream`).
    public func exportBackup(
        onProgress: @Sendable (Double) -> Void = { _ in },
    ) async throws -> URL {
        try await Self.logger.measure(.exportBackup) {
            try await performExport(onProgress: onProgress)
        }
    }

    /// `exportBackup`'s body, split out so the outer span reads as one leg-by-leg
    /// tree rather than wrapping a `return`.
    private func performExport(
        onProgress: @Sendable (Double) -> Void,
    ) async throws -> URL {
        purgePreviousExport()

        let snapshot = try await store.readSnapshot {
            let tables = try await Self.logger.measure(.exportReads) {
                // The user's primary regions with their picked looks + order (the
                // resolved default set when they haven't chosen yet). Check-ins are deliberately
                // excluded: they are live proofs about a target's local outbox, not restorable
                // user data.
                try await ExportTables(
                    samples: store.allSamples(),
                    evidence: store.allEvidence(),
                    manualDays: store.allManualDays(),
                    dismissedIssues: store.allDismissedIssues(),
                    primaryRegions: store.primaryRegions(),
                    recordingDeviceProfiles: store.recordingDeviceProfiles(),
                    recordingDeviceMetadataChanges: store.recordingDeviceMetadataChanges(),
                    recordingDeviceRemovals: store.recordingDeviceRemovals(),
                    plannedStayRecords: store.plannedStayRecords(),
                )
            }
            let evidence = tables.evidence
            var blobs: [UUID: Data] = [:]
            try await Self.logger.measure(.exportBlobLoad) {
                var lastPercent = -1
                for (index, item) in evidence.enumerated() {
                    if let blob = try await store.evidenceBlob(for: item.id) {
                        blobs[item.id] = blob
                    }
                    let fraction = Double(index + 1) / Double(evidence.count)
                        * Self.exportBlobLoadFraction
                    let percent = Int(fraction * 100)
                    guard percent != lastPercent else { continue }
                    lastPercent = percent
                    onProgress(fraction)
                }
            }
            return ExportSnapshot(tables: tables, blobs: blobs)
        }
        let tables = snapshot.tables
        let backupService = backupService
        let url = try await Task.detached(priority: .utility) {
            try backupService.makeArchiveFile(
                samples: tables.samples,
                evidence: tables.evidence,
                manualDays: tables.manualDays,
                dismissedIssues: tables.dismissedIssues,
                // The bare ids ride alongside the primary regions for older readers.
                trackedRegions: tables.primaryRegions.map(\.region),
                primaryRegions: tables.primaryRegions,
                recordingDeviceProfiles: tables.recordingDeviceProfiles,
                recordingDeviceMetadataChanges: tables.recordingDeviceMetadataChanges,
                recordingDeviceRemovals: tables.recordingDeviceRemovals,
                plannedStayRecords: tables.plannedStayRecords,
                blobs: snapshot.blobs,
            )
        }.value
        onProgress(1)
        previousExportDirectory = url.deletingLastPathComponent()
        return url
    }

    /// Everything an export reads out of the store before it starts on blobs.
    /// A named value rather than five locals so the whole read leg fits inside
    /// one span without threading a tuple through it.
    private struct ExportTables {
        let samples: [LocationSample]
        let evidence: [Evidence]
        let manualDays: [DayPresence]
        let dismissedIssues: [DismissedIssue]
        let primaryRegions: [PrimaryRegion]
        let recordingDeviceProfiles: [RecordingDeviceProfile]
        let recordingDeviceMetadataChanges: [RecordingDeviceMetadataChange]
        let recordingDeviceRemovals: [RecordingDeviceRemoval]
        let plannedStayRecords: [PlannedStayRecord]
    }

    private struct ExportSnapshot {
        let tables: ExportTables
        let blobs: [UUID: Data]
    }

    /// Delete the most recent export's staging directory now, rather than
    /// lazily on the next export. For a caller that's finished offering the
    /// archive — e.g. a UI that times out its "share" affordance — so the temp
    /// file doesn't linger until the next export or process exit. A no-op when
    /// there's nothing left to reclaim.
    public func discardExport() {
        purgePreviousExport()
    }

    /// Delete the previous export's staging directory if we still have one. A
    /// failure here is non-fatal — a leftover temp directory only wastes a
    /// little disk — so it's logged rather than thrown, and never blocks the new
    /// export.
    private func purgePreviousExport() {
        guard let previous = previousExportDirectory else { return }
        previousExportDirectory = nil
        do {
            try FileManager.default.removeItem(at: previous)
        } catch {
            Self.logger { .removePreviousExportFailed(description: error.localizedDescription) }
        }
    }

    /// Read a backup `.zip` and write its contents back into the store inside a
    /// single transaction. `.replace` wipes user history/settings first while retaining the
    /// append-only device ledger; `.merge` relies on the store's upsert semantics. Tracked
    /// regions round-trip too: `.replace` restores the archive's set exactly, `.merge` unions it
    /// into the current set. Returns counts of what was imported.
    ///
    /// `onProgress` is invoked with a fraction in `0...1` as rows are written,
    /// throttled to whole-percent changes so a large import doesn't flood the
    /// caller. It runs on the store's executor; a UI caller should marshal it
    /// back to the main actor (e.g. via an `AsyncStream`).
    public func importBackup(
        from url: URL,
        strategy: ImportStrategy,
        onProgress: @Sendable (Double) -> Void,
    ) async throws -> ImportSummary {
        try await hydrateImportRecovery()
        let operationID = UUID()
        switch importRecoveryPhase {
            case .ready:
                importRecoveryPhase = .importing(operationID)
            case .importing:
                throw RecordingPersistenceError.recordingRewriteInProgress
            case let .recoveryRequired(recovery), let .retrying(recovery):
                throw ImportRecoveryRequiredError(summary: recovery.details.summary)
        }
        defer {
            if case let .importing(activeOperationID) = importRecoveryPhase,
               activeOperationID == operationID
            {
                importRecoveryPhase = .ready
            }
        }
        return try await Self.logger.measure(.importBackup) {
            try await performImport(
                from: url,
                strategy: strategy,
                transactionID: operationID,
                onProgress: onProgress,
            )
        }
    }

    /// Current recovery gate for backup UI. The coordinator owns this state so recreating a
    /// presentation model cannot accidentally reopen imports after a committed cleanup failure.
    public func importRecoveryState() async throws -> ImportRecoveryState {
        try await hydrateImportRecovery()
        guard let recovery = importRecoveryPhase.recovery else { return .ready }
        switch recovery {
            case let .committed(details, cleanupCompleted, onboardingAcknowledged)
            where cleanupCompleted
            && !onboardingAcknowledged:
                return .onboardingAcknowledgementRequired(details.summary)
            case .prepared, .committed:
                return .cleanupRequired(recovery.details.summary)
        }
    }

    /// Retry only the post-commit cleanup for the last committed import. The imported rows are
    /// never applied a second time, and the gate clears only after cleanup and reconciliation
    /// complete successfully.
    public func retryImportCleanup() async throws {
        try await hydrateImportRecovery()
        let recovery: DurableImportRecovery
        switch importRecoveryPhase {
            case .ready:
                return
            case .importing:
                throw RecordingPersistenceError.recordingRewriteInProgress
            case let .recoveryRequired(value):
                recovery = value
                importRecoveryPhase = .retrying(value)
            case let .retrying(value):
                throw ImportRecoveryRequiredError(summary: value.details.summary)
        }
        do {
            try await recoverCommittedImport(recovery)
        } catch {
            if case .retrying = importRecoveryPhase {
                importRecoveryPhase = .recoveryRequired(recovery)
            }
            throw CommittedImportCleanupError(
                strategy: recovery.details.strategy,
                summary: recovery.details.summary,
                underlying: error,
            )
        }
    }

    /// Record terminal onboarding authority, then clear a committed marker after `WhereModel`
    /// has written its preference. The sidecar tombstone repairs that preference after a crash.
    public func acknowledgeOnboardingImport() async throws {
        try await hydrateImportRecovery()
        guard let recovery = importRecoveryPhase.recovery else { return }
        guard case let .committed(
            details,
            cleanupCompleted,
            onboardingAcknowledged,
        ) = recovery else {
            throw ImportRecoveryRequiredError(summary: recovery.details.summary)
        }
        let acknowledged = DurableImportRecovery.committed(
            details,
            cleanupCompleted: cleanupCompleted,
            onboardingAcknowledged: true,
        )
        // UserDefaults may acknowledge its setter before the bytes reach disk. Persist an
        // independent, backup-excluded authority before marking recovery acknowledged or clearing
        // it, so every later path that observes `onboardingAcknowledged` is safe to finish cleanup.
        try await importRecoveryPersistence.recordOnboardingImportCompletion(.init(
            transactionID: details.transactionID,
        ))
        if !onboardingAcknowledged {
            try await importRecoveryPersistence.saveBackupImportRecovery(acknowledged)
            importRecoveryPhase = .recoveryRequired(acknowledged)
        }
        guard cleanupCompleted else { return }
        try await removeReceipt(for: details)
        try await importRecoveryPersistence.saveBackupImportRecovery(nil)
        importRecoveryPhase = .ready
    }

    /// `importBackup`'s body, split out for the same reason as
    /// ``performExport(onProgress:)``.
    private func performImport(
        from url: URL,
        strategy: ImportStrategy,
        transactionID: UUID,
        onProgress: @Sendable (Double) -> Void,
    ) async throws -> ImportSummary {
        let expectedGenerationID = try await (store.dataGeneration()).id
        // Files handed over by the document picker are security-scoped; we must
        // bracket the read with start/stop access or `Data(contentsOf:)` fails
        // with a permissions error.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let backupService = backupService
        let result = try await Task.detached(priority: .utility) {
            try backupService.readArchive(at: url)
        }.value
        let archive = result.archive
        let blobs = result.blobs
        let summary = ImportSummary(
            sampleCount: archive.samples.count,
            evidenceCount: archive.evidence.count,
            manualDayCount: archive.manualDays.count,
            dismissedIssueCount: archive.dismissedIssues.count,
            trackedRegionCount: archive.primaryRegions.count,
            recordingDeviceCount: archive.recordingDeviceProfiles.count,
            recordingDeviceRemovalCount: archive.recordingDeviceRemovals.count,
        )
        let recoveryDetails = ImportRecoveryDetails(
            transactionID: transactionID,
            strategy: strategy,
            summary: summary,
        )
        let total = archive.samples.count + archive.evidence.count
            + archive.manualDays.count + archive.dismissedIssues.count
            + archive.recordingDeviceProfiles.count
            + archive.recordingDeviceMetadataChanges.count
            + archive.recordingDeviceRemovals.count
            + archive.plannedStayRecords.count

        // Decode and validate before touching live recording. Once the archive is known-good,
        // close ingestion before either merge or replace so a streamed sample cannot cross the
        // transaction boundary.
        let preparedRecovery = DurableImportRecovery.prepared(recoveryDetails)
        try await importRecoveryPersistence.saveBackupImportRecovery(preparedRecovery)
        do {
            try await importLifecycle.prepare(strategy)
        } catch {
            do {
                try await importRecoveryPersistence.saveBackupImportRecovery(nil)
            } catch let persistenceError {
                importRecoveryPhase = .recoveryRequired(preparedRecovery)
                throw ImportRecoveryResolutionError(
                    summary: summary,
                    underlying: persistenceError,
                )
            }
            throw error
        }
        let importDate = now()
        do {
            try await Self.logger.measure(.importWrite) {
                try await store.perform(expectedDataGenerationID: expectedGenerationID) {
                    let preservedRemovals: [RecordingDeviceRemoval] = if strategy == .replace {
                        try await store.recordingDeviceRemovals()
                    } else {
                        []
                    }
                    if strategy == .replace {
                        _ = try await store.rotateDataGeneration(
                            reason: .backupReplace,
                            changedBy: currentDeviceID,
                            at: importDate,
                        )
                    }
                    // `completed`/`report` are local to this `@Sendable` block, so
                    // the running count never crosses the actor boundary; only the
                    // throttled fraction is handed to `onProgress`.
                    var completed = 0
                    var lastPercent = -1
                    func report() {
                        completed += 1
                        guard total > 0 else { return }
                        let percent = Int(Double(completed) / Double(total) * 100)
                        guard percent != lastPercent else { return }
                        lastPercent = percent
                        onProgress(Double(completed) / Double(total))
                    }
                    for sample in archive.samples {
                        try await store.add(sample: sample)
                        report()
                    }
                    for item in archive.evidence {
                        try await store.write(evidence: item, blob: blobs[item.id])
                        report()
                    }
                    for day in archive.manualDays {
                        try await store.setManualDay(day)
                        report()
                    }
                    for dismissal in archive.dismissedIssues {
                        try await store.restoreDismissedIssue(dismissal)
                        report()
                    }
                    for plannedStay in archive.plannedStayRecords {
                        try await store.restorePlannedStayRecord(plannedStay)
                        report()
                    }
                    for profile in archive.recordingDeviceProfiles {
                        try await store.addRecordingDeviceProfile(profile)
                        report()
                    }
                    for metadataChange in archive.recordingDeviceMetadataChanges {
                        try await store.addRecordingDeviceMetadataChange(metadataChange)
                        report()
                    }
                    for removal in preservedRemovals {
                        try await store.addRecordingDeviceRemoval(removal)
                    }
                    for removal in archive.recordingDeviceRemovals {
                        try await store.addRecordingDeviceRemoval(removal)
                        report()
                    }
                    // Primary regions (with their picked looks) round-trip like any
                    // other data. On `.replace` the store was cleared above, so write
                    // the archive's set exactly; on `.merge` union it into the current
                    // set (reading the *resolved* current set first so a device on the
                    // implicit default four doesn't collapse to just the imported
                    // ones), with the archive's appearance winning on overlap.
                    // `setPrimaryRegions` is a whole-set replace, so a merge builds
                    // the full merged list. A handful of rows, so they're not folded
                    // into the progress total.
                    let archivePrimary = archive.primaryRegions
                    let regionsToWrite: [PrimaryRegion] = if strategy == .merge {
                        try await Self.merge(archivePrimary, into: store.primaryRegions())
                    } else {
                        archivePrimary
                    }
                    try await store.setPrimaryRegions(regionsToWrite)
                    try await store.addBackupImportReceipt(
                        id: transactionID,
                        installationID: currentDeviceID,
                    )
                }
            }
        } catch {
            // `SwiftDataStore.perform` can throw after its peer save when a concurrent remote
            // generation supersedes the transaction. The receipt distinguishes that physical commit
            // from a true rollback; never reapply an archive whose rows already landed.
            let receipt: BackupImportReceipt?
            do {
                receipt = try await store.backupImportReceipt(
                    id: transactionID,
                    installationID: currentDeviceID,
                )
            } catch let receiptError {
                importRecoveryPhase = .recoveryRequired(preparedRecovery)
                throw ImportRecoveryResolutionError(
                    summary: summary,
                    underlying: receiptError,
                )
            }
            guard receipt != nil else {
                await importLifecycle.didRollBack(strategy)
                do {
                    try await importRecoveryPersistence.saveBackupImportRecovery(nil)
                } catch let persistenceError {
                    importRecoveryPhase = .recoveryRequired(preparedRecovery)
                    throw ImportRecoveryResolutionError(
                        summary: summary,
                        underlying: persistenceError,
                    )
                }
                throw error
            }
            do {
                try await finishCommittedImport(recoveryDetails)
            } catch {
                throw CommittedImportCleanupError(
                    strategy: strategy,
                    summary: summary,
                    underlying: error,
                )
            }
            throw CommittedImportSupersededError(summary: summary, underlying: error)
        }

        do {
            try await finishCommittedImport(recoveryDetails)
        } catch {
            throw CommittedImportCleanupError(
                strategy: strategy,
                summary: summary,
                underlying: error,
            )
        }

        return summary
    }

    /// Persist the irreversible boundary before cleanup, then advance monotonically through
    /// cleanup completion, receipt removal, and onboarding acknowledgement.
    private func finishCommittedImport(_ details: ImportRecoveryDetails) async throws {
        let cleanupPending = DurableImportRecovery.committed(
            details,
            cleanupCompleted: false,
            onboardingAcknowledged: false,
        )
        do {
            try await importRecoveryPersistence.saveBackupImportRecovery(cleanupPending)
        } catch {
            importRecoveryPhase = .recoveryRequired(.prepared(details))
            throw error
        }
        importRecoveryPhase = .recoveryRequired(cleanupPending)
        try await recoverCommittedImport(cleanupPending)
    }

    /// Resume a durable import from any safe restart point. Every transition is persisted before
    /// deleting the receipt that proves the store save, so a crash cannot turn a committed import
    /// back into an apparent rollback.
    private func recoverCommittedImport(_ recovery: DurableImportRecovery) async throws {
        let cleanupPending: DurableImportRecovery
        switch recovery {
            case let .prepared(details):
                let receipt = try await store.backupImportReceipt(
                    id: details.transactionID,
                    installationID: currentDeviceID,
                )
                guard receipt != nil else {
                    await importLifecycle.didRollBack(details.strategy)
                    try await importRecoveryPersistence.saveBackupImportRecovery(nil)
                    importRecoveryPhase = .ready
                    return
                }
                cleanupPending = .committed(
                    details,
                    cleanupCompleted: false,
                    onboardingAcknowledged: false,
                )
                do {
                    try await importRecoveryPersistence.saveBackupImportRecovery(cleanupPending)
                } catch {
                    importRecoveryPhase = .recoveryRequired(recovery)
                    throw error
                }
                importRecoveryPhase = .recoveryRequired(cleanupPending)
            case .committed:
                cleanupPending = recovery
        }

        let completed: DurableImportRecovery
        switch cleanupPending {
            case .prepared:
                preconditionFailure("Prepared recovery must be resolved before cleanup.")
            case let .committed(details, cleanupCompleted, onboardingAcknowledged):
                if cleanupCompleted {
                    completed = cleanupPending
                } else {
                    do {
                        try await importLifecycle.didCommit(details.strategy)
                    } catch {
                        importRecoveryPhase = .recoveryRequired(cleanupPending)
                        throw error
                    }
                    completed = .committed(
                        details,
                        cleanupCompleted: true,
                        onboardingAcknowledged: onboardingAcknowledged,
                    )
                    do {
                        try await importRecoveryPersistence.saveBackupImportRecovery(completed)
                    } catch {
                        importRecoveryPhase = .recoveryRequired(cleanupPending)
                        throw error
                    }
                    importRecoveryPhase = .recoveryRequired(completed)
                }
        }

        let details = completed.details
        do {
            try await removeReceipt(for: details)
        } catch {
            importRecoveryPhase = .recoveryRequired(completed)
            throw error
        }
        let onboardingAcknowledged: Bool
        switch completed {
            case .prepared:
                preconditionFailure("A completed recovery cannot be prepared.")
            case let .committed(_, _, acknowledged):
                onboardingAcknowledged = acknowledged
        }
        if onboardingAcknowledged {
            do {
                try await importRecoveryPersistence.saveBackupImportRecovery(nil)
            } catch {
                importRecoveryPhase = .recoveryRequired(completed)
                throw error
            }
            importRecoveryPhase = .ready
        } else {
            importRecoveryPhase = .recoveryRequired(completed)
        }
    }

    private func removeReceipt(for details: ImportRecoveryDetails) async throws {
        guard try await store.backupImportReceipt(
            id: details.transactionID,
            installationID: currentDeviceID,
        ) != nil else { return }
        try await store.perform {
            try await self.store.removeBackupImportReceipt(
                id: details.transactionID,
                installationID: self.currentDeviceID,
            )
        }
    }

    /// Load the sidecar exactly once per coordinator lifetime, serializing concurrent first
    /// callers. A prepared marker is resolved against its installation-scoped store receipt.
    private func hydrateImportRecovery() async throws {
        if hasHydratedImportRecovery { return }
        if isHydratingImportRecovery {
            await withCheckedContinuation { importRecoveryHydrationWaiters.append($0) }
            return try await hydrateImportRecovery()
        }
        isHydratingImportRecovery = true
        defer {
            isHydratingImportRecovery = false
            let waiters = importRecoveryHydrationWaiters
            importRecoveryHydrationWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }

        guard let recovery = try await importRecoveryPersistence.loadBackupImportRecovery() else {
            importRecoveryPhase = .ready
            hasHydratedImportRecovery = true
            return
        }
        switch recovery {
            case let .prepared(details):
                let receipt = try await store.backupImportReceipt(
                    id: details.transactionID,
                    installationID: currentDeviceID,
                )
                if receipt == nil {
                    await importLifecycle.didRollBack(details.strategy)
                    try await importRecoveryPersistence.saveBackupImportRecovery(nil)
                    importRecoveryPhase = .ready
                } else {
                    let committed = DurableImportRecovery.committed(
                        details,
                        cleanupCompleted: false,
                        onboardingAcknowledged: false,
                    )
                    try await importRecoveryPersistence.saveBackupImportRecovery(committed)
                    importRecoveryPhase = .recoveryRequired(committed)
                }
            case .committed:
                importRecoveryPhase = .recoveryRequired(recovery)
        }
        hasHydratedImportRecovery = true
    }

    /// A previous import committed but has not completed its privacy-critical cleanup. Applying
    /// another archive would erase the strategy and summary needed to finish that recovery.
    public struct ImportRecoveryRequiredError: LocalizedError, Sendable, Hashable {
        public let summary: ImportSummary

        public var errorDescription: String? {
            String(localized: .backupErrorRecoveryRequired)
        }
    }

    /// The sidecar exists but the coordinator could not determine or persist its next safe phase.
    public struct ImportRecoveryResolutionError: LocalizedError, @unchecked Sendable {
        public let summary: ImportSummary
        public let underlying: any Error

        public var errorDescription: String? {
            String(localized: .backupErrorRecoveryRequired)
        }
    }

    /// The import physically committed, but a newer destructive generation became authoritative
    /// before
    /// the call returned. The receipt prevents an automatic reapply into that newer generation.
    public struct CommittedImportSupersededError: LocalizedError, @unchecked Sendable {
        public let summary: ImportSummary
        public let underlying: any Error

        public var errorDescription: String? {
            String(localized: .backupErrorRecoveryRequired)
        }
    }

    /// The archive rows committed, but pending raw locations could not be removed safely. This
    /// is intentionally distinct from an import failure: callers must not retry as though the
    /// store rolled back, and recording remains paused until cleanup succeeds.
    public struct CommittedImportCleanupError: LocalizedError, @unchecked Sendable {
        public let strategy: ImportStrategy
        public let summary: ImportSummary
        public let underlying: any Error

        public var errorDescription: String? {
            switch strategy {
                case .merge:
                    String(localized: .backupErrorCommittedCleanupMerge)
                case .replace:
                    String(localized: .backupErrorCommittedCleanupReplace)
            }
        }
    }

    /// Union `archive` primary regions into `current` for a `.merge` import:
    /// current regions keep their order and come first, archive-only regions are
    /// appended, and the archive's picked appearance wins on overlap (a `nil`
    /// archive look never clobbers an existing customized one). Reindexed densely
    /// for `setPrimaryRegions`.
    private static func merge(
        _ archive: [PrimaryRegion],
        into current: [PrimaryRegion],
    ) -> [PrimaryRegion] {
        var appearances: [Region: RegionAppearance] = [:]
        var order: [Region] = []
        var seen: Set<Region> = []
        func add(_ region: Region) {
            if seen.insert(region).inserted { order.append(region) }
        }
        for entry in current {
            add(entry.region)
            if let appearance = entry.appearance { appearances[entry.region] = appearance }
        }
        for entry in archive {
            add(entry.region)
            if let appearance = entry.appearance { appearances[entry.region] = appearance }
        }
        return order.enumerated().map { index, region in
            PrimaryRegion(region: region, appearance: appearances[region], order: index)
        }
    }
}
