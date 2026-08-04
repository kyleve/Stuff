import Foundation
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct DeviceSettingsRowModelTests {
    private static let id = RecordingDeviceID(
        rawValue: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
    )
    private static let date = Date(timeIntervalSinceReferenceDate: 100)

    @Test func presentsRemoteDeviceWithoutAnEditableRecordingChoice() {
        let row = DeviceSettingsRowModel(
            configuration: configuration(nickname: "Home iPad", status: .recording),
        )

        #expect(row.displayName == "Home iPad")
        #expect(row.systemImage == "ipad")
        #expect(row.isCurrent == false)
        #expect(row.beginNextOperation() == nil)
    }

    @Test func refreshAppliesLocalChoiceWithoutCreatingAUserCommand() {
        let row = DeviceSettingsRowModel(
            configuration: configuration(status: .recording, isCurrent: true, enabled: true),
        )

        row.update(from: configuration(status: .off, isCurrent: true, enabled: false))

        #expect(row.isEnabled == false)
        #expect(row.beginNextOperation() == nil)
    }

    @Test func explicitLocalToggleCreatesOneRecordingCommand() {
        let row = DeviceSettingsRowModel(
            configuration: configuration(status: .recording, isCurrent: true, enabled: true),
        )

        row.isEnabled = false

        #expect(row.beginNextOperation() == .setRecordingEnabled(false))
    }

    @Test func syncedRefreshDoesNotOverwriteAnUnsavedNickname() {
        let row = DeviceSettingsRowModel(
            configuration: configuration(nickname: "Home", status: .off),
        )
        row.nickname = "Home iPad"

        row.update(from: configuration(nickname: "Synced elsewhere", status: .off))

        #expect(row.nickname == "Home iPad")
        #expect(row.hasUnsavedNickname)
    }

    private func configuration(
        nickname: String? = nil,
        status: RecordingDeviceStatus,
        isCurrent: Bool = false,
        enabled: Bool? = nil,
    ) -> RecordingDeviceConfiguration {
        RecordingDeviceConfiguration(
            device: RecordingDevice(
                id: Self.id,
                systemName: "iPad",
                nickname: nickname,
                kind: .tablet,
                registeredAt: Self.date,
                lastSeenAt: Self.date,
                removedAt: nil,
                status: status,
            ),
            isCurrentDevice: isCurrent,
            localAutomaticRecordingEnabled: enabled,
        )
    }
}
