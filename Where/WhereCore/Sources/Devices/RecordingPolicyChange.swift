import CryptoKit
import Foundation

/// Complete desired authority for one recording installation.
///
/// Archive belongs here rather than in the editable profile metadata stream: turning a device
/// Off and hiding it is one causal command, so CloudKit can never deliver independent halves
/// that later undo a newer re-enable.
public enum RecordingPolicyState: String, Codable, Sendable, Hashable {
    case on
    case off
    case archived

    public var isEnabled: Bool {
        self == .on
    }

    public var isArchived: Bool {
        self == .archived
    }
}

/// Why a recording-authority event was appended.
public enum RecordingPolicyReason: String, Codable, Sendable, Hashable {
    case initialRegistration
    case userCommand
    case archive
    case backupMerge
    case accountReset
    case backupReplace

    /// Destructive account operations must discard a target's unsynced retry backlog so an
    /// offline device cannot repopulate data the user explicitly erased or replaced.
    var discardsPendingSamples: Bool {
        switch self {
            case .accountReset, .backupReplace: true
            case .initialRegistration, .userCommand, .archive, .backupMerge: false
        }
    }
}

/// Append-only change to automatic recording policy for one device.
///
/// `parentIDs` and `revision` form a causal DAG without comparing clocks from different devices.
/// One command names every maximal event its writer observed, so it is a semantic join rather
/// than one physical child per branch. `effectiveAt` remains the historical cutoff applied to
/// samples, while `issuedAt` and `issuedByDeviceID` retain an auditable account of the command.
public struct RecordingPolicyChange: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let deviceID: RecordingDeviceID
    public let parentIDs: [UUID]
    public let revision: Int64
    public let issuedAt: Date
    public let issuedByDeviceID: RecordingDeviceID
    public let effectiveAt: Date
    public let state: RecordingPolicyState
    public let reason: RecordingPolicyReason

    public var isEnabled: Bool {
        state.isEnabled
    }

    public var isArchived: Bool {
        state.isArchived
    }

    public init(
        id: UUID,
        deviceID: RecordingDeviceID,
        parentIDs: [UUID],
        revision: Int64,
        issuedAt: Date,
        issuedByDeviceID: RecordingDeviceID,
        effectiveAt: Date,
        state: RecordingPolicyState,
        reason: RecordingPolicyReason,
    ) {
        precondition(revision >= 0, "A recording-policy revision cannot be negative.")
        precondition(
            (revision == 0) == parentIDs.isEmpty,
            "Only a recording-policy root may omit its parents.",
        )
        let canonicalParentIDs = parentIDs.sorted { $0.uuidString < $1.uuidString }
        precondition(
            Set(canonicalParentIDs).count == canonicalParentIDs.count,
            "A recording-policy command cannot name the same parent twice.",
        )
        precondition(
            canonicalParentIDs.contains(id) == false,
            "A recording-policy command cannot parent itself.",
        )
        self.id = id
        self.deviceID = deviceID
        self.parentIDs = canonicalParentIDs
        self.revision = revision
        self.issuedAt = issuedAt
        self.issuedByDeviceID = issuedByDeviceID
        self.effectiveAt = effectiveAt
        self.state = state
        self.reason = reason
    }
}

extension RecordingPolicyChange {
    private struct CausalGraph {
        let byID: [UUID: RecordingPolicyChange]
        let heads: [RecordingPolicyChange]
    }

    /// Whether the persisted reason and complete-authority state describe a command the domain
    /// can issue. Kept on the value so every wire/storage boundary can reject the same malformed
    /// combinations without duplicating the matrix.
    var hasValidReasonAndState: Bool {
        switch (reason, state) {
            case (.initialRegistration, .on),
                 (.initialRegistration, .off),
                 (.userCommand, .on),
                 (.userCommand, .off),
                 (.archive, .archived),
                 (.backupMerge, .on),
                 (.backupMerge, .off),
                 (.backupMerge, .archived),
                 (.accountReset, .off),
                 (.accountReset, .archived),
                 (.backupReplace, .off),
                 (.backupReplace, .archived):
                true
            case (.initialRegistration, .archived),
                 (.userCommand, .archived),
                 (.archive, .on),
                 (.archive, .off),
                 (.accountReset, .on),
                 (.backupReplace, .on):
                false
        }
    }

