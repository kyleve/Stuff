import Foundation
import RegionKit

/// Binds transactions to one service lifetime. Reads remain available during session teardown.
public struct CompatibilityScopedStore: WhereStore {
    private let base: any WhereStore
    private let permit: DataAccessPermit

    init(base: any WhereStore, permit: DataAccessPermit) {
        self.base = base
        self.permit = permit
    }

    public func dataCompatibilityRequirements() async throws -> [DataCompatibilityRequirement] {
        try await base.dataCompatibilityRequirements()
    }

    public func addDataCompatibilityRequirement(
        _ requirement: DataCompatibilityRequirement,
    ) async throws {
        try await base.addDataCompatibilityRequirement(requirement)
    }

    public func importedRecordingRecoveryExclusions() async throws -> [RecordingRecoveryExclusion] {
        try await base.importedRecordingRecoveryExclusions()
    }

    public func addRecordingRecoveryExclusion(_ exclusion: RecordingRecoveryExclusion) async throws {
        try await base.addRecordingRecoveryExclusion(exclusion)
    }

    public func recordingAuthorityCommits() async throws -> [RecordingAuthorityCommit] {
        try await base.recordingAuthorityCommits()
    }

    public func addRecordingAuthorityCommit(_ commit: RecordingAuthorityCommit) async throws {
        try await base.addRecordingAuthorityCommit(commit)
    }

    public func perform<T: Sendable>(_ block: @Sendable () async throws -> T) async throws -> T {
        try await permit.withAccess {
            try await base.validateDataAccess()
            return try await base.perform(block)
        }
    }

