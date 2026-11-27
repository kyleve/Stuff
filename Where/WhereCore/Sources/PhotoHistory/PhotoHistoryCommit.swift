import CryptoKit
import Foundation
import RegionKit

/// Sidecar identity only. No photo coordinates, library identifiers or draft leave memory before
/// Finish.
public struct PhotoHistoryReceipt: Codable, Hashable, Sendable {
    public let id: UUID
    public let installationID: RecordingDeviceID
    public let domain: DataCompatibilityDomain
    public let generation: WhereDataGenerationID
    public var acknowledged = false
}

public struct PhotoHistoryConflicts: Equatable, Sendable {
    public let manualDays: [DayPresence]
    public let priorPoints: [CalendarDay: [LocationSample]]
    public let primaryRegions: [PrimaryRegion]
    public let affectedDays: Set<CalendarDay>
    public var isEmpty: Bool {
        affectedDays.isEmpty && primaryRegions.isEmpty
    }
}

public struct PhotoHistoryResolution: Sendable {
    public let evidence: PhotoHistoryConflicts
    public let useReviewedDays: Set<CalendarDay>
    public let useReviewedPicks: Bool

    public init(
        evidence: PhotoHistoryConflicts,
        useReviewedDays: Set<CalendarDay>,
        useReviewedPicks: Bool,
    ) {
        self.evidence = evidence
        self.useReviewedDays = useReviewedDays
        self.useReviewedPicks = useReviewedPicks
    }
}

extension PhotoPoint {
    /// Canonical IEEE-754 bytes keep identity independent of locale and display rounding.
    var sampleID: UUID {
        var data = Data("Where.photo.v1".utf8)
        for value in [
            capturedAt.timeIntervalSinceReferenceDate,
            coordinate.latitude,
            coordinate.longitude,
        ] {
            var bits = (value == 0 ? 0 : value.bitPattern).bigEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return SHA256.hash(data: data)
            .withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }
}

extension WhereServices {
    public func preparePhotoReceipt(in domain: DataCompatibilityDomain) async throws
        -> PhotoHistoryReceipt
    {
        try await PhotoHistoryReceipt(
            id: UUID(),
            installationID: installationContext.currentDevice.id,
            domain: domain,
            generation: store.dataGeneration().id,
        )
    }

    public func hasCommittedPhotoHistory(_ receipt: PhotoHistoryReceipt) async throws -> Bool {
        guard receipt.installationID == installationContext.currentDevice.id else { return false }
        return try await store.readSnapshot {
            guard try await store.dataGeneration().id == receipt.generation else { return false }
            return try await store.backupImportReceipt(
                id: receipt.id,
                installationID: receipt.installationID,
            )?.dataGenerationID == receipt.generation
        }
    }

    public func reconcilePhotoHistory() async {
        if let live = attributor as? RegionAttribution { await live.reconcile() }
        await journal.reconcileAfterDayDataChange()
    }