    /// A complete persisted policy snapshot has at least one revision-zero root for every
    /// device, and every later event names a unique, present parent set, advances one revision
    /// beyond that set's maximum, and never moves its historical cutoff before any parent.
    /// Multiple roots or unjoined heads remain valid: concurrent CloudKit writers can legitimately
    /// produce them, and resolution compares every maximal causal head.
    static func formValidPersistedTimelines(_ changes: [RecordingPolicyChange]) -> Bool {
        guard changes.allSatisfy({ $0.revision >= 0 && $0.hasValidReasonAndState }) else {
            return false
        }
        return Dictionary(grouping: changes, by: \.deviceID).values.allSatisfy { timeline in
            canonicalTimeline(in: timeline) != nil
        }
    }

    /// Resolve the authoritative maximal head's ancestor DAG for one installation.
    ///
    /// Descendants supersede ancestors. Concurrent maximal heads remain eligible even when they
    /// descend from a sibling that previously lost resolution; destructive/restrictive state
    /// wins between those heads, followed by immutable identity. A local command names every
    /// observed head so one post-convergence action can causally supersede all of them. The
    /// returned order is deterministic and causal (revision first), with the selected
    /// head last; historical evaluation resolves the eligible induced DAG directly rather than
    /// treating this array as a single branch.
    static func canonicalTimeline(
        in changes: [RecordingPolicyChange],
    ) -> [RecordingPolicyChange]? {
        guard changes.isEmpty == false else { return [] }
        guard let graph = causalGraph(in: changes),
              let head = graph.heads.max(by: isPreferredBefore)
        else { return nil }

        var ancestorIDs: Set<UUID> = [head.id]
        var pending = head.parentIDs
        while let parentID = pending.popLast() {
            guard let parent = graph.byID[parentID] else { return nil }
            if ancestorIDs.insert(parent.id).inserted {
                pending.append(contentsOf: parent.parentIDs)
            }
        }
        return ancestorIDs
            .compactMap { graph.byID[$0] }
            .sorted(by: isOrderedBefore)
    }

    static func canonicalHead(
        in changes: [RecordingPolicyChange],
    ) -> RecordingPolicyChange? {
        canonicalTimeline(in: changes)?.last
    }

    /// Resolve authority at one historical instant from the induced causal DAG. Effective times
    /// are monotonic across every parent edge, so removing future commands leaves an
    /// ancestor-complete graph whose concurrent heads use the same safety-first join as current
    /// authority.
    static func effectiveHead(
        in changes: [RecordingPolicyChange],
        at date: Date,
    ) -> RecordingPolicyChange? {
        guard causalGraph(in: changes) != nil else { return nil }
        let eligible = changes.filter { $0.effectiveAt <= date }
        guard eligible.isEmpty == false else { return nil }
        return canonicalHead(in: eligible)
    }

    /// Every currently maximal causal head, ordered by the same deterministic safety lattice as
    /// resolution. An empty valid history has an empty frontier; malformed history returns nil.
    static func maximalHeads(
        in changes: [RecordingPolicyChange],
    ) -> [RecordingPolicyChange]? {
        guard changes.isEmpty == false else { return [] }
        return causalGraph(in: changes)?.heads.sorted(by: isPreferredBefore)
    }

