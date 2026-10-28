import Foundation
import RegionKit

/// Binds transactions to one service lifetime. Reads remain available during session teardown.
struct CompatibilityScopedStore: WhereStore {
    let base: any WhereStore
    let permit: DataAccessPermit

    func dataCompatibilityRequirements() async throws -> [DataCompatibilityRequirement] {
        try await base.dataCompatibilityRequirements()
    }

    func addDataCompatibilityRequirement(_ requirement: DataCompatibilityRequirement) async throws {
        try await base.addDataCompatibilityRequirement(requirement)
    }

    func importedRecordingRecoveryExclusions() async throws -> [RecordingRecoveryExclusion] {
        try await base.importedRecordingRecoveryExclusions()
    }

    func addRecordingRecoveryExclusion(_ exclusion: RecordingRecoveryExclusion) async throws {
        try await base.addRecordingRecoveryExclusion(exclusion)
    }

    func recordingAuthorityCommits() async throws -> [RecordingAuthorityCommit] {
        try await base.recordingAuthorityCommits()
    }

    func addRecordingAuthorityCommit(_ commit: RecordingAuthorityCommit) async throws {
        try await base.addRecordingAuthorityCommit(commit)
    }

    func perform<T: Sendable>(_ block: @Sendable () async throws -> T) async throws -> T {
        try await permit.withAccess {
            try await base.validateDataAccess()
            return try await base.perform(block)
        }
    }

    func perform<T: Sendable>(
        expectedDataGenerationID: WhereDataGenerationID,
        _ block: @Sendable () async throws -> T,
    ) async throws -> T {
        try await permit.withAccess {
            try await base.validateDataAccess()
            return try await base.perform(
                expectedDataGenerationID: expectedDataGenerationID,
                block,
            )
        }
    }

    func readSnapshot<T: Sendable>(_ block: @Sendable () async throws -> T) async throws -> T {
        try await base.readSnapshot(block)
    }

    func changes() -> AsyncStream<Void> {
        base.changes()
    }

    func remoteChanges() -> AsyncStream<Void> {
        base.remoteChanges()
    }

    func dataGeneration() async throws -> WhereDataGeneration {
        try await base.dataGeneration()
    }

    func recordingDeviceResetBarrier(
        for registrationGenerationID: WhereDataGenerationID,
    ) async throws
        -> Date?
    {
        try await base.recordingDeviceResetBarrier(for: registrationGenerationID)
    }

    func rotateDataGeneration(
        reason: WhereDataGenerationReason,
        changedBy deviceID: RecordingDeviceID,
        at date: Date,
    ) async throws -> WhereDataGeneration {
        try await base.rotateDataGeneration(
            reason: reason,
            changedBy: deviceID,
            at: date,
        )
    }

    func backupImportReceipt(
        id: UUID,
        installationID: RecordingDeviceID,
    ) async throws -> BackupImportReceipt? {
        try await base.backupImportReceipt(
            id: id,
            installationID: installationID,
        )
    }

    func addBackupImportReceipt(id: UUID, installationID: RecordingDeviceID) async throws {
        try await base.addBackupImportReceipt(
            id: id,
            installationID: installationID,
        )
    }

    func removeBackupImportReceipt(id: UUID, installationID: RecordingDeviceID) async throws {
        try await base.removeBackupImportReceipt(
            id: id,
            installationID: installationID,
        )
    }

    func add(sample: LocationSample) async throws {
        try await base.add(sample: sample)
    }

    func samples(in interval: DateInterval) async throws -> [LocationSample] {
        try await base.samples(in: interval)
    }

    func allSamples() async throws -> [LocationSample] {
        try await base.allSamples()
    }

    func sampleAttributionRevisions(for sampleIDs: Set<UUID>) async throws
        -> [SampleAttributionRevision]
    {
        try await base.sampleAttributionRevisions(for: sampleIDs)
    }

    func allSampleAttributionRevisions() async throws -> [SampleAttributionRevision] {
        try await base.allSampleAttributionRevisions()
    }

    func addSampleAttributionRevision(_ revision: SampleAttributionRevision) async throws {
        try await base.addSampleAttributionRevision(revision)
    }

    func recordingDevices() async throws -> [RecordingDevice] {
        try await base.recordingDevices()
    }

    func recordingDeviceProfiles() async throws -> [RecordingDeviceProfile] {
        try await base.recordingDeviceProfiles()
    }

