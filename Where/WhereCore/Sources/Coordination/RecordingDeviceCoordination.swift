import Foundation

/// User-driven device-role changes; approval is internal so only recording can stop and transfer.
public actor RecordingDeviceCoordination: RecordingAuthorityReading {
    private let authority: RecordingAuthorityCoordinator
    private var isOperating = false
    private let installation: any InstallationRecordingContextStoring

    public init(
        authority: RecordingAuthorityCoordinator,
        installation: any InstallationRecordingContextStoring,
    ) {
        self.authority = authority
        self.installation = installation
    }

    public nonisolated func updates() -> AsyncStream<Void> {
        authority.updates()
    }

    public func observed() async throws -> RecordingAuthority {
        try await authority.observed()
    }

    public func deviceNames() async throws -> [RecordingDeviceID: String] {
        try await authority
            .deviceNames()
    }

    public func refresh() async throws -> RecordingAuthority {
        try await authority.refresh()
    }

    /// Network outages retain a verified local role. Authentication and malformed state do not.
    public func refreshForUse() async throws -> RecordingAuthority {
        do { return try await authority.refresh() }
        catch {
            guard CloudKitRecordingAuthorityTransport.isTemporarilyUnavailable(error),
                  try await installation.resolve().recordingControl.selection != .unconfirmed
            else { throw error }
            let cached = try await authority.observed()
            Self
                .logger(attachments: [.error(error, name: "authority-refresh-error")]) {
                    .usingCachedAuthority
                }
            return cached
        }
    }

    private static let logger = WhereLog.root(RecordingCoordinationLog.self)

    public func pendingApprovalRequestID() async throws -> RecordingAuthority.EventID? {
        let control = try await installation.resolve().recordingControl
        guard control.isRelinquishing else { return nil }
        return control.pendingTransition?.expected.pendingHandoff?.requestID
    }

    public func isRelinquishing() async throws -> Bool {
        try await installation.resolve().recordingControl.isRelinquishing
    }

    /// Persist identity/intent before the first server mutation, including on restored phones.
    public func selectRecordingRole(_ selection: RecordingInstallationControl
        .Selection) async throws -> RecordingAuthority
    {
        guard !isOperating else { throw RecordingAuthorityError.conflict }
        isOperating = true
        defer { isOperating = false }
        precondition(selection != .unconfirmed)
        let context = try await installation.resolve()
        let existing = context.recordingControl
        guard existing.pendingTransition == nil else { return try await retryPendingRequestImpl() }
        _ = try await installation
            .confirmInitialRecording(isEnabled: selection == .recordingRequested)
        try await installation.setAutomaticRecordingEnabled(selection == .recordingRequested)
        let state = try await authority.refresh()
        try await installation.setRecordingControl(.init(
            selection: selection,
            pendingTransition: nil,
        ))
        try await authority.registerInstallation(context)
        guard selection == .recordingRequested,
              state.owner?.deviceID != context.currentDevice.id else { return state }
        if state.pendingHandoff?.requestedBy == context.currentDevice.id { return state }
        let proposal = try RecordingAuthorityProposal(
            state: state,
            action: state.owner == nil ? .claim : .requestHandoff,
            deviceID: context.currentDevice.id,
            buildVersion: .current,
            eventID: .init(rawValue: UUID()),
        )
        try await submitPersisted(proposal, selection: selection)
        return try await authority.observed()
    }

    public func cancelHandoff(requestID: RecordingAuthority.EventID) async throws {
        guard !isOperating else { throw RecordingAuthorityError.conflict }
        isOperating = true
        defer { isOperating = false }
        let context = try await installation.resolve()
        let state = try await authority.refresh()
        // Resolve an uncertain approval before considering cancellation. A completed transfer is
        // final.
        if context.recordingControl.isRelinquishing,
           state.owner?.deviceID != context.currentDevice.id ||
           state.pendingHandoff?.requestID != requestID
        {
            try await installation.setRecordingControl(.init(
                selection: context.recordingControl.selection,
                pendingTransition: nil,
            ))
            return
        }
        let proposal = try RecordingAuthorityProposal(
            state: state,
            action: .cancelHandoff(requestID: requestID),
            deviceID: context.currentDevice.id,
            buildVersion: .current,
            eventID: .init(rawValue: UUID()),
        )
        try await submitPersisted(proposal, selection: context.recordingControl.selection)
    }

    /// Does not retry an approval: the recording controller must first stop all automatic work.
    public func retryPendingRequest() async throws -> RecordingAuthority {
        guard !isOperating else { throw RecordingAuthorityError.conflict }
        isOperating = true
        defer { isOperating = false }
        return try await retryPendingRequestImpl()
    }

    private func retryPendingRequestImpl() async throws -> RecordingAuthority {
        let context = try await installation.resolve()
        guard let proposal = context.recordingControl.pendingTransition
        else { return try await authority.refresh() }
        guard proposal.kind != .transfer else { return try await authority.refresh() }
        try await submitPersisted(proposal, selection: context.recordingControl.selection)
        return try await authority.observed()
    }

    func prepareApproval(requestID: RecordingAuthority
        .EventID) async throws -> RecordingAuthorityProposal
    {
        guard !isOperating else { throw RecordingAuthorityError.conflict }
        isOperating = true
        defer { isOperating = false }
        let context = try await installation.resolve()
        if let pending = context.recordingControl.pendingTransition {
            guard pending.kind == .transfer,
                  pending.expected.pendingHandoff?.requestID == requestID
            else { throw RecordingAuthorityError.invalidHandoff }
            return pending
        }
        let state = try await authority.refresh()
        let proposal = try RecordingAuthorityProposal(
            state: state,
            action: .approveHandoff(requestID: requestID),
            deviceID: context.currentDevice.id,
            buildVersion: .current,
            eventID: .init(rawValue: UUID()),
        )
        try await installation.setRecordingControl(.init(
            selection: context.recordingControl.selection,
            pendingTransition: proposal,
        ))
        return proposal
    }

    func commitStoppedApproval(_ proposal: RecordingAuthorityProposal) async throws {
        guard !isOperating else { throw RecordingAuthorityError.conflict }
        isOperating = true
        defer { isOperating = false }
        let context = try await installation.resolve()
        guard context.recordingControl.pendingTransition == proposal,
              proposal.kind == .transfer else { throw RecordingAuthorityError.invalidHandoff }
        try await submitPersisted(proposal, selection: context.recordingControl.selection)
    }

    private func submitPersisted(
        _ proposal: RecordingAuthorityProposal,
        selection: RecordingInstallationControl.Selection,
    ) async throws {
        try await installation.setRecordingControl(.init(
            selection: selection,
            pendingTransition: proposal,
        ))
        do {
            _ = try await authority.submit(proposal)
        } catch RecordingAuthorityError.conflict {
            _ = try await authority.refresh()
            // A rejected approval remains fenced until explicit cancellation resolves it.
            if proposal.kind != .transfer,
               try await installation.resolve().recordingControl.pendingTransition == proposal
            {
                try await installation.setRecordingControl(.init(
                    selection: selection,
                    pendingTransition: nil,
                ))
            }
            throw RecordingAuthorityError.conflict
        }
        // Never clear a newer command after an actor suspension.
        guard try await installation.resolve().recordingControl.pendingTransition == proposal
        else { throw RecordingAuthorityError.conflict }
        try await installation.setRecordingControl(.init(
            selection: selection,
            pendingTransition: nil,
        ))
    }
}
