import Foundation
import Observation
import WhereCore

/// Editable presentation state for one synced recording device.
@MainActor
@Observable
final class DeviceSettingsRowModel: Identifiable {
    enum Operation: Equatable {
        case setRecordingEnabled(Bool)
        case rename(String)
        case remove
    }

    struct OperationFailure: Identifiable, Equatable {
        let id = UUID()
        let operation: Operation
        let message: String
    }

    enum OperationState: Equatable {
        case idle
        case saving(Operation)
        case failed(OperationFailure)
    }

    let id: RecordingDeviceID
    let systemName: String
    let kind: RecordingDeviceKind
    let isCurrent: Bool

    private var confirmedNickname: String
    private var confirmedRecordingEnabled: Bool?
    private var recordingEnabled: Bool
    private var pendingRecordingIntent = false
    private var wantsNicknameSave = false
    private var wantsRemoval = false

    var nickname: String
    private(set) var operationState: OperationState = .idle
    private(set) var status: RecordingDeviceStatus
    private(set) var lastSeenAt: Date

    init(configuration: RecordingDeviceConfiguration) {
        id = configuration.id
        systemName = configuration.device.systemName
        kind = configuration.device.kind
        isCurrent = configuration.isCurrentDevice
        let nickname = configuration.device.nickname ?? ""
        self.nickname = nickname
        confirmedNickname = nickname
        confirmedRecordingEnabled = configuration.localAutomaticRecordingEnabled
        recordingEnabled = configuration.localAutomaticRecordingEnabled ?? false
        status = configuration.device.status
        lastSeenAt = configuration.device.lastSeenAt
    }

    var isEnabled: Bool {
        get { recordingEnabled }
        set {
            guard isCurrent, recordingEnabled != newValue else { return }
            recordingEnabled = newValue
            pendingRecordingIntent = true
            clearFailure(matching: .setRecordingEnabled(newValue))
        }
    }

    var hasUnsavedNickname: Bool {
        normalizedNickname != confirmedNickname
    }

    var canSaveNickname: Bool {
        hasUnsavedNickname && !isSaving
    }

    var isSaving: Bool {
        if case .saving = operationState { true } else { false }
    }

    var displayName: String {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? systemName : trimmed
    }

    var systemImage: String {
        kind.systemImage
    }

    func requestNicknameSave() {
        wantsNicknameSave = true
    }

    func requestRemoval() {
        precondition(!isCurrent, "The current device cannot remove itself.")
        wantsRemoval = true
    }

    func beginNextOperation() -> Operation? {
        guard !isSaving else { return nil }
        if wantsRemoval {
            wantsRemoval = false
            return begin(.remove)
        }
        if pendingRecordingIntent {
            pendingRecordingIntent = false
            return begin(.setRecordingEnabled(recordingEnabled))
        }
        if wantsNicknameSave, hasUnsavedNickname {
            wantsNicknameSave = false
            return begin(.rename(normalizedNickname))
        }
        wantsNicknameSave = false
        return nil
    }

    func finish(_ operation: Operation) {
        switch operation {
            case let .setRecordingEnabled(enabled):
                confirmedRecordingEnabled = enabled
            case let .rename(nickname):
                confirmedNickname = nickname
            case .remove:
                break
        }
        operationState = .idle
    }

    func fail(_ operation: Operation, error: any Error) -> OperationFailure {
        let failure = OperationFailure(operation: operation, message: error.localizedDescription)
        operationState = .failed(failure)
        return failure
    }

    func update(from configuration: RecordingDeviceConfiguration) {
        let newNickname = configuration.device.nickname ?? ""
        if !hasUnsavedNickname { nickname = newNickname }
        confirmedNickname = newNickname
        if let enabled = configuration.localAutomaticRecordingEnabled {
            if !pendingRecordingIntent { recordingEnabled = enabled }
            confirmedRecordingEnabled = enabled
        }
        status = configuration.device.status
        lastSeenAt = configuration.device.lastSeenAt
    }

    private var normalizedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func begin(_ operation: Operation) -> Operation {
        operationState = .saving(operation)
        return operation
    }

    private func clearFailure(matching operation: Operation) {
        guard case let .failed(failure) = operationState else { return }
        switch (failure.operation, operation) {
            case (.setRecordingEnabled, .setRecordingEnabled), (.rename, .rename):
                operationState = .idle
            case (.remove, _), (.setRecordingEnabled, _), (.rename, _):
                break
        }
    }
}

extension RecordingDeviceKind {
    var systemImage: String {
        switch self {
            case .phone: "iphone"
            case .tablet: "ipad"
            case .other: "apple.logo"
        }
    }
}
