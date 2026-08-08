import Foundation
import Testing
import WhereCore
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

    @Test func loadsCurrentAndRemoteDeviceRows() async {
        let session = Session(configurations: Self.configurations)
        let model = DevicesSettingsModel(client: session.client)

        await model.run()

        #expect(model.rows.map(\.id) == [Self.currentID, Self.remoteID])
        #expect(model.rows.first?.isCurrent == true)
    }

    @Test func localToggleChangesOnlyTheCurrentInstallationsPreference() async throws {
        let session = Session(configurations: Self.configurations)
        let model = DevicesSettingsModel(client: session.client)
        await model.run()
        let current = try #require(model.rows.first)

        current.isEnabled = false
        await model.recordingPreferenceChanged(for: current)

        #expect(session.recordingChoices == [false])
    }

    @Test func remoteDeviceCanBeRenamedAndRemovedButNotToggled() async throws {
        let session = Session(configurations: Self.configurations)
        let model = DevicesSettingsModel(client: session.client)
        await model.run()
        let remote = try #require(model.rows.last)

        remote.nickname = "Kitchen iPad"
        await model.saveNickname(remote)
        await model.remove(remote)

        #expect(session.renames.map(\.id) == [Self.remoteID])
        #expect(session.renames.map(\.nickname) == ["Kitchen iPad"])
        #expect(session.removals == [Self.remoteID])
        #expect(session.recordingChoices.isEmpty)
    }

    @Test func operationFailureRemainsVisibleAfterRefresh() async throws {
        let session = Session(configurations: Self.configurations)
        session.nextError = TestFailure()
        let model = DevicesSettingsModel(client: session.client)
        await model.run()
        let current = try #require(model.rows.first)

        current.isEnabled = false
        await model.recordingPreferenceChanged(for: current)

        #expect(model.presentedFailure?.context == .operation(deviceID: Self.currentID))
    }

    private static var configurations: [RecordingDeviceConfiguration] {
        [
            configuration(
                id: currentID,
                name: "iPhone",
                kind: .phone,
                status: .recording,
                isCurrent: true,
                enabled: true,
            ),
            configuration(
                id: remoteID,
                name: "iPad",
                kind: .tablet,
                status: .off,
                isCurrent: false,
                enabled: nil,
            ),
        ]
    }

    private static func configuration(
        id: RecordingDeviceID,
        name: String,
        kind: RecordingDeviceKind,
        status: RecordingDeviceStatus,
        isCurrent: Bool,
        enabled: Bool?,
    ) -> RecordingDeviceConfiguration {
        RecordingDeviceConfiguration(
            device: RecordingDevice(
                id: id,
                systemName: name,
                nickname: nil,
                kind: kind,
                registeredAt: date,
                lastSeenAt: date,
                removedAt: nil,
                status: status,
            ),
            isCurrentDevice: isCurrent,
            localAutomaticRecordingEnabled: enabled,
        )
    }
}

private struct TestFailure: Error {}

@MainActor
private final class Session {
    struct Rename: Equatable {
        let id: RecordingDeviceID
        let nickname: String
    }

    var configurations: [RecordingDeviceConfiguration]
    var recordingChoices: [Bool] = []
    var renames: [Rename] = []
    var removals: [RecordingDeviceID] = []
    var nextError: (any Error)?

    init(configurations: [RecordingDeviceConfiguration]) {
        self.configurations = configurations
    }

    var client: DevicesSettingsClient {
        DevicesSettingsClient(
            recordingDeviceUpdates: { [self] in recordingDeviceUpdates() },
            recordingDevices: { [self] in try await recordingDevices() },
            setRecordingEnabled: { [self] in try await setRecordingEnabled($0) },
            renameRecordingDevice: { [self] in
                try await renameRecordingDevice($0, to: $1)
            },
            removeRecordingDevice: { [self] in try await removeRecordingDevice($0) },
            requestPermission: { [self] in await requestPermission() },
        )
    }

    func recordingDeviceUpdates() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    func recordingDevices() async throws -> [RecordingDeviceConfiguration] {
        configurations
    }

    func setRecordingEnabled(_ enabled: Bool) async throws {
        try failIfNeeded()
        recordingChoices.append(enabled)
    }

    func renameRecordingDevice(_ deviceID: RecordingDeviceID, to nickname: String) async throws {
        try failIfNeeded()
        renames.append(.init(id: deviceID, nickname: nickname))
    }

    func removeRecordingDevice(_ deviceID: RecordingDeviceID) async throws {
        try failIfNeeded()
        removals.append(deviceID)
    }

    func requestPermission() async {}

    private func failIfNeeded() throws {
        if let nextError {
            self.nextError = nil
            throw nextError
        }
    }
}
