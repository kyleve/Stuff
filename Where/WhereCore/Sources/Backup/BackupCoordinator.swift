import Foundation
import LogKit
import RegionKit

/// Owns backup export/import over the `BackupService` and the store, running a
/// caller-supplied `onImport` hook after an import lands new data.
///
/// An import rewrites day data, so the same badge / notification / widget
/// reconcile a `DayJournal` day change runs has to follow it. Rather than reach
/// into all those collaborators (a leaky abstraction), the coordinator takes one
/// `onImport` closure and the composition root points it at the shared fan-out —
/// so the reconcile stays defined in a single place.
///
/// Public so its `ImportStrategy` / `ImportSummary` types stay nameable from the
/// UI directly through `WhereServices.backup`; construction stays in-module via
/// the internal `init`.
public actor BackupCoordinator {
    /// How an imported backup combines with whatever is already on the device.
    public enum ImportStrategy: Sendable {
        /// Upsert the imported rows into the existing data (by `id` for
        /// samples/evidence, by day key for manual days), leaving anything not
        /// present in the file untouched.
        case merge
        /// Erase the whole store first so the device ends up mirroring the file
        /// exactly.
        case replace
    }

    /// Counts of what an import wrote, for a user-facing confirmation.
    public struct ImportSummary: Sendable, Hashable {
        public let sampleCount: Int
        public let evidenceCount: Int
        public let manualDayCount: Int
        public let dismissedIssueCount: Int
        public let trackedRegionCount: Int

        public init(
            sampleCount: Int,
            evidenceCount: Int,
            manualDayCount: Int,
            dismissedIssueCount: Int,
            trackedRegionCount: Int,
        ) {
            self.sampleCount = sampleCount
            self.evidenceCount = evidenceCount
            self.manualDayCount = manualDayCount
            self.dismissedIssueCount = dismissedIssueCount
            self.trackedRegionCount = trackedRegionCount
        }
    }

    private let store: any WhereStore
    private let backupService = BackupService()
    /// Invoked once after an import successfully commits. The composition root
    /// wires it to the same post-day-change reconcile a journal write runs
    /// (drop the issue-scan cache, reconcile the app-icon badge + issues
    /// notification, republish the widget snapshot).
    private let onImport: @Sendable () async -> Void
    private static let logger = WhereLog.channel(.backupService)

    /// Staging directory of the most recent export. Each archive lands in its
    /// own temporary directory; the share sheet copies the file it needs out of
    /// ours and gives no dismissal hook to clean up after, so we purge the
    /// previous export lazily when the next one starts (bounding us to one stale
    /// archive on disk). Actor-isolated, so it survives the UI that triggered
    /// the export being torn down.
    private var previousExportDirectory: URL?

    init(
        store: any WhereStore,
        onImport: @escaping @Sendable () async -> Void,
    ) {
        self.store = store
        self.onImport = onImport
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
        purgePreviousExport()

        let samples = try await store.allSamples()
        let evidence = try await store.allEvidence()
        let manualDays = try await store.allManualDays()
        let dismissedIssues = try await store.allDismissedIssues()
        // The resolved tracked set (the four when the user hasn't chosen yet),
        // in canonical order so the archive is stable.
        let trackedRegions = try await Region.inCanonicalOrder(store.trackedRegions())
        var blobs: [UUID: Data] = [:]
        var lastPercent = -1
        for (index, item) in evidence.enumerated() {
            if let blob = try await store.evidenceBlob(for: item.id) {
                blobs[item.id] = blob
            }
            let fraction = Double(index + 1) / Double(evidence.count) * Self.exportBlobLoadFraction
            let percent = Int(fraction * 100)
            guard percent != lastPercent else { continue }
            lastPercent = percent
            onProgress(fraction)
        }
        let backupService = backupService
        let url = try await Task.detached(priority: .utility) {
            try backupService.makeArchiveFile(
                samples: samples,
                evidence: evidence,
                manualDays: manualDays,
                dismissedIssues: dismissedIssues,
                trackedRegions: trackedRegions,
                blobs: blobs,
            )
        }.value
        onProgress(1)
        previousExportDirectory = url.deletingLastPathComponent()
        return url
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
            Self.logger.warning(
                "Failed to remove previous backup export directory: \(error.localizedDescription)",
            )
        }
    }

    /// Read a backup `.zip` and write its contents back into the store inside a
    /// single transaction. `.replace` wipes the store first; `.merge` relies on
    /// the store's upsert semantics. Tracked regions round-trip too: `.replace`
    /// restores the archive's set exactly, `.merge` unions it into the current
    /// set. Returns counts of what was imported.
    ///
    /// `onProgress` is invoked with a fraction in `0...1` as rows are written,
    /// throttled to whole-percent changes so a large import doesn't flood the
    /// caller. It runs on the store's executor; a UI caller should marshal it
    /// back to the main actor (e.g. via an `AsyncStream`).
    public func importBackup(
        from url: URL,
        strategy: ImportStrategy,
        onProgress: @Sendable (Double) -> Void = { _ in },
    ) async throws -> ImportSummary {
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
        let total = archive.samples.count + archive.evidence.count
            + archive.manualDays.count + archive.dismissedIssues.count

        try await store.perform {
            if strategy == .replace {
                try await store.clearAll()
            }
            // `completed`/`report` are local to this `@Sendable` block, so the
            // running count never crosses the actor boundary; only the throttled
            // fraction is handed to `onProgress`.
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
            // Tracked regions round-trip like any other data. On `.replace` the
            // store was cleared above, so write the archive's set exactly; on
            // `.merge` union it into the current set (reading the *resolved*
            // current set first so a device on the implicit default four doesn't
            // collapse to just the imported regions). A handful of rows, so
            // they're not folded into the progress total.
            let regionsToWrite: Set<Region> = if strategy == .merge {
                try await store.trackedRegions().union(archive.trackedRegions)
            } else {
                Set(archive.trackedRegions)
            }
            for region in regionsToWrite {
                try await store.setTrackedRegion(true, id: region.rawValue)
            }
        }
        // An import rewrites day data, so the badge / notification / widget
        // reconcile a day change runs has to follow it — these headless
        // reconcilers don't observe `store.changes()`, so without this the
        // home-screen badge and the issues alert stay stuck at their pre-import
        // values. The composition root supplies the shared fan-out.
        await onImport()

        return ImportSummary(
            sampleCount: archive.samples.count,
            evidenceCount: archive.evidence.count,
            manualDayCount: archive.manualDays.count,
            dismissedIssueCount: archive.dismissedIssues.count,
            trackedRegionCount: archive.trackedRegions.count,
        )
    }
}
