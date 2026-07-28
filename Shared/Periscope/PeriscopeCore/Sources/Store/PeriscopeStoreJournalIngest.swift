import Foundation
import JournalKit
import SwiftData

/// Journal ingest — the recovery half of crash durability. At launch,
/// before the new session starts, the store replays every prior session's
/// journal: records the async pipeline never delivered (the process died
/// first) are persisted, deduplicated against what did arrive, and the
/// journal is deleted. A journal that fails to ingest stays on disk for
/// the next launch to retry.
extension PeriscopeStore {
    /// Whether this process is an app extension (widget, share sheet, …).
    /// Extensions journal their own sessions but never ingest: ingest
    /// deletes journals, and an extension launching mid-app-session must
    /// not eat the live app's journal. The app's next launch ingests
    /// everyone's. (Full multi-process coordination — the reverse case of
    /// an app launch during a live extension session — is tracked in
    /// `Shared/Periscope/TODOs.md`.)
    private static let isAppExtension = Bundle.main.bundleURL.pathExtension == "appex"

    /// Ingest every prior session's journal under `Periscope-Journals/`.
    /// Runs before `startSession`, so recovered span begans participate in
    /// the orphan sweep. App processes only — see ``isAppExtension``.
    func ingestRecoveredJournals() async {
        guard !Self.isAppExtension else {
            Self.failureLogger.debug("Skipping crash journal ingest in an app extension")
            return
        }
        let root = journalsRoot
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let directories: [URL]
        do {
            directories = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
            )
        } catch {
            writeFailures += 1
            Self.failureLogger.warning("Failed to list crash journals: \(error)")
            return
        }
        for directory in directories {
            await ingestJournal(at: directory)
        }
    }

    private func ingestJournal(at directory: URL) async {
        do {
            let recovered = try JournalRecovery.recover(directory: directory)
            let journal = Self.parse(recovered.payloads)

            guard let session = journal.session else {
                // Without a session entry (a crash tore the very first
                // write) the records are unattributable; the journal can
                // only be discarded — but audibly.
                if !recovered.payloads.isEmpty {
                    Self.failureLogger.warning(
                        "Discarding a crash journal with no session entry (\(recovered.payloads.count) entries)",
                    )
                }
                try JournalRecovery.remove(directory: directory)
                return
            }

            await defineScopes(journal.scopes)
            let inserted = try persistRecovered(
                records: journal.records.sorted { $0.sequence < $1.sequence },
                session: session,
                recovery: recovered,
            )
            try JournalRecovery.remove(directory: directory)
            let hasGaps = recovered.foundTornEntry || recovered.droppedOlderEntries
            if inserted > 0 || hasGaps {
                notifyChanged()
                Self.failureLogger.info(
                    """
                    Recovered \(inserted) journaled event(s) from session \
                    \(session.id) (torn: \(recovered.foundTornEntry), \
                    rotated: \(recovered.droppedOlderEntries))
                    """,
                )
            }
        } catch {
            // Leave the journal for the next launch to retry.
            recoverFromFailedWrite()
            writeFailures += 1
            Self.failureLogger.warning(
                "Crash journal ingest failed for \(directory.lastPathComponent): \(error)",
            )
        }
    }

    private struct ParsedJournal {
        var session: LogSession?
        var scopes: [LogScope] = []
        var records: [LogJournalRecord] = []
    }

    private static func parse(_ payloads: [Data]) -> ParsedJournal {
        var parsed = ParsedJournal()
        for payload in payloads {
            // Undecodable entries skip: an unknown kind is a newer build's
            // (nil), and a corrupt payload can't be recovered — the
            // journal-level CRC already dropped torn entries.
            switch try? LogJournalEntry.decoded(from: payload) {
                case let .session(session):
                    parsed.session = parsed.session ?? session
                case let .scope(scope):
                    parsed.scopes.append(scope)
                case let .record(record):
                    parsed.records.append(record)
                case nil:
                    continue
            }
        }
        return parsed
    }

    /// Persist the recovered records the store doesn't already have, plus
    /// a marker recording the recovery — and, honestly, its gaps — in one
    /// save. Returns how many records were inserted.
    private func persistRecovered(
        records: [LogJournalRecord],
        session: LogSession,
        recovery: JournalRecovery.Recovered,
    ) throws -> Int {
        let existing = try existingEventIDs(among: records)
        let missing = records.filter { !existing.contains($0.id) }
        let hasGaps = recovery.foundTornEntry || recovery.droppedOlderEntries
        // A complete journal whose every record already arrived needs no
        // marker; a gappy one tells its story even when nothing inserts.
        guard !missing.isEmpty || hasGaps else { return 0 }

        let sessionRow = try fetchOrInsertSession(session)
        for record in missing {
            let scopeRows = try record.scopes.map { try scopeRow(for: $0) }
            let tagRows = try record.tags.map { try tagRow(for: $0) }
            let attachmentRows = record.attachments.enumerated()
                .compactMap { index, attachment -> SDLogAttachment? in
                    guard case let .inline(inline) = attachment else { return nil }
                    return SDLogAttachment(
                        name: inline.name,
                        contentType: inline.contentType.mimeType,
                        index: index,
                        data: inline.data,
                    )
                }
            let row = try SDLogEvent(
                eventID: record.id,
                date: record.date,
                sequence: takeSequence(),
                severity: record.severity,
                levelName: record.levelName,
                eventName: record.eventName,
                eventVersion: record.eventVersion,
                message: record.message,
                payload: record.payload,
                orderedScopeIDs: record.scopes,
                sessionID: sessionRow.sessionID,
                ambientSnapshotID: ambientRow(for: record.ambient, at: record.date)?
                    .snapshotID,
                spanID: record.spanID,
                spanExitMode: record.spanExitMode,
                callFunction: record.callFunction,
                callFileID: record.callFileID,
                externalID: record.externalID,
                scopes: scopeRows,
                tags: tagRows,
                attachments: attachmentRows,
            )
            modelContext.insert(row)
        }

        // The recovery is itself diagnostic gold — mark it in the story,
        // attributed to the crashed session, and be honest about what the
        // journal could *not* preserve. Gaps escalate the marker to
        // .warning (degraded but handled).
        var text = "Recovered \(missing.count) event(s) from this session's crash journal"
        if recovery.foundTornEntry {
            text += "; the journal ended in a torn entry (its record is lost)"
        }
        if recovery.droppedOlderEntries {
            text += "; older entries were dropped by the journal's byte budget"
        }
        let notice = Message(level: hasGaps ? .warning : .notice, text)
        let marker = try SDLogEvent(
            eventID: UUID(),
            date: Date(),
            sequence: takeSequence(),
            severity: notice.level.severity,
            levelName: notice.level.name,
            eventName: Message.eventName,
            eventVersion: Message.eventVersion,
            message: notice.message,
            payload: JSONEncoder().encode(notice),
            orderedScopeIDs: [],
            sessionID: sessionRow.sessionID,
            // The marker describes the recovery, not a moment in the
            // crashed session — it has no ambient state of its own.
            ambientSnapshotID: nil,
            spanID: nil,
            spanExitMode: nil,
            callFunction: nil,
            callFileID: nil,
            externalID: nil,
            scopes: [],
            tags: [],
            attachments: [],
        )
        modelContext.insert(marker)

        try throwInjectedFailureIfPending()
        try modelContext.save()
        return missing.count
    }

    /// The recovered IDs the store already persisted (the drain delivered
    /// them before the crash), fetched in chunks.
    private func existingEventIDs(among records: [LogJournalRecord]) throws -> Set<UUID> {
        var existing: Set<UUID> = []
        let ids = records.map(\.id)
        for start in stride(from: 0, to: ids.count, by: 500) {
            let chunk = Array(ids[start ..< min(start + 500, ids.count)])
            let descriptor = FetchDescriptor<SDLogEvent>(
                predicate: #Predicate { chunk.contains($0.eventID) },
            )
            try existing.formUnion(modelContext.fetch(descriptor).map(\.eventID))
        }
        return existing
    }

    /// The crashed session's row — usually already saved by that launch's
    /// `startSession`; inserted from the journal's copy when the crash
    /// preceded even that.
    private func fetchOrInsertSession(_ session: LogSession) throws -> SDLogSession {
        let id = session.id
        var descriptor = FetchDescriptor<SDLogSession>(
            predicate: #Predicate { $0.sessionID == id },
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let row = SDLogSession(session: session)
        modelContext.insert(row)
        return row
    }
}
