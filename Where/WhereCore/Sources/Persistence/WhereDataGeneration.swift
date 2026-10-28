import CryptoKit
import Foundation

/// Typed identity of one account-wide logical data generation.
///
/// Every synced user-data row belongs to exactly one generation. Reset and backup Replace append a
/// new generation before writing their result, so records uploaded later by an offline device
/// remain
/// in the superseded generation and cannot repopulate or alter the new account state.
public struct WhereDataGenerationID: RawRepresentable, Codable, Sendable, Hashable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// Generation used by rows created before the first destructive account operation. It is
    /// implicit rather than persisted, so independently installed devices begin in the same
    /// generation without racing to create a singleton row.
    public static let initial = WhereDataGenerationID(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000E0")!,
    )
}

/// Operation that began a logical data generation.
public enum WhereDataGenerationReason: String, Codable, Sendable, Hashable {
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
/// Revision zero is the implicit initial generation. Destructive operations append immutable
/// changes
/// at revisions one and above; equal revisions can arise from offline concurrent devices and
/// converge deterministically without trusting peer wall clocks.
public struct WhereDataGeneration: Identifiable, Codable, Sendable, Hashable {
    public let id: WhereDataGenerationID
    public let parentIDs: [WhereDataGenerationID]
    public let revision: Int64
    public let changedAt: Date
    public let changedByDeviceID: RecordingDeviceID?
    public let reason: WhereDataGenerationReason

    public init(
        id: WhereDataGenerationID,
        parentIDs: [WhereDataGenerationID],
        revision: Int64,
        changedAt: Date,
        changedByDeviceID: RecordingDeviceID?,
        reason: WhereDataGenerationReason,
    ) {
        precondition(revision >= 0, "A data-generation revision cannot be negative.")
        precondition(
            (revision == 0) == (reason == .initial),
            "Only the implicit initial data generation may use revision zero.",
        )
        precondition(
            (reason == .initial) == parentIDs.isEmpty,
            "A destructive data generation must identify at least one parent.",
        )
        precondition(
            (reason == .initial) == (changedByDeviceID == nil),
            "A destructive data generation must identify its issuing installation.",
        )
        let canonicalParentIDs = parentIDs.sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }
        precondition(
            Set(canonicalParentIDs).count == canonicalParentIDs.count,
            "A data generation cannot name the same parent twice.",
        )
        precondition(
            canonicalParentIDs.contains(id) == false,
            "A data generation cannot parent itself.",
        )
        self.id = id
        self.parentIDs = canonicalParentIDs
        self.revision = revision
        self.changedAt = changedAt
        self.changedByDeviceID = changedByDeviceID
        self.reason = reason
    }

