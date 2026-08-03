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
        #expect(row.status == .off)
        #expect(row.isPending)
        #expect(row.isSyncingRecordingPolicy == false)
        #expect(row.policyPresentationState == .resolved(isAcknowledged: false))
        #expect(row.isEnabled == false)
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
        #expect(row.hasUnsavedNickname)
    }

    @Test func profileWithoutASyncedPolicyStaysUnresolved() {
        let device = configuration(
            nickname: "Home iPad",
            status: .unknown,
            appliedPolicyID: nil,
        ).device
        let row = DeviceSettingsRowModel(
            configuration: RecordingDeviceConfiguration(
                device: device,
                policy: .unknown,
            ),
            isCurrent: false,
        )

        #expect(row.hasResolvedRecordingPolicy == false)
        #expect(row.isPending)
        #expect(row.isSyncingRecordingPolicy)
        #expect(row.policyPresentationState == .syncingPolicy)
        #expect(row.disablesDestructiveActions)

        row.update(from: configuration(
            nickname: "Home iPad",
            status: .off,
            appliedPolicyID: Self.policyID,
        ))

        #expect(row.hasResolvedRecordingPolicy)
        #expect(row.isEnabled == false)
        #expect(row.isPending == false)
        #expect(row.isSyncingRecordingPolicy == false)
        #expect(row.policyPresentationState == .resolved(isAcknowledged: true))
        #expect(row.disablesDestructiveActions == false)
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
            policy: .resolved(ResolvedRecordingPolicy(
                isEnabled: status != .off,
                isArchived: false,
                changeID: Self.policyID,
                isAcknowledged: appliedPolicyID == Self.policyID,
            )),
        )
    }
}
