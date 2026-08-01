import Foundation
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct DevicesSettingsModelTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 1000)

    private func makeSubject() throws -> (
        model: DevicesSettingsModel,
        session: WhereSession,
        store: SwiftDataStore
    ) {
        let store = try SwiftDataStore.inMemory()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(authorizationStatus: .always),
            recordingParticipation: .recording(
                device: .preview,
                defaultEnabledForNewInstallation: true,
            ),
            now: { Self.now },
        )
        let preferences = makePreferences()
        preferences.wantsTracking = true
        let session = WhereSession(services: services, preferences: preferences)
        return (DevicesSettingsModel(session: session), session, store)
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
        await subject.model.setEnabled(false, row: row)

        #expect(row.isEnabled == false)
        #expect(row.status == .off)
        #expect(row.isPending == false)
        #expect(subject.session.isTracking == false)
        #expect(subject.session.preferences.wantsTracking == false)
    }

    @Test func renamesAndArchivesARemoteDevice() async throws {
        let subject = try makeSubject()
        await subject.session.start()
        let remoteID = try RecordingDeviceID(
            rawValue: #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
        )
        try await subject.store.perform {
            try await subject.store.setRecordingDevice(RecordingDevice(
                id: remoteID,
                systemName: "iPad",
                nickname: nil,
                kind: .tablet,
                registeredAt: Self.now,
                lastSeenAt: Self.now,
                archivedAt: nil,
                lastAppliedPolicyChangeID: nil,
                status: .off,
            ))
        }
        await subject.model.retry()
        let remote = try #require(subject.model.rows.first(where: { $0.id == remoteID }))

        remote.nickname = "Home iPad"
        await subject.model.rename(remote)
        #expect(remote.displayName == "Home iPad")
        #expect(try await subject.store.recordingDevices()
            .first(where: { $0.id == remoteID })?.nickname == "Home iPad")

        await subject.model.archive(remote)
        #expect(subject.model.rows.contains(where: { $0.id == remoteID }) == false)
        #expect(try await subject.store.recordingDevices()
            .first(where: { $0.id == remoteID })?.archivedAt == Self.now)
    }

    @Test func repeatedNicknameCommitNormalizesWithoutChangingTheConfirmedName() async throws {
        let subject = try makeSubject()
        await subject.session.start()
        await subject.model.retry()
        let row = try #require(subject.model.rows.first)

        row.nickname = "Pocket"
        await subject.model.rename(row)
        row.nickname = "  Pocket  "
        await subject.model.rename(row)

        #expect(row.nickname == "Pocket")
        #expect(row.confirmedNickname == "Pocket")
        #expect(try await subject.store.recordingDevices()
            .first(where: { $0.id == row.id })?.nickname == "Pocket")
    }
}