    /// Returns current conflicting evidence without writing until the user resolves it.
    public func commitPhotoHistory(
        _ history: ReviewedPhotoHistory,
        primary: [PrimaryRegion],
        receipt: PhotoHistoryReceipt,
        resolution: PhotoHistoryResolution?,
    ) async throws -> PhotoHistoryConflicts? {
        guard receipt.installationID == installationContext.currentDevice.id
        else { throw RecordingPersistenceError.dataGenerationChanged }
        // Archive dates use Unix seconds. Normalize the approval instant to that representation
        // before the first save so a backup round trip retains the exact same audit value.
        let approvedAt = Date(timeIntervalSince1970: now().timeIntervalSince1970)
        let points = history.points.map { point in
            let observation = point.original.observation
            let attribution = PhotoStayAttribution(
                observedDay: point.original.day,
                observedRegion: point.original.region,
                day: point.day,
                region: point.region,
                approvedAt: approvedAt,
            )
            return LocationSample(
                id: observation.point.sampleID,
                timestamp: observation.point.capturedAt,
                coordinate: observation.point.coordinate,
                horizontalAccuracy: observation.accuracy ?? -1,
                source: .photo(attribution),
            )
        }
        let assertions = Dictionary(
            history.assertedDays.map { ($0.day, $0.regions) },
            uniquingKeysWith: { $0.union($1) },
        )
        var proposed = assertions
        for point in history.points {
            proposed[point.day, default: []].insert(point.region)
        }
        let regionsByDay = proposed
        return try await store.perform(expectedDataGenerationID: receipt.generation) {
            try await store.readSnapshot {
                try Task.checkCancellation()
                if try await store.backupImportReceipt(
                    id: receipt.id,
                    installationID: receipt.installationID,
                ) != nil { return nil }
                let existingPicks = if try await store
                    .hasExplicitPrimaryRegions() { try await store.primaryRegions() }
                else { [PrimaryRegion]() }
                let entries: [DayPresence] = if let first = regionsByDay.keys.min(),
                                                let last = regionsByDay.keys.max()
                {
                    try await store.manualDays(in: first ... last)
                } else { [] }
                let existing = Dictionary(
                    entries.map { ($0.day, $0) },
                    uniquingKeysWith: { first, _ in first },
                )
                let conflicts = entries.filter { row in
                    let additions = row
                        .isAuthoritative ? regionsByDay[row.day] : assertions[row.day]
                    return additions.map { !$0.isSubset(of: row.regions) } ?? false
                }.sorted { $0.day < $1.day }
                let prior: [UUID: LocationSample]
                if let start = points.map(\.timestamp).min(),
                   let end = points.map(\.timestamp).max()
                {
                    let samples = try await store.samples(in: DateInterval(
                        start: start.addingTimeInterval(-1),
                        end: end.addingTimeInterval(1),
                    ))
                    prior = Dictionary(
                        samples.map { ($0.id, $0) },
                        uniquingKeysWith: { first, _ in first },
                    )
                } else { prior = [:] }
                var affected = Set(conflicts.map(\.day))
                var changed: [CalendarDay: [LocationSample]] = [:]
                for point in points {
                    guard let old = prior[point.id], let next = point.source.photoAttribution,
                          old.source.photoAttribution?.day != next.day || old.source
                          .photoAttribution?.region != next.region else { continue }
                    affected.insert(next.day)
                    changed[next.day, default: []].append(old)
                }
                let evidence = PhotoHistoryConflicts(
                    manualDays: conflicts,
                    priorPoints: changed
                        .mapValues { $0.sorted { $0.id.uuidString < $1.id.uuidString } },
                    primaryRegions: existingPicks == primary ? [] : existingPicks,
                    affectedDays: affected,
                )
                if let resolution {
                    if resolution.evidence != evidence { return evidence }
                } else if !evidence.isEmpty { return evidence }
                let excluded = affected.subtracting(resolution?.useReviewedDays ?? [])
                for point in points {
                    guard let photo = point.source.photoAttribution,
                          !excluded.contains(photo.day) else { continue }
                    if let old = prior[point.id]?.source.photoAttribution, old.day == photo.day,
                       old.region == photo.region { continue }
                    try await store.add(sample: point)
                }
                for (day, regions) in regionsByDay where !excluded.contains(day) {
                    let old = existing[day]
                    let additions = old?.isAuthoritative == true ? regions : assertions[
                        day,
                        default: [],
                    ]
                    guard !additions.isSubset(of: old?.regions ?? []) else { continue }
                    try await store.setManualDay(DayPresence(
                        day: day,
                        regions: additions.union(old?.regions ?? []),
                        isAuthoritative: old?.isAuthoritative ?? false,
                        audit: old?.audit ?? ManualEntryAudit(
                            recordedAt: approvedAt,
                            note: nil,
                            location: nil,
                        ),
                        photoApprovedAt: approvedAt,
                    ))
                }
                if evidence.primaryRegions.isEmpty || resolution?
                    .useReviewedPicks == true { try await store.setPrimaryRegions(primary) }
                try Task.checkCancellation()
                try await store.addBackupImportReceipt(
                    id: receipt.id,
                    installationID: receipt.installationID,
                )
                return nil
            }
        }
    }
}