    func addRecordingDeviceProfile(_ profile: RecordingDeviceProfile) async throws {
        try await base.addRecordingDeviceProfile(profile)
    }

    func recordingDeviceMetadataChanges() async throws -> [RecordingDeviceMetadataChange] {
        try await base.recordingDeviceMetadataChanges()
    }

    func addRecordingDeviceMetadataChange(_ change: RecordingDeviceMetadataChange) async throws {
        try await base.addRecordingDeviceMetadataChange(change)
    }

    func recordingDeviceCheckIns() async throws -> [RecordingDeviceCheckIn] {
        try await base.recordingDeviceCheckIns()
    }

    func setRecordingDeviceCheckIn(_ checkIn: RecordingDeviceCheckIn) async throws {
        try await base.setRecordingDeviceCheckIn(checkIn)
    }

    func recordingDeviceRemovals() async throws -> [RecordingDeviceRemoval] {
        try await base.recordingDeviceRemovals()
    }

    func addRecordingDeviceRemoval(_ removal: RecordingDeviceRemoval) async throws {
        try await base.addRecordingDeviceRemoval(removal)
    }

    func write(evidence: Evidence, blob: Data?) async throws {
        try await base.write(evidence: evidence, blob: blob)
    }

    func evidence(in interval: DateInterval) async throws -> [Evidence] {
        try await base.evidence(in: interval)
    }

    func allEvidence() async throws -> [Evidence] {
        try await base.allEvidence()
    }

    func evidenceBlob(for id: UUID) async throws -> Data? {
        try await base.evidenceBlob(for: id)
    }

    func setManualDay(_ day: DayPresence) async throws {
        try await base.setManualDay(day)
    }

    func clearManualDay(_ day: CalendarDay) async throws {
        try await base.clearManualDay(day)
    }

    func manualDays(in dayRange: ClosedRange<CalendarDay>) async throws -> [DayPresence] {
        try await base.manualDays(in: dayRange)
    }

    func allManualDays() async throws -> [DayPresence] {
        try await base.allManualDays()
    }

    func clear(
        in interval: DateInterval,
        manualDays dayRange: ClosedRange<CalendarDay>,
    ) async throws {
        try await base.clear(in: interval, manualDays: dayRange)
    }

    func dismissedIssueIDs() async throws -> Set<DataIssueID> {
        try await base.dismissedIssueIDs()
    }

    func allDismissedIssues() async throws -> [DismissedIssue] {
        try await base.allDismissedIssues()
    }

    func plannedStayRecords() async throws -> [PlannedStayRecord] {
        try await base.plannedStayRecords()
    }

    func replacePlannedStayRecord(with record: PlannedStayRecord) async throws {
        try await base.replacePlannedStayRecord(with: record)
    }

    func restorePlannedStayRecord(_ record: PlannedStayRecord) async throws {
        try await base.restorePlannedStayRecord(record)
    }

    func homeRegionRecords() async throws -> [HomeRegionRecord] {
        try await base.homeRegionRecords()
    }

    func replaceHomeRegionRecord(with record: HomeRegionRecord) async throws {
        try await base.replaceHomeRegionRecord(with: record)
    }

    func restoreHomeRegionRecord(_ record: HomeRegionRecord) async throws {
        try await base.restoreHomeRegionRecord(record)
    }

    func setIssueDismissed(_ dismissed: Bool, id: DataIssueID) async throws {
        try await base.setIssueDismissed(dismissed, id: id)
    }

    func restoreDismissedIssue(_ issue: DismissedIssue) async throws {
        try await base.restoreDismissedIssue(issue)
    }

    func trackedRegions() async throws -> Set<Region> {
        try await base.trackedRegions()
    }

    func primaryRegions() async throws -> [PrimaryRegion] {
        try await base.primaryRegions()
    }

    func setTrackedRegion(_ tracked: Bool, region: Region) async throws {
        try await base.setTrackedRegion(tracked, region: region)
    }

    func setPrimaryRegions(_ regions: [PrimaryRegion]) async throws {
        try await base.setPrimaryRegions(regions)
    }

    func requiredDataCompatibilityVersion() async throws -> DataCompatibilityVersion {
        try await base.requiredDataCompatibilityVersion()
    }

    func validateDataAccess() async throws {
        try await permit.withAccess { try await base.validateDataAccess() }
    }
}
