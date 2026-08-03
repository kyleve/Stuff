import Foundation
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct DevicesSettingsModelTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 1000)
    private static let disabledInitialPolicyID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000003",
    )!

    @Test func searchFocusWaitsUntilDeviceRowsAreLoaded() {
        #expect(DevicesSettingsModel.LoadState.idle.isReadyForSearchFocus == false)
        #expect(DevicesSettingsModel.LoadState.loading.isReadyForSearchFocus == false)
        #expect(DevicesSettingsModel.LoadState.empty.isReadyForSearchFocus == false)
        #expect(DevicesSettingsModel.LoadState.loaded.isReadyForSearchFocus)
    }

    private func makeSubject() throws -> (
        model: DevicesSettingsModel,
        session: WhereSession,
        store: SwiftDataStore
    ) {
        let store = try SwiftDataStore.inMemory()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(authorizationStatus: .always),
            installationContext: .testing,
            now: { Self.now },
        )
        let preferences = makePreferences()
        let session = WhereSession(services: services, preferences: preferences)
        return (DevicesSettingsModel(session: session), session, store)
    }

    private func makeSubject(
        store: any WhereStore,
        initialRecordingEnabled: Bool = true,
    ) -> (
        model: DevicesSettingsModel,
        session: WhereSession
    ) {
        let installationContext = if initialRecordingEnabled {
            InstallationRecordingContext.testing
        } else {
            InstallationRecordingContext(
                currentDevice: InstallationRecordingContext.testing.currentDevice,
                registeredAt: InstallationRecordingContext.testing.registeredAt,
                initialRecordingChoice: .init(
                    isEnabled: false,
                    assignmentChangeID: Self.disabledInitialPolicyID,
                    confirmedAt: Date(timeIntervalSinceReferenceDate: 1),
                ),
            )
        }
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(authorizationStatus: .always),
            installationContext: installationContext,
            now: { Self.now },
        )
        let preferences = makePreferences()
        let session = WhereSession(services: services, preferences: preferences)
        return (DevicesSettingsModel(session: session), session)
    }

    @Test func loadsTheCurrentDeviceAndAwaitsAToggle() async throws {
        let subject = try makeSubject()
        await subject.session.start()
        await subject.model.retry()
        let row = try #require(subject.model.rows.first)
        #expect(row.isCurrent)
        #expect(row.isEnabled)
        #expect(row.status == .recording)

        row.isEnabled = false
        await subject.model.recordingPreferenceChanged(for: row)

        #expect(row.isEnabled == false)
        #expect(row.status == .off)
        #expect(row.isPending == false)
        #expect(subject.session.isTracking == false)
    }

    @Test func emptyDeviceResultsRemainVisibleAndRetryable() async {
        let session = ScriptedDevicesSettingsSession(hasDevice: false)
        let model = DevicesSettingsModel(session: session)

        await model.retry()

        guard case .empty = model.state else {
            Issue.record("Expected an empty device result to have a visible state.")
            return
        }
        #expect(model.rows.isEmpty)

        session.hasDevice = true
        await model.retry()

        guard case .loaded = model.state else {
            Issue.record("Expected retry to load the now-available device.")
            return
        }
        #expect(model.rows.count == 1)
        #expect(session.recordingDevicesCallCount == 2)
    }

    @Test func refreshFailureAfterACommittedToggleDoesNotFailOrRepeatTheToggle() async throws {
        let session = ScriptedDevicesSettingsSession(isEnabled: false)
        let model = DevicesSettingsModel(session: session)
        await model.retry()
        let row = try #require(model.rows.first)
        session.failRecordingDevicesCall(2)

        row.isEnabled = true
        await model.recordingPreferenceChanged(for: row)

        #expect(session.setEnabledCalls == [true])
        #expect(row.isEnabled)
        #expect(row.isApplyingRecordingChange)
        #expect(model.presentedFailure?.context == .refresh)
        #expect(model.presentedFailureCanRetry)

        await model.retry()

        #expect(session.setEnabledCalls == [true])
        #expect(row.isEnabled)
        #expect(row.operationState == .idle)
        #expect(model.presentedFailure == nil)
    }

    @Test func repeatedRefreshFailureKeepsExistingRowsVisible() async throws {
        let session = ScriptedDevicesSettingsSession()
        let model = DevicesSettingsModel(session: session)
        await model.retry()
        _ = try #require(model.rows.first)
        session.failRecordingDevicesCall(2)
        session.failRecordingDevicesCall(3)

        await model.retry()
        guard case .loaded = model.state else {
            Issue.record("Expected a failed reconciliation to preserve the loaded rows.")
            return
        }
        #expect(model.presentedFailure?.context == .refresh)

        model.isShowingError = false
        await model.retry()

        guard case .loaded = model.state else {
            Issue.record("Expected a repeated failure to preserve the loaded rows.")
            return
        }
        #expect(model.rows.count == 1)
        #expect(model.presentedFailure?.context == .refresh)
    }

    @Test func remoteConflictRefreshDoesNotSubmitAnOffCommand() async {
        let session = ScriptedDevicesSettingsSession()
        let model = DevicesSettingsModel(session: session)
        await model.retry()
        #expect(model.recordingSelection == .off)

        session.simulateRemoteAuthority(.conflict([session.currentRecordingDeviceID]))
        await model.retry()
        #expect(model.recordingSelection == .unresolved)

        // SwiftUI observes the refreshed picker selection after the model applies it. The same
        // callback used for a user gesture must recognize that persisted truth already matches.
        await model.recordingAssignmentChanged()

        #expect(session.setEnabledCalls.isEmpty)
    }

    @Test func explicitPickerSelectionStillSubmitsACommand() async {
        let session = ScriptedDevicesSettingsSession()
        let model = DevicesSettingsModel(session: session)
        await model.retry()

        model.recordingSelection = .device(session.currentRecordingDeviceID)
        await model.recordingAssignmentChanged()

        #expect(session.setEnabledCalls == [true])
    }

    @Test func refreshRetrySubmitsANewerToggleWithoutRepeatingTheCommittedToggle() async throws {
        let session = ScriptedDevicesSettingsSession(isEnabled: false)
        let model = DevicesSettingsModel(session: session)
        await model.retry()
        let row = try #require(model.rows.first)
        session.failRecordingDevicesCall(2)

        row.isEnabled = true
        await model.recordingPreferenceChanged(for: row)
        row.isEnabled = false
        await model.recordingPreferenceChanged(for: row)

        await model.retry()

        #expect(session.setEnabledCalls == [true, false])
        #expect(row.isEnabled == false)
        #expect(row.operationState == .idle)
        #expect(model.presentedFailure == nil)
    }

    @Test func renamesAndArchivesARemoteDevice() async throws {
        let subject = try makeSubject()
        await subject.session.start()
        let remoteID = try RecordingDeviceID(
            rawValue: #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
        )
        let remotePolicyID = try #require(
            UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAB"),
        )
        try await addRemoteDevice(
            to: subject.store,
            id: remoteID,
            nickname: nil,
            policyID: remotePolicyID,
            enabled: false,
            status: .off,
            writerID: subject.session.currentRecordingDeviceID,
        )
        await subject.model.retry()
        let remote = try #require(subject.model.rows.first(where: { $0.id == remoteID }))

        remote.nickname = "Home iPad"
        await subject.model.saveNickname(remote)
        #expect(remote.displayName == "Home iPad")
        #expect(try await subject.store.recordingDevices()
            .first(where: { $0.id == remoteID })?.nickname == "Home iPad")

        await subject.model.archive(remote)
        #expect(subject.model.rows.contains(where: { $0.id == remoteID }) == false)
        #expect(try await subject.store.recordingDevices()
            .first(where: { $0.id == remoteID })?.archivedAt == Self.now)
    }

    @Test func newestToggleWinsWhileTheFirstWriteIsSuspended() async throws {
        let store = try TestStore()
        let subject = makeSubject(store: store, initialRecordingEnabled: false)
        await subject.session.start()
        await subject.model.retry()
        let row = try #require(subject.model.rows.first)
        #expect(row.isEnabled == false)

        await store.gateNextRecordingAssignmentWrite()
        row.isEnabled = true
        let firstWrite = Task {
            await subject.model.recordingPreferenceChanged(for: row)
        }
        await store.awaitRecordingAssignmentWriteGate()
        #expect(row.isApplyingRecordingChange)

        row.isEnabled = false
        let newestIntent = Task {
            await subject.model.recordingPreferenceChanged(for: row)
        }
        await newestIntent.value
        await store.releaseRecordingAssignmentWriteGate()
        await firstWrite.value

        #expect(row.isEnabled == false)
        #expect(row.operationState == .idle)
        #expect(row.isApplyingRecordingChange == false)
        let assignmentChanges = try await store.recordingAssignmentChanges()
        #expect(assignmentChanges.suffix(2).map(\.assignedDeviceID)
            == [subject.session.currentRecordingDeviceID, nil])
    }

    @Test func remoteRefreshWinsWhileANicknameCommandIsSuspended() async throws {
        let session = SuspendedDevicesSettingsSession()
        let model = DevicesSettingsModel(session: session)
        await model.retry()
        let row = try #require(model.rows.first)

        row.nickname = "Local Name"
        let save = Task { await model.saveNickname(row) }
        await session.awaitRename()

        session.simulateRemoteNickname("Cloud Name")
        await model.retry()
        session.releaseRename()
        await save.value

        #expect(row.nickname == "Cloud Name")
        #expect(row.hasUnsavedNickname == false)
        #expect(row.operationState == .idle)
    }

    @Test func failedToggleRestoresConfirmedStateAndSurfacesTheFailure() async throws {
        let store = try TestStore()
        let subject = makeSubject(store: store)
        await subject.session.start()
        await subject.model.retry()
        let row = try #require(subject.model.rows.first)

        await store.failNextRecordingAssignmentWrite()
        row.isEnabled = false
        await subject.model.recordingPreferenceChanged(for: row)

        #expect(row.isEnabled)
        guard case .failed = row.operationState else {
            Issue.record("Expected the row to retain its failed operation state.")
            return
        }
        #expect(subject.model.presentedFailure != nil)

        subject.model.isShowingError = false
        #expect(row.operationState == .idle)
        #expect(subject.model.presentedFailure == nil)
    }

    @Test func failedNicknameSavePreservesTheDraftForAnExplicitRetry() async throws {
        let store = try TestStore()
        let subject = makeSubject(store: store)
        await subject.session.start()
        await subject.model.retry()
        let row = try #require(subject.model.rows.first)

        row.nickname = "Travel Phone"
        await store.failNextRecordingDeviceWrite()
        await subject.model.saveNickname(row)

        #expect(row.nickname == "Travel Phone")
        #expect(row.hasUnsavedNickname)
        #expect(subject.model.presentedFailure != nil)

        subject.model.isShowingError = false
        await subject.model.saveNickname(row)

        #expect(row.nickname == "Travel Phone")
        #expect(row.hasUnsavedNickname == false)
        #expect(try await store.recordingDevices().first?.nickname == "Travel Phone")
    }

    @Test func refreshesADeviceImportedFromAnotherDevice() async throws {
        let remoteChanges = ScriptedStoreRemoteChangeSource()
        let store = try SwiftDataStore.inMemory(remoteChangeSource: remoteChanges)
        let subject = makeSubject(store: store)
        await subject.session.start()

        let runTask = Task { await subject.model.run() }
        await waitUntil {
            subject.model.rows.contains(where: \.isCurrent)
        }

        let remoteID = try RecordingDeviceID(
            rawValue: #require(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")),
        )
        let policyID = try #require(
            UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"),
        )
        try await store.simulateRemoteRecordingImport(
            profiles: [
                RecordingDeviceProfile(
                    id: remoteID,
                    systemName: "iPad",
                    kind: .tablet,
                    registeredAt: Self.now,
                    registrationEpochID: .initial,
                ),
            ],
            metadataChanges: [
                RecordingDeviceMetadataChange(
                    id: #require(
                        UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCD"),
                    ),
                    deviceID: remoteID,
                    revision: 0,
                    changedAt: Self.now,
                    changedByDeviceID: subject.session.currentRecordingDeviceID,
                    nickname: "Home iPad",
                ),
            ],
            checkIns: [
                RecordingDeviceCheckIn(
                    deviceID: remoteID,
                    revision: 0,
                    lastSeenAt: Self.now,
                    appliedAt: Self.now,
                    lastAppliedAssignmentChangeID: policyID,
                    status: .off,
                ),
            ],
            assignmentChanges: [
                RecordingAssignmentChange(
                    id: policyID,
                    parentIDs: [],
                    revision: 0,
                    issuedAt: Self.now,
                    issuedByDeviceID: subject.session.currentRecordingDeviceID,
                    effectiveAt: Self.now,
                    assignedDeviceID: nil,
                    reason: .userCommand,
                ),
            ],
            archives: [],
        )

        // The imported rows alone are intentionally silent: this assertion
        // prevents a normal local `perform` ping from making the test pass.
        #expect(subject.model.rows.contains(where: { $0.id == remoteID }) == false)

        remoteChanges.yield()

        await waitUntil {
            subject.model.rows.contains(where: { $0.id == remoteID })
        }
        runTask.cancel()
        await runTask.value

        let remote = try #require(subject.model.rows.first(where: { $0.id == remoteID }))
        #expect(remote.displayName == "Home iPad")
        #expect(remote.isEnabled == false)
        #expect(remote.status == .off)
        #expect(remote.isPending == false)
    }

    @Test func remoteTargetAcknowledgementClearsThePendingRow() async throws {
        let remoteChanges = ScriptedStoreRemoteChangeSource()
        let store = try SwiftDataStore.inMemory(remoteChangeSource: remoteChanges)
        let subject = makeSubject(store: store)
        await subject.session.start()

        let runTask = Task { await subject.model.run() }
        defer { runTask.cancel() }
        await waitUntil {
            subject.model.rows.contains(where: \.isCurrent)
        }

        let remoteID = try RecordingDeviceID(
            rawValue: #require(UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB")),
        )
        let initialPolicyID = try #require(
            UUID(uuidString: "CDCDCDCD-CDCD-CDCD-CDCD-CDCDCDCDCDCD"),
        )
        try await addRemoteDevice(
            to: store,
            id: remoteID,
            nickname: "Travel iPad",
            policyID: initialPolicyID,
            enabled: true,
            status: .recording,
            writerID: remoteID,
        )
        await waitUntil {
            subject.model.rows.contains(where: { $0.id == remoteID })
        }
        let remote = try #require(subject.model.rows.first(where: { $0.id == remoteID }))

        #expect(remote.isEnabled)
        #expect(remote.isPending)
        #expect(remote.status == .recording)
        let assignmentID = try #require(try await store.recordingAssignmentChanges().last?.id)

        try await store.simulateRemoteRecordingImport(
            profiles: [],
            metadataChanges: [],
            checkIns: [RecordingDeviceCheckIn(
                deviceID: remoteID,
                revision: 1,
                lastSeenAt: Self.now.addingTimeInterval(60),
                appliedAt: Self.now.addingTimeInterval(60),
                lastAppliedAssignmentChangeID: assignmentID,
                status: .recording,
            )],
            assignmentChanges: [],
            archives: [],
        )
        #expect(remote.isPending)

        remoteChanges.yield()

        await waitUntil {
            remote.isPending == false && remote.status == .recording
        }
        #expect(remote.isEnabled)
        #expect(remote.isPending == false)
        #expect(remote.status == .recording)
        runTask.cancel()
        await runTask.value
    }

    @Test func observesADeviceAddedDuringInitialLoad() async throws {
        let store = try TestStore()
        let subject = makeSubject(store: store)
        await subject.session.start()
        await store.gateRecordingDevices(afterCalls: 0)

        let runTask = Task { await subject.model.run() }
        await store.awaitRecordingDevicesGate()

        let remoteID = try RecordingDeviceID(
            rawValue: #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")),
        )
        let remotePolicyID = try #require(
            UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBC"),
        )
        try await addRemoteDevice(
            to: store,
            id: remoteID,
            nickname: nil,
            policyID: remotePolicyID,
            enabled: false,
            status: .off,
            writerID: subject.session.currentRecordingDeviceID,
        )
        await store.releaseRecordingDevicesGate()

        await waitUntil {
            subject.model.rows.contains(where: { $0.id == remoteID })
        }
        runTask.cancel()
        await runTask.value

        #expect(subject.model.rows.contains(where: { $0.id == remoteID }))
    }

    private func addRemoteDevice(
        to store: any WhereStore,
        id: RecordingDeviceID,
        nickname: String?,
        policyID: UUID,
        enabled: Bool,
        status: RecordingDeviceStatus,
        writerID: RecordingDeviceID,
    ) async throws {
        let profile = RecordingDeviceProfile(
            id: id,
            systemName: "iPad",
            kind: .tablet,
            registeredAt: Self.now,
            registrationEpochID: .initial,
        )
        let metadata = nickname.map {
            RecordingDeviceMetadataChange(
                id: UUID(),
                deviceID: id,
                revision: 0,
                changedAt: Self.now,
                changedByDeviceID: writerID,
                nickname: $0,
            )
        }
        let assignment = try await RecordingAssignmentChange.appendingCommand(
            to: store.recordingAssignmentChanges(),
            assignment: enabled ? .device(id) : .off,
            issuedAt: Self.now,
            issuedByDeviceID: writerID,
            effectiveAt: Self.now,
            reason: .userCommand,
        )
        let checkIn = RecordingDeviceCheckIn(
            deviceID: id,
            revision: 0,
            lastSeenAt: Self.now,
            appliedAt: Self.now,
            lastAppliedAssignmentChangeID: policyID,
            status: status,
        )
        try await store.perform {
            try await store.addRecordingDeviceProfile(profile)
            if let metadata {
                try await store.addRecordingDeviceMetadataChange(metadata)
            }
            try await store.addRecordingAssignmentChange(assignment)
            try await store.setRecordingDeviceCheckIn(checkIn)
        }
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ predicate: () -> Bool,
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(predicate(), "condition was not met before timeout")
    }
}

