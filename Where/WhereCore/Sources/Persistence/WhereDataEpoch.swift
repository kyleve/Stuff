import CryptoKit
import Foundation

/// Typed identity of one account-wide logical data generation.
///
/// Every synced user-data row belongs to exactly one epoch. Reset and backup Replace append a
/// new epoch before writing their result, so records uploaded later by an offline device remain
/// in the superseded epoch and cannot repopulate or alter the new account state.
public struct WhereDataEpochID: RawRepresentable, Codable, Sendable, Hashable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// Epoch used by rows created before the first destructive account operation. It is
    /// implicit rather than persisted, so independently installed devices begin in the same
    /// generation without racing to create a singleton row.
    public static let initial = WhereDataEpochID(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000E0")!,
    )
}

/// Operation that began a logical data epoch.
public enum WhereDataEpochReason: String, Codable, Sendable, Hashable {
    case initial
    case accountReset
    case backupReplace

    var isDestructive: Bool {
        self != .initial
    }

    /// A concurrent account reset wins over Replace because erasure is the stronger privacy
    /// command. A causally later Replace still wins through its higher revision.
    fileprivate var conflictPriority: Int {
        switch self {
            case .initial: 0
            case .backupReplace: 1
            case .accountReset: 2
        }
    }
}

/// Current account-wide logical data generation.
///
/// Revision zero is the implicit initial epoch. Destructive operations append immutable changes
/// at revisions one and above; equal revisions can arise from offline concurrent devices and
/// converge deterministically without trusting peer wall clocks.
public struct WhereDataEpoch: Identifiable, Codable, Sendable, Hashable {
    public let id: WhereDataEpochID
    public let parentIDs: [WhereDataEpochID]
    public let revision: Int64
    public let changedAt: Date
    public let changedByDeviceID: RecordingDeviceID?
    public let reason: WhereDataEpochReason