    /// Create one semantic command naming every observed maximal head. After this node syncs,
    /// every observed branch has been causally superseded while an unseen concurrent branch
    /// remains eligible.
    static func appendingCommand(
        to changes: [RecordingPolicyChange],
        deviceID: RecordingDeviceID,
        issuedAt: Date,
        issuedByDeviceID: RecordingDeviceID,
        effectiveAt: Date,
        state: RecordingPolicyState,
        reason: RecordingPolicyReason,
    ) throws -> RecordingPolicyChange {
        guard let heads = maximalHeads(in: changes),
              changes.allSatisfy({ $0.deviceID == deviceID })
        else {
            throw RecordingPersistenceError.incompletePolicyHistory(deviceID)
        }
        let commandEffectiveAt = heads.reduce(effectiveAt) { partialResult, head in
            max(partialResult, head.effectiveAt)
        }
        let maximumRevision = heads.map(\.revision).max()
        let revision: Int64
        if let maximumRevision {
            let (next, overflow) = maximumRevision.addingReportingOverflow(1)
            guard overflow == false else {
                throw RecordingPersistenceError.revisionExhausted(deviceID)
            }
            revision = next
        } else {
            revision = 0
        }
        return RecordingPolicyChange(
            id: UUID(),
            deviceID: deviceID,
            parentIDs: heads.map(\.id),
            revision: revision,
            issuedAt: issuedAt,
            issuedByDeviceID: issuedByDeviceID,
            effectiveAt: commandEffectiveAt,
            state: state,
            reason: reason,
        )
    }