    public static let initial = WhereDataGeneration(
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

    /// Validated account-generation resolution. `current.id` is the generation stamped on ordinary
    /// writes and can be a synthetic empty reset-conflict id; `realHeads` are the persisted
    /// maximal nodes a later destructive rotation must causally join.
    struct Resolution: Hashable {
        let current: WhereDataGeneration
        let realHeads: [WhereDataGeneration]
    }

    /// Orders concurrent maximal heads. Reset wins over Replace because erasure is the stronger
    /// privacy command. Between resets, the later erase boundary is more restrictive; immutable
    /// event identity breaks the remaining tie without relying on delivery order.
    static func isPreferredBefore(_ lhs: WhereDataGeneration, _ rhs: WhereDataGeneration) -> Bool {
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
    static func maximalHeads(in changes: [WhereDataGeneration]) throws -> [WhereDataGeneration] {
        guard changes.allSatisfy({
            $0.id != initial.id && isReservedSyntheticID($0.id) == false
        }) else {
            // The implicit root and UUIDv8 synthetic namespace are reserved. Synthetic generations
            // are derived read state, never persisted events; accepting either identity on the
            // wire would let a real row masquerade as resolver-owned authority.
            throw RecordingPersistenceError.incompleteDataGenerationHistory
        }
        let groupedByID = Dictionary(grouping: changes, by: \.id)
        guard groupedByID.values.allSatisfy({ $0.count == 1 }) else {
            throw RecordingPersistenceError.incompleteDataGenerationHistory
        }
        var byID = groupedByID.compactMapValues(\.first)
        byID[initial.id] = initial

        var parentIDs = Set<WhereDataGenerationID>()
        for change in changes {
            let canonicalParentIDs = change.parentIDs.sorted {
                $0.rawValue.uuidString < $1.rawValue.uuidString
            }
            guard change.parentIDs.isEmpty == false,
                  change.parentIDs == canonicalParentIDs,
                  Set(change.parentIDs).count == change.parentIDs.count,
                  change.parentIDs.contains(change.id) == false
            else {
                throw RecordingPersistenceError.incompleteDataGenerationHistory
            }
            let parents = change.parentIDs.compactMap { byID[$0] }
            guard parents.count == change.parentIDs.count,
                  let maximumRevision = parents.map(\.revision).max(),
                  maximumRevision < Int64.max,
                  change.revision == maximumRevision + 1,
                  parents.allSatisfy({ change.changedAt >= $0.changedAt })
            else {
                throw RecordingPersistenceError.incompleteDataGenerationHistory
            }
            parentIDs.formUnion(change.parentIDs)
        }

        return byID.values
            .filter { parentIDs.contains($0.id) == false }
            .sorted(by: isPreferredBefore)
    }

    /// Resolve the current logical generation and retain the real causal frontier needed for a
    /// later join. Two unjoined reset heads resolve to a deterministic empty UUIDv8 synthetic
    /// generation, so neither reset branch's rows can defeat the other's erase intent through a
    /// UUID
    /// tie-break. UUIDv8 is reserved for this derived authority and is never a persisted event id.
    static func resolve(in changes: [WhereDataGeneration]) throws -> Resolution {
        let heads = try maximalHeads(in: changes)
        guard let head = heads.max(by: isPreferredBefore) else {
            preconditionFailure("The implicit data generation must always form a causal head.")
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
            throw RecordingPersistenceError.incompleteDataGenerationHistory
        }
        guard let maximumRevision = resetHeads.map(\.revision).max(),
              maximumRevision < Int64.max,
              let changedAt = resetHeads.map(\.changedAt).max(),
              let issuer = resetHeads.max(by: isPreferredBefore)?.changedByDeviceID
        else {
            throw RecordingPersistenceError.incompleteDataGenerationHistory
        }
        let synthetic = WhereDataGeneration(
            id: syntheticID,
            parentIDs: resetHeads.map(\.id),
            revision: maximumRevision + 1,
            changedAt: changedAt,
            changedByDeviceID: issuer,
            reason: .accountReset,
        )
        return Resolution(current: synthetic, realHeads: heads)
    }

    static func canonicalHead(in changes: [WhereDataGeneration]) throws -> WhereDataGeneration {
        try resolve(in: changes).current
    }

    /// Latest account reset that the installation's registration point did not observe.
    /// Registrations normally name a persisted generation. A registration made while concurrent
    /// resets resolve to a synthetic generation is recognized both while that conflict is current
    /// and
    /// after a later destructive operation joins its real reset heads.
    static func resetBarrier(
        for registrationGenerationID: WhereDataGenerationID,
        in changes: [WhereDataGeneration],
    ) throws -> Date? {
        let resets = changes.filter { $0.reason == .accountReset }
        guard resets.isEmpty == false else { return nil }

        var byID = Dictionary(uniqueKeysWithValues: changes.map { ($0.id, $0) })
        byID[initial.id] = initial

        func ancestors(of generationIDs: [WhereDataGenerationID]) -> Set<WhereDataGenerationID>? {
            var result = Set<WhereDataGenerationID>()
            var pending = generationIDs
            while let id = pending.popLast() {
                guard result.insert(id).inserted else { continue }
                guard let generation = byID[id] else { return nil }
                pending.append(contentsOf: generation.parentIDs)
            }
            return result
        }

        let observed: Set<WhereDataGenerationID>?
        if byID[registrationGenerationID] != nil {
            observed = ancestors(of: [registrationGenerationID])
        } else {
            let resolution = try resolve(in: changes)
            if resolution.current.id == registrationGenerationID {
                observed = ancestors(of: resolution.current.parentIDs)
            } else {
                let joinedResetParents = changes
                    .compactMap { generation -> [WhereDataGeneration]? in
                        let parents = generation.parentIDs.compactMap { byID[$0] }
                        let resetParents = parents.filter { $0.reason == .accountReset }
                        guard resetParents.count > 1,
                              resetConflictID(for: resetParents) == registrationGenerationID
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

    /// Versioned, domain-separated digest locked by `WhereDataGenerationTests`. Only reset-head ids
    /// participate, keeping the synthetic empty generation stable when a weaker concurrent
    /// Replace arrives while still changing it for every newly relevant reset.
    private static func resetConflictID(
        for resetHeads: [WhereDataGeneration],
    ) -> WhereDataGenerationID {
        var hasher = SHA256()
        // This namespace is part of the derived identity's wire contract. Keep its original
        // spelling even though the Swift domain term is now “generation”.
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
        return WhereDataGenerationID(rawValue: UUID(uuid: (
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

    private static func isReservedSyntheticID(_ id: WhereDataGenerationID) -> Bool {
        let bytes = id.rawValue.uuid
        return bytes.6 & 0xF0 == 0x80
    }
}
