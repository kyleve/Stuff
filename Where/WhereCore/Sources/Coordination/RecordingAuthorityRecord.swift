import Foundation

/// Stable, synthesized wire shapes for authority history and installation-side pending requests.
/// These records may contain invalid combinations. Convert through `value` before using them;
/// domain enums never decode unchecked payloads or inherit persisted Swift case names.
public struct RecordingAuthorityRecord: Codable, Equatable, Sendable {
    let revision: RecordingAuthority.Revision?
    let owner: RecordingAuthority.Owner?
    let pendingHandoff: RecordingAuthority.Handoff?
    let requiredVersion: DataCompatibilityVersion

    init(_ value: RecordingAuthority) {
        revision = value.revision
        owner = value.owner
        pendingHandoff = value.pendingHandoff
        requiredVersion = value.requiredVersion
    }

    var value: RecordingAuthority {
        get throws {
            guard let revision else {
                guard owner == nil, pendingHandoff == nil, requiredVersion == .initial
                else { throw RecordingAuthorityError.invalidRecord }
                return .unclaimed
            }
            guard let owner else { throw RecordingAuthorityError.invalidRecord }
            return try .established(.init(
                revision: revision,
                owner: owner,
                pendingHandoff: pendingHandoff,
                requiredVersion: requiredVersion,
            ))
        }
    }

    /// Preserves the existing expected/result/kind/recoveryHistory JSON contract.
    public struct Proposal: Codable, Equatable, Sendable {
        let expected: RecordingAuthorityRecord
        let result: RecordingAuthorityRecord
        let kind: RecordingAuthorityProposal.Kind
        let recoveryHistory: RecordingRecoveryHistory?

        public init(_ proposal: RecordingAuthorityProposal) {
            expected = .init(proposal.expected)
            result = .init(proposal.result.authority)
            kind = proposal.kind
            if case let .recover(history) = proposal.transition { recoveryHistory = history }
            else { recoveryHistory = nil }
        }

        /// Reconstruct a legal transition and compare all stored fields. Valid endpoints alone
        /// do not prove a legal edge. This checks protocol shape, not claimed device identity.
        public var value: RecordingAuthorityProposal {
            get throws {
                let expected = try expected.value
                guard case let .established(result) = try result.value
                else { throw RecordingAuthorityError.invalidRecord }
                let device: RecordingDeviceID
                let action: RecordingAuthorityProposal.Action
                let version: DataCompatibilityVersion
                switch kind {
                    case .claim:
                        device = result.owner.deviceID
                        action = .claim
                        version = expected.requiredVersion
                    case .request:
                        guard let pending = result.pendingHandoff
                        else { throw RecordingAuthorityError.invalidRecord }
                        device = pending.requestedBy
                        action = .requestHandoff
                        version = pending.supportedVersion
                    case .cancel, .transfer:
                        guard let pending = expected.pendingHandoff, let owner = expected.owner
                        else { throw RecordingAuthorityError.invalidRecord }
                        device = owner.deviceID
                        action = kind == .cancel ? .cancelHandoff(requestID: pending.requestID) :
                            .approveHandoff(requestID: pending.requestID)
                        version = expected.requiredVersion
                    case .recover:
                        guard let recoveryHistory
                        else { throw RecordingAuthorityError.invalidRecord }
                        device = result.owner.deviceID
                        action = .recover(recoveryHistory)
                        version = expected.requiredVersion
                    case .upgrade:
                        guard let owner = expected.owner
                        else { throw RecordingAuthorityError.invalidRecord }
                        device = owner.deviceID
                        action = .upgrade
                        version = result.requiredVersion
                }
                let proposal = try RecordingAuthorityProposal(
                    state: expected,
                    action: action,
                    deviceID: device,
                    buildVersion: version,
                    eventID: result.revision.eventID,
                )
                guard Self(proposal) == self else { throw RecordingAuthorityError.invalidRecord }
                return proposal
            }
        }
    }

    /// Stable immutable-history payload stored in SwiftData.
    struct Commit: Codable {
        let proposal: Proposal
        let committedAt: Date

        init(_ commit: RecordingAuthorityCommit) {
            proposal = .init(commit.proposal)
            committedAt = commit.committedAt
        }

        var value: RecordingAuthorityCommit {
            get throws { try .init(proposal: proposal.value, committedAt: committedAt) }
        }
    }
}