/// Deterministic command-vs-refresh race for the Settings session protocol. The command first
/// commits a local value, then suspends while a causally later remote value becomes readable.
@MainActor
private final class SuspendedDevicesSettingsSession: DevicesSettingsSession {
    let currentRecordingDeviceID = CurrentRecordingDevice.preview.id

    private let policyID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
    private var nickname = "iPhone"
    private var renameReached = false
    private var renameArrival: CheckedContinuation<Void, Never>?
    private var renameGate: CheckedContinuation<Void, Never>?

    func recordingDeviceUpdates() -> AsyncStream<Void> {
        AsyncStream { _ in }
    }

    func recordingDevices() async throws -> [RecordingDeviceConfiguration] {
        [configuration]
    }

    func setRecordingEnabled(_: Bool, for _: RecordingDeviceID) async throws {}

    func renameRecordingDevice(_: RecordingDeviceID, to nickname: String) async throws {
        self.nickname = nickname
        renameReached = true
        renameArrival?.resume()
        renameArrival = nil
        await withCheckedContinuation { renameGate = $0 }
    }

    func archiveRecordingDevice(_: RecordingDeviceID) async throws {}
    func requestPermission() async {}

    func awaitRename() async {
        guard !renameReached else { return }
        await withCheckedContinuation { renameArrival = $0 }
    }

