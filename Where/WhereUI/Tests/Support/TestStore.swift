import Foundation
import WhereCore

/// Thrown by `TestStore.setManualDay` when failure injection is enabled.
struct ManualSaveFailure: Error, Equatable {}

/// Thrown by `TestStore.samples(in:)` when failure injection is enabled, so a
/// year-report load can be forced to fail.
struct SampleReadFailure: Error, Equatable {}

/// Thrown by the Devices settings save-failure hooks below.
struct RecordingDeviceSaveFailure: Error, Equatable {}

/// Test `WhereStore` that forwards to an in-memory `SwiftDataStore` but adds
/// hooks the view-model tests need:
///
/// - `enableFirstSamplesGate()` suspends the first `samples(in:)` call until
///   the test releases it, so two `refresh()`es can be forced to complete out
///   of order (the stale-year race).
/// - `gateRecordingDevices(afterCalls:)` suspends a selected device read after
///   capturing its result, so a committed change can race an initial load.
/// - `failNextRecordingDeviceWrite()` makes one Devices save fail without
///   contaminating later retry assertions.
/// - `failManualDays()` makes `setManualDay` throw, so manual-entry error
///   handling is exercisable without a real persistence fault.
///
/// Everything else forwards to the backing store so reads stay deterministic.
actor TestStore: WhereStore {
    private let backing: SwiftDataStore

    private var gateFirstSamplesCall = false
    private var firstSamplesSeen = false
    private var gate: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?

    private var recordingDeviceCallsBeforeGate: Int?
    private var recordingDevicesGateReached = false
    private var recordingDevicesGate: CheckedContinuation<Void, Never>?
    private var recordingDevicesArrival: CheckedContinuation<Void, Never>?

    private var shouldFailManualDay = false
    private var shouldFailSamples = false
    private var shouldFailNextRecordingDeviceWrite = false

    init() throws {
        backing = try SwiftDataStore.inMemory()
    }

    // MARK: - Test controls

    func enableFirstSamplesGate() {
        gateFirstSamplesCall = true
    }

    /// Suspends until the gated first `samples(in:)` call has arrived.
    func awaitFirstSamplesCall() async {
        guard !firstSamplesSeen else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func releaseFirstSamplesCall() {
        gate?.resume()
        gate = nil
    }

    /// Gates the device read after `calls` earlier reads have completed.
    func gateRecordingDevices(afterCalls calls: Int) {
        precondition(calls >= 0)
        recordingDeviceCallsBeforeGate = calls
        recordingDevicesGateReached = false
    }

    func awaitRecordingDevicesGate() async {
        guard !recordingDevicesGateReached else { return }
        await withCheckedContinuation { recordingDevicesArrival = $0 }
    }

    func releaseRecordingDevicesGate() {
        recordingDevicesGate?.resume()
        recordingDevicesGate = nil
    }

    func failNextRecordingDeviceWrite() {
        shouldFailNextRecordingDeviceWrite = true
    }

    func failManualDays() {
        shouldFailManualDay = true
    }

    /// Makes `samples(in:)` throw, so a `refresh()`'s year-report load fails and
    /// the model's `.failed` load state is exercisable.
    func failSamples() {
        shouldFailSamples = true
    }

    // MARK: - WhereStore

    func perform<T: Sendable>(_ block: @Sendable () async throws -> T) async throws -> T {
        try await backing.perform(block)
    }

    nonisolated func changes() -> AsyncStream<Void> {
        backing.changes()
    }

    func dataEpoch() async throws -> WhereDataEpoch {
        try await backing.dataEpoch()
    }

    func rotateDataEpoch(
        reason: WhereDataEpochReason,
        changedBy deviceID: RecordingDeviceID,
        at date: Date,
    ) async throws -> WhereDataEpoch {
        try await backing.rotateDataEpoch(reason: reason, changedBy: deviceID, at: date)
    }

    func backupImportReceipt(
        id: UUID,
        installationID: RecordingDeviceID,
    ) async throws -> BackupImportReceipt? {
        try await backing.backupImportReceipt(id: id, installationID: installationID)
    }

    func addBackupImportReceipt(
        id: UUID,
        installationID: RecordingDeviceID,
    ) async throws {
        try await backing.addBackupImportReceipt(id: id, installationID: installationID)
    }

    func removeBackupImportReceipt(
        id: UUID,
        installationID: RecordingDeviceID,
    ) async throws {
        try await backing.removeBackupImportReceipt(id: id, installationID: installationID)
    }

    func add(sample: LocationSample) async throws {
        try await backing.add(sample: sample)
    }

    func samples(in interval: DateInterval) async throws -> [LocationSample] {
        if shouldFailSamples { throw SampleReadFailure() }
        if gateFirstSamplesCall, !firstSamplesSeen {
            firstSamplesSeen = true
            arrival?.resume()
            arrival = nil
            await withCheckedContinuation { gate = $0 }
        }
        return try await backing.samples(in: interval)
    }

    func allSamples() async throws -> [LocationSample] {
        try await backing.allSamples()
    }

    func recordingDevices() async throws -> [RecordingDevice] {
        let devices = try await backing.recordingDevices()
        guard let calls = recordingDeviceCallsBeforeGate else { return devices }
        guard calls == 0 else {
            recordingDeviceCallsBeforeGate = calls - 1
            return devices
        }

        recordingDeviceCallsBeforeGate = nil
        recordingDevicesGateReached = true
        recordingDevicesArrival?.resume()
        recordingDevicesArrival = nil
        await withCheckedContinuation { recordingDevicesGate = $0 }
        return devices
    }

    func recordingDeviceProfiles() async throws -> [RecordingDeviceProfile] {
        try await backing.recordingDeviceProfiles()
    }

    func addRecordingDeviceProfile(_ profile: RecordingDeviceProfile) async throws {
        try await backing.addRecordingDeviceProfile(profile)
    }

    func recordingDeviceMetadataChanges() async throws -> [RecordingDeviceMetadataChange] {
        try await backing.recordingDeviceMetadataChanges()
    }

    func addRecordingDeviceMetadataChange(
        _ change: RecordingDeviceMetadataChange,
    ) async throws {
        if shouldFailNextRecordingDeviceWrite {
            shouldFailNextRecordingDeviceWrite = false
            throw RecordingDeviceSaveFailure()
        }
        try await backing.addRecordingDeviceMetadataChange(change)
    }

    func recordingDeviceCheckIns() async throws -> [RecordingDeviceCheckIn] {
        try await backing.recordingDeviceCheckIns()
    }

    func setRecordingDeviceCheckIn(_ checkIn: RecordingDeviceCheckIn) async throws {
        try await backing.setRecordingDeviceCheckIn(checkIn)
    }

    func recordingDeviceRemovals() async throws -> [RecordingDeviceRemoval] {
        try await backing.recordingDeviceRemovals()
    }

    func addRecordingDeviceRemoval(_ archive: RecordingDeviceRemoval) async throws {
        try await backing.addRecordingDeviceRemoval(archive)
    }

    func write(evidence: Evidence, blob: Data?) async throws {
        try await backing.write(evidence: evidence, blob: blob)
    }

    func evidence(in interval: DateInterval) async throws -> [Evidence] {
        try await backing.evidence(in: interval)
    }

    func allEvidence() async throws -> [Evidence] {
        try await backing.allEvidence()
    }

    func evidenceBlob(for id: UUID) async throws -> Data? {
        try await backing.evidenceBlob(for: id)
    }

    func setManualDay(_ day: DayPresence) async throws {
        if shouldFailManualDay { throw ManualSaveFailure() }
        try await backing.setManualDay(day)
    }

    func clearManualDay(_ day: CalendarDay) async throws {
        try await backing.clearManualDay(day)
    }

    func manualDays(in dayRange: ClosedRange<CalendarDay>) async throws -> [DayPresence] {
        try await backing.manualDays(in: dayRange)
    }

    func allManualDays() async throws -> [DayPresence] {
        try await backing.allManualDays()
    }

    func clear(
        in interval: DateInterval,
        manualDays dayRange: ClosedRange<CalendarDay>,
    ) async throws {
        try await backing.clear(in: interval, manualDays: dayRange)
    }

    func dismissedIssueIDs() async throws -> Set<DataIssueID> {
        try await backing.dismissedIssueIDs()
    }

    func allDismissedIssues() async throws -> [DismissedIssue] {
        try await backing.allDismissedIssues()
    }

    func setIssueDismissed(_ dismissed: Bool, id: DataIssueID) async throws {
        try await backing.setIssueDismissed(dismissed, id: id)
    }

    func restoreDismissedIssue(_ issue: DismissedIssue) async throws {
        try await backing.restoreDismissedIssue(issue)
    }
}
