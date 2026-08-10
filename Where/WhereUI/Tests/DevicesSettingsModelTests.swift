import Foundation
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct DevicesSettingsModelTests {
    fileprivate static let currentID = RecordingDeviceID(
        rawValue: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
    )
    private static let remoteID = RecordingDeviceID(
        rawValue: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
    )
    private static let date = Date(timeIntervalSinceReferenceDate: 100)

    @Test func loadsCurrentAndRemoteDeviceRows() async throws {
        let fixture = try await makeFixture()
        let model = DevicesSettingsModel(session: fixture.session)

        await model.retry()

        #expect(model.rows.map(\.id) == [Self.currentID, Self.remoteID])
        #expect(model.rows.first?.isCurrent == true)
    }

    @Test func localToggleChangesOnlyTheCurrentInstallationsPreference() async throws {
        let fixture = try await makeFixture()
        let model = DevicesSettingsModel(session: fixture.session)
        await model.retry()
        let current = try #require(model.rows.first)

        current.isEnabled = false
        await model.recordingPreferenceChanged(for: current)

        let currentConfiguration = try #require(
            try await fixture.session.recordingDevices().first { $0.id == Self.currentID },
        )
        #expect(currentConfiguration.localAutomaticRecordingEnabled == false)
    }

    @Test func remoteDeviceCanBeRenamedAndRemovedButNotToggled() async throws {
        let fixture = try await makeFixture()
        let model = DevicesSettingsModel(session: fixture.session)
        await model.retry()
        let remote = try #require(model.rows.last)

        remote.nickname = "Kitchen iPad"
        await model.saveNickname(remote)
        let renamed = try #require(
            try await fixture.session.recordingDevices().first { $0.id == Self.remoteID },
        )
        #expect(renamed.device.nickname == "Kitchen iPad")

        await model.remove(remote)

        #expect(try await fixture.session.recordingDevices().contains { $0.id == Self.remoteID }
            == false)
        let current = try #require(
            try await fixture.session.recordingDevices().first { $0.id == Self.currentID },
        )
        #expect(current.localAutomaticRecordingEnabled == true)
    }

    @Test func operationFailureRemainsVisibleAfterRefresh() async throws {
        let fixture = try await makeFixture()
        let model = DevicesSettingsModel(session: fixture.session)
        await model.retry()
        let remote = try #require(model.rows.last)
        await fixture.store.failNextRecordingDeviceWrite()

        remote.nickname = "Kitchen iPad"
        await model.saveNickname(remote)

        #expect(model.presentedFailure?.context == .operation(deviceID: Self.remoteID))
    }

    private func makeFixture() async throws -> Fixture {
        let store = try TestStore()
        let context = InstallationRecordingContext(
            currentDevice: CurrentRecordingDevice(
                id: Self.currentID,
                systemName: "iPhone",
                kind: .phone,
            ),
            registeredAt: Self.date,
            recordingChoice: .on(enabledAt: Self.date),
            isRejoining: false,
        )
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(authorizationStatus: .always),
            installationContext: context,
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        _ = try await services.recording.register(authorization: .always)
        let generation = try await store.dataGeneration()
        try await store.perform {
            try await store.addRecordingDeviceProfile(RecordingDeviceProfile(
                id: Self.remoteID,
                systemName: "iPad",
                kind: .tablet,
                registeredAt: Self.date,
                registrationGenerationID: generation.id,
            ))
            try await store.setRecordingDeviceCheckIn(RecordingDeviceCheckIn(
                deviceID: Self.remoteID,
                revision: 0,
                lastSeenAt: Self.date,
                status: .off,
            ))
        }
        return Fixture(
            session: WhereSession(
                services: services,
                preferences: WherePreferences(store: InMemoryKeyValueStore()),
            ),
            store: store,
        )
    }
}

@MainActor
private struct Fixture {
    let session: WhereSession
    let store: TestStore
}
