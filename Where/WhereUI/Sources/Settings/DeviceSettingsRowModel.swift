import Foundation
import Observation
import WhereCore

/// Editable presentation state for one synced recording device.
@MainActor
@Observable
final class DeviceSettingsRowModel: Identifiable {
    /// Why the desired recording setting is not yet settled. A missing policy
    /// is still arriving through CloudKit; a resolved policy can instead be
    /// waiting for its target installation to acknowledge it.
    enum PolicyPresentationState: Equatable {
        case syncingPolicy
        case resolved(isAcknowledged: Bool)
    }

    struct EditableValues: Equatable {
        var nickname: String
        var isEnabled: Bool?
    }

    enum Operation: Equatable {
        case setRecordingEnabled(Bool)
        case rename(String)
        case archive
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

    private enum PendingAction: Hashable {
        case saveNickname
        case archive
    }

    let id: RecordingDeviceID
    let systemName: String
    let kind: RecordingDeviceKind
    let isCurrent: Bool

    private var confirmedValues: EditableValues
    private var draftValues: EditableValues
    private var pendingActions: Set<PendingAction> = []
    private(set) var operationState: OperationState = .idle
    private(set) var status: RecordingDeviceStatus
    private(set) var lastSeenAt: Date
    private(set) var policyPresentationState: PolicyPresentationState

    init(configuration: RecordingDeviceConfiguration, isCurrent: Bool) {
        id = configuration.id
        systemName = configuration.device.systemName
        kind = configuration.device.kind
        self.isCurrent = isCurrent
        let nickname = configuration.device.nickname ?? ""
        let editableValues = EditableValues(
            nickname: nickname,
            isEnabled: configuration.isEnabled,
        )
        confirmedValues = editableValues
        draftValues = editableValues
        status = configuration.device.status
        lastSeenAt = configuration.device.lastSeenAt
        policyPresentationState = Self.policyPresentationState(for: configuration.policy)
    }

    var nickname: String {
        get { draftValues.nickname }
        set {
            guard draftValues.nickname != newValue else { return }
            draftValues.nickname = newValue
            clearFailure(for: .rename(newValue))
        }
    }

    var isEnabled: Bool {
        get { draftValues.isEnabled ?? false }
        set {
            guard draftValues.isEnabled != nil else {
                assertionFailure("An unresolved recording policy cannot be edited.")
                return
            }
            guard draftValues.isEnabled != newValue else { return }
            draftValues.isEnabled = newValue
            clearFailure(for: .setRecordingEnabled(newValue))
        }
    }

    var hasResolvedRecordingPolicy: Bool {
        draftValues.isEnabled != nil
    }

    var isSyncingRecordingPolicy: Bool {
        if case .syncingPolicy = policyPresentationState { true } else { false }
    }

    var isPending: Bool {
        switch policyPresentationState {
            case .syncingPolicy: true
            case let .resolved(isAcknowledged): !isAcknowledged
        }
    }

    var hasUnsavedNickname: Bool {
        normalizedNickname != confirmedValues.nickname
    }

    var canSaveNickname: Bool {
        guard hasUnsavedNickname else { return false }
        return switch operationState {
            case .saving: false
            case .idle, .failed: true
        }
    }

    var disablesRecordingControl: Bool {
        switch operationState {
            case .saving(.rename), .saving(.archive): true
            case .idle, .saving(.setRecordingEnabled), .failed: false
        }
    }

    var disablesNicknameControl: Bool {
        if case .saving = operationState { true } else { false }
    }

    var disablesDestructiveActions: Bool {
        guard hasResolvedRecordingPolicy else { return true }
        return if case .saving = operationState { true } else { false }
    }

    var isApplyingRecordingChange: Bool {
        operationState.isSavingRecording
    }

    var displayName: String {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? systemName : trimmed
    }

    var systemImage: String {
        kind.systemImage
    }

    /// Marks the current nickname draft as an explicit save request. Typing
    /// alone never writes, while a request made during another save is retained
    /// and processed when that operation finishes.
    func requestNicknameSave() {
        pendingActions.insert(.saveNickname)
    }

    func requestArchive() {
        pendingActions.insert(.archive)
    }