    func simulateRemoteNickname(_ nickname: String) {
        self.nickname = nickname
    }

    func releaseRename() {
        renameGate?.resume()
        renameGate = nil
    }

    private var configuration: RecordingDeviceConfiguration {
        RecordingDeviceConfiguration(
            device: RecordingDevice(
                id: currentRecordingDeviceID,
                systemName: "iPhone",
                nickname: nickname,
                kind: .phone,
                registeredAt: Date(timeIntervalSinceReferenceDate: 1000),
                lastSeenAt: Date(timeIntervalSinceReferenceDate: 1000),
                archivedAt: nil,
                lastAppliedAssignmentChangeID: policyID,
                status: .recording,
            ),
            assignmentResolution: .resolved(.device(currentRecordingDeviceID)),
            assignmentFrontierID: policyID,
            isAssignmentAcknowledged: true,
            isArchived: false,
        )
    }
}

@MainActor
private final class ScriptedDevicesSettingsSession: DevicesSettingsSession {
    enum ReadError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Device refresh unavailable"
        }
    }

    let currentRecordingDeviceID = CurrentRecordingDevice.preview.id
    var hasDevice: Bool
    private(set) var recordingDevicesCallCount = 0
    private(set) var setEnabledCalls: [Bool] = []

    private let policyID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
    private var isEnabled: Bool
    private var authorityOverride: RecordingAssignmentResolution?
    private var failingRecordingDevicesCalls: Set<Int> = []

    init(hasDevice: Bool = true, isEnabled: Bool = false) {
        self.hasDevice = hasDevice
        self.isEnabled = isEnabled
    }

    func recordingDeviceUpdates() -> AsyncStream<Void> {
        AsyncStream { _ in }
    }

    func recordingDevices() async throws -> [RecordingDeviceConfiguration] {
        recordingDevicesCallCount += 1
        if failingRecordingDevicesCalls.remove(recordingDevicesCallCount) != nil {
            throw ReadError.unavailable
        }
        return hasDevice ? [configuration] : []
    }

    func recordingAuthoritySnapshot() async throws -> RecordingAuthoritySnapshot {
        RecordingAuthoritySnapshot(
            resolution: authorityOverride ?? configuration.assignmentResolution,
            devices: hasDevice ? [configuration.device] : [],
            archivedDeviceIDs: [],
        )
    }

    func setRecordingEnabled(_ enabled: Bool, for _: RecordingDeviceID) async throws {
        setEnabledCalls.append(enabled)
        isEnabled = enabled
    }

    func renameRecordingDevice(_: RecordingDeviceID, to _: String) async throws {}
    func archiveRecordingDevice(_: RecordingDeviceID) async throws {}
    func requestPermission() async {}

    func failRecordingDevicesCall(_ call: Int) {
        failingRecordingDevicesCalls.insert(call)
    }

    func simulateRemoteAuthority(_ resolution: RecordingAssignmentResolution) {
        authorityOverride = resolution
    }

    private var configuration: RecordingDeviceConfiguration {
        RecordingDeviceConfiguration(
            device: RecordingDevice(
                id: currentRecordingDeviceID,
                systemName: "iPhone",
                nickname: nil,
                kind: .phone,
                registeredAt: Date(timeIntervalSinceReferenceDate: 1000),
                lastSeenAt: Date(timeIntervalSinceReferenceDate: 1000),
                archivedAt: nil,
                lastAppliedAssignmentChangeID: policyID,
                status: isEnabled ? .recording : .off,
            ),
            assignmentResolution: .resolved(
                isEnabled ? .device(currentRecordingDeviceID) : .off,
            ),
            assignmentFrontierID: policyID,
            isAssignmentAcknowledged: true,
            isArchived: false,
        )
    }
}
