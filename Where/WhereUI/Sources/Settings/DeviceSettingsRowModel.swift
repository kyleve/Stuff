import Foundation
import Observation
import WhereCore

/// Editable presentation state for one synced recording device.
@MainActor
@Observable
final class DeviceSettingsRowModel: Identifiable {
    let id: RecordingDeviceID
    let systemName: String
    let kind: RecordingDeviceKind
    let isCurrent: Bool

    var nickname: String
    private(set) var confirmedNickname: String
    var isEnabled: Bool
    private(set) var confirmedIsEnabled: Bool
    var status: RecordingDeviceStatus
    var lastSeenAt: Date
    var isPending: Bool
    var isBusy = false

    init(configuration: RecordingDeviceConfiguration, isCurrent: Bool) {
        id = configuration.id
        systemName = configuration.device.systemName
        kind = configuration.device.kind
        self.isCurrent = isCurrent
        let nickname = configuration.device.nickname ?? ""
        self.nickname = nickname
        confirmedNickname = nickname
        isEnabled = configuration.isEnabled
        confirmedIsEnabled = configuration.isEnabled
        status = configuration.device.status
        lastSeenAt = configuration.device.lastSeenAt
        isPending = configuration.isPending
    }

    var displayName: String {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? systemName : trimmed
    }

    var systemImage: String {
        switch kind {
            case .phone: "iphone"
            case .tablet: "ipad"
            case .other: "apple.logo"
        }
    }

    func update(from configuration: RecordingDeviceConfiguration) {
        let updatedNickname = configuration.device.nickname ?? ""
        if nickname == confirmedNickname {
            nickname = updatedNickname
        }
        confirmedNickname = updatedNickname
        isEnabled = configuration.isEnabled
        confirmedIsEnabled = configuration.isEnabled
        status = configuration.device.status
        lastSeenAt = configuration.device.lastSeenAt
        isPending = configuration.isPending
    }
}