    /// Claims the next accepted intent for the owning model's single writer
    /// loop. Recording uses the live draft, so a second toggle made while the
    /// first write is suspended becomes the next operation instead of being
    /// discarded by a busy guard.
    func beginNextOperation() -> Operation? {
        if case .saving = operationState { return nil }

        if pendingActions.remove(.archive) != nil {
            return begin(.archive)
        }

        if let desiredEnabled = draftValues.isEnabled,
           desiredEnabled != confirmedValues.isEnabled
        {
            return begin(.setRecordingEnabled(desiredEnabled))
        }

        if pendingActions.remove(.saveNickname) != nil {
            let nickname = normalizedNickname
            guard nickname != confirmedValues.nickname else {
                draftValues.nickname = confirmedValues.nickname
                operationState = .idle
                return nil
            }
            return begin(.rename(nickname))
        }

        operationState = .idle
        return nil
    }

    func finish(_ operation: Operation) {
        guard operationState == .saving(operation) else {
            assertionFailure("Finished a device operation that was not active.")
            return
        }
        if case let .rename(savedNickname) = operation,
           normalizedNickname == savedNickname
        {
            draftValues.nickname = confirmedValues.nickname
        }
        operationState = .idle
    }

    func fail(_ operation: Operation, error: any Error) -> OperationFailure {
        guard operationState == .saving(operation) else {
            assertionFailure("Failed a device operation that was not active.")
            return OperationFailure(
                operation: operation,
                message: error.localizedDescription,
            )
        }

        switch operation {
            case .setRecordingEnabled:
                // A failed toggle must display the last confirmed value rather
                // than leave an optimistic value looking successfully saved.
                draftValues.isEnabled = confirmedValues.isEnabled
            case .rename:
                // Preserve the draft so the explicit Save button is a reliable
                // retry path and a failed write never destroys user input.
                break
            case .archive:
                break
        }

        let failure = OperationFailure(
            operation: operation,
            message: error.localizedDescription,
        )
        operationState = .failed(failure)
        return failure
    }

    func dismiss(_ failure: OperationFailure) {
        guard operationState == .failed(failure) else { return }
        operationState = .idle
    }

    func update(from configuration: RecordingDeviceConfiguration) {
        let previousConfirmedValues = confirmedValues
        let updatedNickname = configuration.device.nickname ?? ""
        let updatedValues = EditableValues(
            nickname: updatedNickname,
            isEnabled: configuration.isEnabled,
        )

        let preservesNicknameDraft = draftValues.nickname != previousConfirmedValues.nickname
            || operationState.isSavingNickname
        let preservesRecordingDraft = draftValues.isEnabled != previousConfirmedValues.isEnabled
            || operationState.isSavingRecording
        confirmedValues = updatedValues
        if !preservesNicknameDraft {
            draftValues.nickname = updatedValues.nickname
        }
        if !preservesRecordingDraft {
            draftValues.isEnabled = updatedValues.isEnabled
        }
        status = configuration.device.status
        lastSeenAt = configuration.device.lastSeenAt
        policyPresentationState = Self.policyPresentationState(for: configuration.policy)
    }

    private var normalizedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func begin(_ operation: Operation) -> Operation {
        operationState = .saving(operation)
        return operation
    }

    private func clearFailure(for operation: Operation) {
        guard case let .failed(failure) = operationState else { return }
        switch (failure.operation, operation) {
            case (.setRecordingEnabled, .setRecordingEnabled), (.rename, .rename):
                operationState = .idle
            case (.archive, _), (.setRecordingEnabled, _), (.rename, _):
                break
        }
    }

    private static func policyPresentationState(
        for resolution: RecordingPolicyResolution,
    ) -> PolicyPresentationState {
        switch resolution {
            case .unknown:
                .syncingPolicy
            case let .resolved(policy):
                .resolved(isAcknowledged: policy.isAcknowledged)
        }
    }
}

extension DeviceSettingsRowModel.OperationState {
    fileprivate var isSavingNickname: Bool {
        if case .saving(.rename) = self { true } else { false }
    }

    fileprivate var isSavingRecording: Bool {
        if case .saving(.setRecordingEnabled) = self { true } else { false }
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
