import Foundation
import Observation
import WhereCore

/// Shared role-selection state for first launch and Devices settings.
@MainActor
@Observable
final class RecordingDeviceRoleModel {
    struct Details: Equatable {
        let authority: RecordingAuthority
        let currentDeviceID: RecordingDeviceID
        let names: [RecordingDeviceID: String]
        var interruptedApproval: RecordingAuthority.EventID?
        var isOwner: Bool {
            authority.owner?.deviceID == currentDeviceID
        }

        var isWaiting: Bool {
            authority.pendingHandoff?.requestedBy == currentDeviceID
        }
    }

    struct RecoveryReview: Identifiable {
        let owner: RecordingAuthority.Owner
        let deviceName: String
        var id: RecordingAuthority.EventID {
            owner.tenureID
        }
    }

    var recoveryReview: RecoveryReview?

    enum State: Equatable {
        case loading
        case loaded(Details)
        case working(Details)
        case failed(Details?, String)

        var details: Details? {
            switch self {
                case .loading: nil
                case let .loaded(details), let .working(details): details
                case let .failed(details, _): details
            }
        }
    }

    private(set) var state: State = .loading
    private var readID = UUID()
    private let coordination: RecordingDeviceCoordination
    private let currentDeviceID: RecordingDeviceID
    private let selectionChanged: (@MainActor (Bool) async throws -> Void)?
    private let approve: (@MainActor (RecordingAuthority.EventID) async throws -> Void)?

    init(
        coordination: RecordingDeviceCoordination,
        currentDeviceID: RecordingDeviceID,
        selectionChanged: (@MainActor (Bool) async throws -> Void)?,
        approve: (@MainActor (RecordingAuthority.EventID) async throws -> Void)?,
    ) {
        self.coordination = coordination
        self.currentDeviceID = currentDeviceID
        self.approve = approve
        self.selectionChanged = selectionChanged
    }

    var isOwner: Bool {
        state.details?.isOwner == true
    }

    var canApprove: Bool {
        approve != nil
    }

    func run() async {
        let updates = coordination.updates()
        await refresh()
        for await _ in updates {
            guard !Task.isCancelled else { return }
            await loadFromStore()
        }
    }

    func refresh() async {
        if case .working = state { return }
        let refreshID = UUID()
        readID = refreshID
        do {
            _ = try await coordination.refresh()
            guard readID == refreshID, !Task.isCancelled else { return }
            await loadFromStore()
        } catch {
            guard readID == refreshID, !Task.isCancelled else { return }
            state = .failed(state.details, error.localizedDescription)
        }
    }

    /// Nil means a request is waiting or failed; a value can complete first-launch selection.
    func choose(recording: Bool) async -> Bool? {
        guard case let .loaded(details) = state else { return nil }
        readID = UUID()
        state = .working(details)
        do {
            if !recording, let request = details.authority.pendingHandoff,
               request.requestedBy == currentDeviceID
            {
                try await coordination.cancelHandoff(requestID: request.requestID)
            }
            let updated = try await coordination
                .selectRecordingRole(recording ? .recordingRequested : .secondary)
            try await selectionChanged?(recording)
            state = .loaded(details)
            await loadFromStore()
            return !recording || updated.owner?.deviceID == currentDeviceID ? recording : nil
        } catch {
            state = .failed(details, error.localizedDescription)
            return nil
        }
    }

    func reviewRecovery() {
        guard case let .loaded(details) = state,
              let owner = details.authority.owner, !details.isOwner else { return }
        recoveryReview = .init(
            owner: owner,
            deviceName: details
                .names[owner.deviceID] ?? String(localized: .recordingRoleAnotherDevice),
        )
    }

    func recover(history: RecordingRecoveryHistory) async {
        guard case let .loaded(details) = state, let review = recoveryReview else { return }
        recoveryReview = nil
        readID = UUID()
        state = .working(details)
        do {
            _ = try await coordination.recover(replacing: review.owner, history: history)
            try await selectionChanged?(true)
            state = .loaded(details)
            await loadFromStore()
        } catch { state = .failed(details, error.localizedDescription) }
    }

    func approveRequest() async {
        guard case let .loaded(details) = state, let request = details.authority.pendingHandoff,
              let approve else { return }
        readID = UUID()
        state = .working(details)
        do {
            try await approve(request.requestID)
            state = .loaded(details)
            await loadFromStore()
        } catch { state = .failed(details, error.localizedDescription) }
    }

    func cancelRequest() async {
        guard case let .loaded(details) = state,
              let requestID = details.interruptedApproval ?? details.authority.pendingHandoff?
              .requestID else { return }
        readID = UUID()
        state = .working(details)
        do {
            try await coordination.cancelHandoff(requestID: requestID)
            state = .loaded(details)
            await loadFromStore()
        } catch { state = .failed(details, error.localizedDescription) }
    }

    private func loadFromStore() async {
        if case .working = state { return }
        let requestID = UUID()
        readID = requestID
        do {
            let authority = try await coordination.observed()
            let names = try await coordination.deviceNames()
            let interruptedApproval = try await coordination.pendingApprovalRequestID()
            guard readID == requestID, !Task.isCancelled else { return }
            state = .loaded(.init(
                authority: authority,
                currentDeviceID: currentDeviceID,
                names: names,
                interruptedApproval: interruptedApproval,
            ))
        } catch {
            guard readID == requestID, !Task.isCancelled else { return }
            state = .failed(state.details, error.localizedDescription)
        }
    }
}
