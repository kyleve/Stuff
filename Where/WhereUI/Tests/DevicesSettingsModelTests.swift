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
            currentDevice: .preview,
            now: { Self.now },
        )
        let preferences = makePreferences()
        preferences.wantsTracking = true
        let session = WhereSession(services: services, preferences: preferences)
        return (DevicesSettingsModel(session: session), session, store)
    }

    private func makeSubject(store: any WhereStore) -> (
        model: DevicesSettingsModel,
        session: WhereSession
    ) {
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(authorizationStatus: .always),
            currentDevice: .preview,
            now: { Self.now },
        )
        let preferences = makePreferences()
        preferences.wantsTracking = true
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

    @Test func observesADeviceAddedDuringInitialLoad() async throws {
        let store = try TestStore()
        let subject = makeSubject(store: store)
        await subject.session.start()
        await store.gateRecordingDevices(afterCalls: 1)

        let runTask = Task { await subject.model.run() }
        await store.awaitRecordingDevicesGate()

        let remoteID = try RecordingDeviceID(
            rawValue: #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")),
        )
        try await store.perform {
            try await store.setRecordingDevice(RecordingDevice(
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
        await store.releaseRecordingDevicesGate()

        await waitUntil {
            subject.model.rows.contains(where: { $0.id == remoteID })
        }
        runTask.cancel()
        await runTask.value

        #expect(subject.model.rows.contains(where: { $0.id == remoteID }))
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