    public func perform<T: Sendable>(
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

    public func readSnapshot<T: Sendable>(_ block: @Sendable () async throws -> T) async throws
        -> T
    {
        try await base.readSnapshot(block)
    }

    public func changes() -> AsyncStream<Void> {
        base.changes()
    }

    public func remoteChanges() -> AsyncStream<Void> {
        base.remoteChanges()
    }

    public func dataGeneration() async throws -> WhereDataGeneration {
        try await base.dataGeneration()
    }

    public func recordingDeviceResetBarrier(
        for registrationGenerationID: WhereDataGenerationID,
    ) async throws
        -> Date?
    {
        try await base.recordingDeviceResetBarrier(for: registrationGenerationID)
    }

    public func rotateDataGeneration(
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

    public func backupImportReceipt(
        id: UUID,
        installationID: RecordingDeviceID,
    ) async throws -> BackupImportReceipt? {
        try await base.backupImportReceipt(
            id: id,
            installationID: installationID,
        )
    }

    public func addBackupImportReceipt(id: UUID, installationID: RecordingDeviceID) async throws {
        try await base.addBackupImportReceipt(
            id: id,
            installationID: installationID,
        )
    }

    public func removeBackupImportReceipt(
        id: UUID,
        installationID: RecordingDeviceID,
    ) async throws {
        try await base.removeBackupImportReceipt(
            id: id,
            installationID: installationID,
        )
    }

    public func add(sample: LocationSample) async throws {
        try await base.add(sample: sample)
    }

    public func samples(in interval: DateInterval) async throws -> [LocationSample] {
        try await base.samples(in: interval)
    }

    public func allSamples() async throws -> [LocationSample] {
        try await base.allSamples()
    }

    public func sampleAttributionRevisions(for sampleIDs: Set<UUID>) async throws
        -> [SampleAttributionRevision]
    {
        try await base.sampleAttributionRevisions(for: sampleIDs)
    }

    public func allSampleAttributionRevisions() async throws -> [SampleAttributionRevision] {
        try await base.allSampleAttributionRevisions()
    }

    public func addSampleAttributionRevision(_ revision: SampleAttributionRevision) async throws {
        try await base.addSampleAttributionRevision(revision)
    }

    public func recordingDevices() async throws -> [RecordingDevice] {
        try await base.recordingDevices()
    }

    public func recordingDeviceProfiles() async throws -> [RecordingDeviceProfile] {
        try await base.recordingDeviceProfiles()
    }

    public func addRecordingDeviceProfile(_ profile: RecordingDeviceProfile) async throws {
        try await base.addRecordingDeviceProfile(profile)
    }

    public func recordingDeviceMetadataChanges() async throws -> [RecordingDeviceMetadataChange] {
        try await base.recordingDeviceMetadataChanges()
    }

    public func addRecordingDeviceMetadataChange(
        _ change: RecordingDeviceMetadataChange,
    ) async throws {
        try await base.addRecordingDeviceMetadataChange(change)
    }

    public func recordingDeviceCheckIns() async throws -> [RecordingDeviceCheckIn] {
        try await base.recordingDeviceCheckIns()
    }

    public func setRecordingDeviceCheckIn(_ checkIn: RecordingDeviceCheckIn) async throws {
        try await base.setRecordingDeviceCheckIn(checkIn)
    }

    public func recordingDeviceRemovals() async throws -> [RecordingDeviceRemoval] {
        try await base.recordingDeviceRemovals()
    }

    public func addRecordingDeviceRemoval(_ removal: RecordingDeviceRemoval) async throws {
        try await base.addRecordingDeviceRemoval(removal)
    }

    public func write(evidence: Evidence, blob: Data?) async throws {
        try await base.write(evidence: evidence, blob: blob)
    }

    public func evidence(in interval: DateInterval) async throws -> [Evidence] {
        try await base.evidence(in: interval)
    }

    public func allEvidence() async throws -> [Evidence] {
        try await base.allEvidence()
    }

    public func evidenceBlob(for id: UUID) async throws -> Data? {
        try await base.evidenceBlob(for: id)
    }

    public func setManualDay(_ day: DayPresence) async throws {
        try await base.setManualDay(day)
    }

    public func clearManualDay(_ day: CalendarDay) async throws {
        try await base.clearManualDay(day)
    }

    public func manualDays(in dayRange: ClosedRange<CalendarDay>) async throws -> [DayPresence] {
        try await base.manualDays(in: dayRange)
    }

    public func allManualDays() async throws -> [DayPresence] {
        try await base.allManualDays()
    }

    public func clear(
        in interval: DateInterval,
        manualDays dayRange: ClosedRange<CalendarDay>,
    ) async throws {
        try await base.clear(in: interval, manualDays: dayRange)
    }

    public func dismissedIssueIDs() async throws -> Set<DataIssueID> {
        try await base.dismissedIssueIDs()
    }

    public func allDismissedIssues() async throws -> [DismissedIssue] {
        try await base.allDismissedIssues()
    }

    public func plannedStayRecords() async throws -> [PlannedStayRecord] {
        try await base.plannedStayRecords()
    }

    public func replacePlannedStayRecord(with record: PlannedStayRecord) async throws {
        try await base.replacePlannedStayRecord(with: record)
    }

    public func restorePlannedStayRecord(_ record: PlannedStayRecord) async throws {
        try await base.restorePlannedStayRecord(record)
    }

    public func homeRegionRecords() async throws -> [HomeRegionRecord] {
        try await base.homeRegionRecords()
    }

    public func replaceHomeRegionRecord(with record: HomeRegionRecord) async throws {
        try await base.replaceHomeRegionRecord(with: record)
    }

    public func restoreHomeRegionRecord(_ record: HomeRegionRecord) async throws {
        try await base.restoreHomeRegionRecord(record)
    }

    public func setIssueDismissed(_ dismissed: Bool, id: DataIssueID) async throws {
        try await base.setIssueDismissed(dismissed, id: id)
    }

    public func restoreDismissedIssue(_ issue: DismissedIssue) async throws {
        try await base.restoreDismissedIssue(issue)
    }

    public func trackedRegions() async throws -> Set<Region> {
        try await base.trackedRegions()
    }

    public func primaryRegions() async throws -> [PrimaryRegion] {
        try await base.primaryRegions()
    }

    public func setTrackedRegion(_ tracked: Bool, region: Region) async throws {
        try await base.setTrackedRegion(tracked, region: region)
    }

    public func setPrimaryRegions(_ regions: [PrimaryRegion]) async throws {
        try await base.setPrimaryRegions(regions)
    }

    public func requiredDataCompatibilityVersion() async throws -> DataCompatibilityVersion {
        try await base.requiredDataCompatibilityVersion()
    }

    public func validateDataAccess() async throws {
        try await permit.withAccess { try await base.validateDataAccess() }
    }
}