    /// Stable acknowledgement token for the causally maximal destructive frontier. A singleton
    /// uses its event id; multiple concurrent barriers hash the entire sorted id set so delivery
    /// of any newly relevant barrier changes the token and forces the target to clear its outbox
    /// again before acknowledging authority.
    static func destructiveCleanupToken(
        in changes: [RecordingPolicyChange],
    ) -> RecordingPolicyCleanupToken? {
        guard let frontier = destructiveFrontier(in: changes), frontier.isEmpty == false else {
            return nil
        }
        guard frontier.count > 1 else {
            return RecordingPolicyCleanupToken(rawValue: frontier[0].id)
        }

        var hasher = SHA256()
        hasher.update(data: Data("com.stuff.where.recording-cleanup-frontier.v1".utf8))
        for change in frontier.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.update(data: Data("\n\(change.id.uuidString)".utf8))
        }
        let digest = Array(hasher.finalize().prefix(16))
        return RecordingPolicyCleanupToken(rawValue: UUID(uuid: (
            digest[0],
            digest[1],
            digest[2],
            digest[3],
            digest[4],
            digest[5],
            digest[6],
            digest[7],
            digest[8],
            digest[9],
            digest[10],
            digest[11],
            digest[12],
            digest[13],
            digest[14],
            digest[15],
        )))
    }

    /// Conservative historical erase floor contributed by active account-reset barriers. A
    /// later non-destructive On does not clear it; only a causally later destructive boundary
    /// removes its ancestor from the destructive frontier. Concurrent reset floors join by the
    /// latest effective cutoff.
    static func activeAccountResetFloor(
        in changes: [RecordingPolicyChange],
    ) -> Date? {
        destructiveFrontier(in: changes)?
            .filter { $0.reason == .accountReset }
            .map(\.effectiveAt)
            .max()
    }

    /// Deterministic causal ordering. At an equal revision, destructive cleanup wins first,
    /// followed by the more restrictive state, so a concurrent On cannot defeat an
    /// Off/archive/reset command; UUID text breaks the remaining tie.
    static func isOrderedBefore(
        _ lhs: RecordingPolicyChange,
        _ rhs: RecordingPolicyChange,
    ) -> Bool {
        if lhs.revision != rhs.revision {
            return lhs.revision < rhs.revision
        }
        return isPreferredBefore(lhs, rhs)
    }

    /// Orders competing roots or children of the same parent. Destructive cleanup wins first,
    /// followed by the more restrictive state; immutable identity breaks the remaining tie.
    private static func isPreferredBefore(
        _ lhs: RecordingPolicyChange,
        _ rhs: RecordingPolicyChange,
    ) -> Bool {
        if lhs.reason.conflictPriority != rhs.reason.conflictPriority {
            return lhs.reason.conflictPriority < rhs.reason.conflictPriority
        }
        if lhs.state.conflictPriority != rhs.state.conflictPriority {
            return lhs.state.conflictPriority < rhs.state.conflictPriority
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func causalGraph(
        in changes: [RecordingPolicyChange],
    ) -> CausalGraph? {
        guard let deviceID = changes.first?.deviceID,
              changes.allSatisfy({
                  $0.deviceID == deviceID && $0.revision >= 0 && $0.hasValidReasonAndState
              })
        else { return nil }

        let groupedByID = Dictionary(grouping: changes, by: \.id)
        guard groupedByID.values.allSatisfy({ $0.count == 1 }) else { return nil }
        let byID = groupedByID.compactMapValues(\.first)
        var parentIDs = Set<UUID>()
        for change in changes {
            let canonicalParentIDs = change.parentIDs.sorted { $0.uuidString < $1.uuidString }
            if change.revision == 0 {
                guard change.parentIDs.isEmpty, change.parentIDs == canonicalParentIDs else {
                    return nil
                }
                continue
            }
            guard change.parentIDs.isEmpty == false,
                  change.parentIDs == canonicalParentIDs,
                  Set(change.parentIDs).count == change.parentIDs.count,
                  change.parentIDs.contains(change.id) == false
            else { return nil }
            let parents = change.parentIDs.compactMap { byID[$0] }
            guard parents.count == change.parentIDs.count,
                  parents.allSatisfy({ $0.deviceID == deviceID }),
                  let maximumRevision = parents.map(\.revision).max(),
                  maximumRevision < Int64.max,
                  change.revision == maximumRevision + 1,
                  parents.allSatisfy({ change.effectiveAt >= $0.effectiveAt })
            else {
                return nil
            }
            parentIDs.formUnion(change.parentIDs)
        }
        let heads = changes.filter { parentIDs.contains($0.id) == false }
        guard heads.isEmpty == false else { return nil }
        return CausalGraph(byID: byID, heads: heads)
    }

    /// Destructive boundaries remain active until another destructive event causally descends
    /// from them. Non-destructive On/Off commands intentionally do not clear a reset's historical
    /// erase floor.
    private static func destructiveFrontier(
        in changes: [RecordingPolicyChange],
    ) -> [RecordingPolicyChange]? {
        guard changes.isEmpty == false else { return [] }
        guard let graph = causalGraph(in: changes) else { return nil }
        let destructive = changes.filter(\.reason.discardsPendingSamples)
        var superseded = Set<UUID>()
        for change in destructive {
            var pending = change.parentIDs
            var visited = Set<UUID>()
            while let id = pending.popLast(), let ancestor = graph.byID[id] {
                guard visited.insert(id).inserted else { continue }
                if ancestor.reason.discardsPendingSamples {
                    superseded.insert(ancestor.id)
                }
                pending.append(contentsOf: ancestor.parentIDs)
            }
        }
        return destructive.filter { superseded.contains($0.id) == false }
    }

    /// Stable winner when CloudKit supplies conflicting values for one immutable event id.
    static func isCanonicalBefore(
        _ lhs: RecordingPolicyChange,
        _ rhs: RecordingPolicyChange,
    ) -> Bool {
        if lhs.deviceID != rhs.deviceID {
            return lhs.deviceID.storeURL.absoluteString < rhs.deviceID.storeURL.absoluteString
        }
        if lhs.parentIDs != rhs.parentIDs {
            return lhs.parentIDs.map(\.uuidString).joined(separator: ",")
                < rhs.parentIDs.map(\.uuidString).joined(separator: ",")
        }
        if lhs.revision != rhs.revision { return lhs.revision < rhs.revision }
        if lhs.issuedAt != rhs.issuedAt { return lhs.issuedAt < rhs.issuedAt }
        if lhs.issuedByDeviceID != rhs.issuedByDeviceID {
            return lhs.issuedByDeviceID.storeURL.absoluteString
                < rhs.issuedByDeviceID.storeURL.absoluteString
        }
        if lhs.effectiveAt != rhs.effectiveAt { return lhs.effectiveAt < rhs.effectiveAt }
        if lhs.state != rhs.state { return lhs.state.rawValue < rhs.state.rawValue }
        return lhs.reason.rawValue < rhs.reason.rawValue
    }
}

extension RecordingPolicyState {
    fileprivate var conflictPriority: Int {
        switch self {
            case .on: 0
            case .off: 1
            case .archived: 2
        }
    }
}

extension RecordingPolicyReason {
    fileprivate var conflictPriority: Int {
        switch self {
            case .initialRegistration, .userCommand, .archive, .backupMerge: 0
            case .backupReplace: 1
            case .accountReset: 2
        }
    }
}
