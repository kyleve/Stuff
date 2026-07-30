import Foundation
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct DeviceSettingsRowModelTests {
    private static let id = RecordingDeviceID(
        rawValue: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
    )
    private static let policyID = UUID(
        uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
    )!
    private static let date = Date(timeIntervalSinceReferenceDate: 100)

    @Test func presentsNicknameKindAndAcknowledgement() {
        let row = DeviceSettingsRowModel(
            configuration: configuration(
                nickname: "Home iPad",
                status: .recording,
                appliedPolicyID: Self.policyID,
            ),
            isCurrent: false,
        )

        #expect(row.displayName == "Home iPad")
        #expect(row.systemImage == "ipad")
        #expect(row.isPending == false)
    }

    @Test func updateKeepsEditableObjectIdentityAndAppliesRemoteState() {
        let row = DeviceSettingsRowModel(
            configuration: configuration(
                nickname: nil,
                status: .recording,
                appliedPolicyID: Self.policyID,
            ),
            isCurrent: false,
        )
        row.update(from: configuration(
            nickname: "Desk",
            status: .off,
            appliedPolicyID: nil,
        ))

        #expect(row.id == Self.id)
        #expect(row.displayName == "Desk")
        #expect(row.confirmedNickname == "Desk")
        #expect(row.status == .off)
        #expect(row.isPending)
        #expect(row.confirmedIsEnabled == false)
    }

    @Test func syncedRefreshDoesNotOverwriteAnUnsavedNickname() {
        let row = DeviceSettingsRowModel(
            configuration: configuration(
                nickname: "Home",
                status: .off,
                appliedPolicyID: Self.policyID,
            ),
            isCurrent: false,
        )
        row.nickname = "Home iPad"

        row.update(from: configuration(
            nickname: "Synced elsewhere",
            status: .off,
            appliedPolicyID: Self.policyID,
        ))

        #expect(row.nickname == "Home iPad")
        #expect(row.confirmedNickname == "Synced elsewhere")
    }

    private func configuration(
        nickname: String?,
        status: RecordingDeviceStatus,
        appliedPolicyID: UUID?,
    ) -> RecordingDeviceConfiguration {
        RecordingDeviceConfiguration(
            device: RecordingDevice(
                id: Self.id,
                systemName: "iPad",
                nickname: nickname,
                kind: .tablet,
                registeredAt: Self.date,
                lastSeenAt: Self.date,
                archivedAt: nil,
                lastAppliedPolicyChangeID: appliedPolicyID,
                status: status,
            ),
            isEnabled: status != .off,
            latestPolicyChangeID: Self.policyID,
        )
    }
}