    public init(
        id: WhereDataEpochID,
        parentIDs: [WhereDataEpochID],
        revision: Int64,
        changedAt: Date,
        changedByDeviceID: RecordingDeviceID?,
        reason: WhereDataEpochReason,
    ) {
        precondition(revision >= 0, "A data-epoch revision cannot be negative.")
        precondition(
            (revision == 0) == (reason == .initial),
            "Only the implicit initial data epoch may use revision zero.",
        )
        precondition(
            (reason == .initial) == parentIDs.isEmpty,
            "A destructive data epoch must identify at least one parent.",
        )
        precondition(
            (reason == .initial) == (changedByDeviceID == nil),
            "A destructive data epoch must identify its issuing installation.",
        )
        let canonicalParentIDs = parentIDs.sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }
        precondition(
            Set(canonicalParentIDs).count == canonicalParentIDs.count,
            "A data epoch cannot name the same parent twice.",
        )
        precondition(
            canonicalParentIDs.contains(id) == false,
            "A data epoch cannot parent itself.",
        )
        self.id = id
        self.parentIDs = canonicalParentIDs
        self.revision = revision
        self.changedAt = changedAt
        self.changedByDeviceID = changedByDeviceID
        self.reason = reason
    }

    public static let initial = WhereDataEpoch(
        id: .initial,
        parentIDs: [],
        revision: 0,
        changedAt: .distantPast,
        changedByDeviceID: nil,
        reason: .initial,
    )

    var isDestructive: Bool {
        reason.isDestructive
    }

    /// Validated account-generation resolution. `current.id` is the epoch stamped on ordinary
    /// writes and can be a synthetic empty reset-conflict id; `realHeads` are the persisted
    /// maximal nodes a later destructive rotation must causally join.
    struct Resolution: Hashable {
        let current: WhereDataEpoch
        let realHeads: [WhereDataEpoch]
    }

    /// Orders concurrent maximal heads. Reset wins over Replace because erasure is the stronger
    /// privacy command. Between resets, the later erase boundary is more restrictive; immutable
    /// event identity breaks the remaining tie without relying on delivery order.
    static func isPreferredBefore(_ lhs: WhereDataEpoch, _ rhs: WhereDataEpoch) -> Bool {
        if lhs.reason.conflictPriority != rhs.reason.conflictPriority {
            return lhs.reason.conflictPriority < rhs.reason.conflictPriority
        }
        if lhs.reason == .accountReset, lhs.changedAt != rhs.changedAt {
            return lhs.changedAt < rhs.changedAt
        }
        return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
    }

    /// Validate the causal forest and return every maximal head.
    ///
    /// Descendants supersede every named parent, regardless of which concurrent sibling
    /// previously resolved as canonical. A later semantic operation names this entire frontier,
    /// causally joining everything it observed while leaving a genuinely concurrent,
    /// not-yet-delivered command eligible when it arrives.
    static func maximalHeads(in changes: [WhereDataEpoch]) throws -> [WhereDataEpoch] {
        guard changes.allSatisfy({
            $0.id != initial.id && isReservedSyntheticID($0.id) == false
        }) else {
            // The implicit root and UUIDv8 synthetic namespace are reserved. Synthetic epochs
            // are derived read state, never persisted events; accepting either identity on the
            // wire would let a real row masquerade as resolver-owned authority.
            throw RecordingPersistenceError.incompleteDataEpochHistory
        }
        let groupedByID = Dictionary(grouping: changes, by: \.id)
        guard groupedByID.values.allSatisfy({ $0.count == 1 }) else {
            throw RecordingPersistenceError.incompleteDataEpochHistory
        }
        var byID = groupedByID.compactMapValues(\.first)
        byID[initial.id] = initial

        var parentIDs = Set<WhereDataEpochID>()
        for change in changes {
            let canonicalParentIDs = change.parentIDs.sorted {
                $0.rawValue.uuidString < $1.rawValue.uuidString
            }
            guard change.parentIDs.isEmpty == false,
                  change.parentIDs == canonicalParentIDs,
                  Set(change.parentIDs).count == change.parentIDs.count,
                  change.parentIDs.contains(change.id) == false
            else {
                throw RecordingPersistenceError.incompleteDataEpochHistory
            }
            let parents = change.parentIDs.compactMap { byID[$0] }
            guard parents.count == change.parentIDs.count,
                  let maximumRevision = parents.map(\.revision).max(),
                  maximumRevision < Int64.max,
                  change.revision == maximumRevision + 1,
                  parents.allSatisfy({ change.changedAt >= $0.changedAt })
            else {
                throw RecordingPersistenceError.incompleteDataEpochHistory
            }
            parentIDs.formUnion(change.parentIDs)
        }

        return byID.values
            .filter { parentIDs.contains($0.id) == false }
            .sorted(by: isPreferredBefore)
    }

    /// Resolve the current logical generation and retain the real causal frontier needed for a
    /// later join. Two unjoined reset heads resolve to a deterministic empty UUIDv8 synthetic
    /// epoch, so neither reset branch's rows can defeat the other's erase intent through a UUID
    /// tie-break. UUIDv8 is reserved for this derived authority and is never a persisted event id.
    static func resolve(in changes: [WhereDataEpoch]) throws -> Resolution {
        let heads = try maximalHeads(in: changes)
        guard let head = heads.max(by: isPreferredBefore) else {
            preconditionFailure("The implicit data epoch must always form a causal head.")
        }
        let resetHeads = heads
            .filter { $0.reason == .accountReset }
            .sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        guard resetHeads.count > 1 else {
            return Resolution(current: head, realHeads: heads)
        }

        let syntheticID = resetConflictID(for: resetHeads)
        guard syntheticID != initial.id,
              changes.contains(where: { $0.id == syntheticID }) == false
        else {
            throw RecordingPersistenceError.incompleteDataEpochHistory
        }
        guard let maximumRevision = resetHeads.map(\.revision).max(),
              maximumRevision < Int64.max,
              let changedAt = resetHeads.map(\.changedAt).max(),
              let issuer = resetHeads.max(by: isPreferredBefore)?.changedByDeviceID
        else {
            throw RecordingPersistenceError.incompleteDataEpochHistory
        }
        let synthetic = WhereDataEpoch(
            id: syntheticID,
            parentIDs: resetHeads.map(\.id),
            revision: maximumRevision + 1,
            changedAt: changedAt,
            changedByDeviceID: issuer,
            reason: .accountReset,
        )
        return Resolution(current: synthetic, realHeads: heads)
    }

    static func canonicalHead(in changes: [WhereDataEpoch]) throws -> WhereDataEpoch {
        try resolve(in: changes).current
    }

    /// Latest account reset that the installation's registration point did not observe.
    /// Registrations normally name a persisted epoch. A registration made while concurrent
    /// resets resolve to a synthetic epoch is recognized both while that conflict is current and
    /// after a later destructive operation joins its real reset heads.
    static func resetBarrier(
        for registrationEpochID: WhereDataEpochID,
        in changes: [WhereDataEpoch],
    ) throws -> Date? {
        let resets = changes.filter { $0.reason == .accountReset }
        guard resets.isEmpty == false else { return nil }

        var byID = Dictionary(uniqueKeysWithValues: changes.map { ($0.id, $0) })
        byID[initial.id] = initial

        func ancestors(of epochIDs: [WhereDataEpochID]) -> Set<WhereDataEpochID>? {
            var result = Set<WhereDataEpochID>()
            var pending = epochIDs
            while let id = pending.popLast() {
                guard result.insert(id).inserted else { continue }
                guard let epoch = byID[id] else { return nil }
                pending.append(contentsOf: epoch.parentIDs)
            }
            return result
        }

        let observed: Set<WhereDataEpochID>?
        if byID[registrationEpochID] != nil {
            observed = ancestors(of: [registrationEpochID])
        } else {
            let resolution = try resolve(in: changes)
            if resolution.current.id == registrationEpochID {
                observed = ancestors(of: resolution.current.parentIDs)
            } else {
                let joinedResetParents = changes.compactMap { epoch -> [WhereDataEpoch]? in
                    let parents = epoch.parentIDs.compactMap { byID[$0] }
                    let resetParents = parents.filter { $0.reason == .accountReset }
                    guard resetParents.count > 1,
                          resetConflictID(for: resetParents) == registrationEpochID
                    else { return nil }
                    return resetParents
                }.first
                observed = joinedResetParents.flatMap { ancestors(of: $0.map(\.id)) }
            }
        }

        let observedIDs = observed ?? []
        return resets
            .filter { observedIDs.contains($0.id) == false }
            .map(\.changedAt)
            .max()
    }

    /// Versioned, domain-separated digest locked by `WhereDataEpochTests`. Only reset-head ids
    /// participate, keeping the synthetic empty generation stable when a weaker concurrent
    /// Replace arrives while still changing it for every newly relevant reset.
    private static func resetConflictID(
        for resetHeads: [WhereDataEpoch],
    ) -> WhereDataEpochID {
        var hasher = SHA256()
        hasher.update(data: Data("com.stuff.where.data-epoch.reset-conflict.v1".utf8))
        for head in resetHeads {
            hasher.update(data: Data("\n\(head.id.rawValue.uuidString)".utf8))
        }
        var bytes = Array(hasher.finalize().prefix(16))
        // UUIDv8 is the RFC-defined application-specific namespace. Persisted event ids come
        // from UUID() (v4), so the version nibble makes synthetic read authority recognizable
        // and rejectable without maintaining a registry of every possible reset frontier.
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return WhereDataEpochID(rawValue: UUID(uuid: (
            bytes[0],
            bytes[1],
            bytes[2],
            bytes[3],
            bytes[4],
            bytes[5],
            bytes[6],
            bytes[7],
            bytes[8],
            bytes[9],
            bytes[10],
            bytes[11],
            bytes[12],
            bytes[13],
            bytes[14],
            bytes[15],
        )))
    }

    private static func isReservedSyntheticID(_ id: WhereDataEpochID) -> Bool {
        let bytes = id.rawValue.uuid
        return bytes.6 & 0xF0 == 0x80
    }
}
