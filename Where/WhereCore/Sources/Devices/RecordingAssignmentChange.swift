import CryptoKit
import Foundation

/// The account-wide automatic-recording assignment.
///
/// A missing device means recording is explicitly Off. Exactly one installation can otherwise
/// hold the assignment; every installation remains able to edit history and attach evidence.
public struct RecordingAssignment: Sendable, Hashable {
    public let deviceID: RecordingDeviceID?

    public static let off = RecordingAssignment(deviceID: nil)

    public static func device(_ deviceID: RecordingDeviceID) -> RecordingAssignment {
        RecordingAssignment(deviceID: deviceID)
    }

    private init(deviceID: RecordingDeviceID?) {
        self.deviceID = deviceID
    }
}

/// Why an account-wide recording assignment was appended.
public enum RecordingAssignmentReason: String, Codable, Sendable, Hashable {
    case onboarding
    case userCommand
    case backupMerge
    case accountReset
    case backupReplace
}

/// One append-only command in the account-wide automatic-recording assignment DAG.
///
/// Commands name every maximal event observed by their writer. This permits CloudKit writers to
/// converge without comparing clocks: an Off head wins concurrent assignment, identical
/// assignments coalesce, and concurrent assignments to different devices fail closed.
public struct RecordingAssignmentChange: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let parentIDs: [UUID]
    public let revision: Int64
    public let issuedAt: Date
    public let issuedByDeviceID: RecordingDeviceID
    public let effectiveAt: Date
    public let assignedDeviceID: RecordingDeviceID?
    public let reason: RecordingAssignmentReason

    public var assignment: RecordingAssignment {
        assignedDeviceID.map(RecordingAssignment.device) ?? .off
    }

    public init(
        id: UUID,
        parentIDs: [UUID],
        revision: Int64,
        issuedAt: Date,
        issuedByDeviceID: RecordingDeviceID,
        effectiveAt: Date,
        assignedDeviceID: RecordingDeviceID?,
        reason: RecordingAssignmentReason,
    ) {
        precondition(revision >= 0, "A recording-assignment revision cannot be negative.")
        precondition(
            (revision == 0) == parentIDs.isEmpty,
            "Only a recording-assignment root may omit its parents.",
        )
        let canonicalParentIDs = parentIDs.sorted { $0.uuidString < $1.uuidString }
        precondition(
            Set(canonicalParentIDs).count == canonicalParentIDs.count,
            "A recording-assignment command cannot name the same parent twice.",
        )
        precondition(
            canonicalParentIDs.contains(id) == false,
            "A recording-assignment command cannot parent itself.",
        )
        precondition(
            Self.isValid(reason: reason, assignedDeviceID: assignedDeviceID),
            "The recording assignment is invalid for its reason.",
        )
        self.id = id
        self.parentIDs = canonicalParentIDs
        self.revision = revision
        self.issuedAt = issuedAt
        self.issuedByDeviceID = issuedByDeviceID
        self.effectiveAt = effectiveAt
        self.assignedDeviceID = assignedDeviceID
        self.reason = reason
    }
}

/// Fail-closed resolution of the global assignment graph.
public enum RecordingAssignmentResolution: Sendable, Hashable {
    case unconfigured
    case resolved(RecordingAssignment)
    case conflict(Set<RecordingDeviceID>)
    case invalid

    public var assignment: RecordingAssignment? {
        guard case let .resolved(assignment) = self else { return nil }
        return assignment
    }

    public func permitsRecording(on deviceID: RecordingDeviceID) -> Bool {
        assignment?.deviceID == deviceID
    }
}

extension RecordingAssignmentChange {
    private struct CausalGraph {
        let heads: [RecordingAssignmentChange]
    }

    static func persisted(
        id: UUID,
        parentIDs: [UUID],
        revision: Int64,
        issuedAt: Date,
        issuedByDeviceID: RecordingDeviceID,
        effectiveAt: Date,
        assignedDeviceID: RecordingDeviceID?,
        reason: RecordingAssignmentReason,
    ) -> RecordingAssignmentChange? {
        guard revision >= 0,
              (revision == 0) == parentIDs.isEmpty,
              Set(parentIDs).count == parentIDs.count,
              parentIDs.contains(id) == false,
              isValid(reason: reason, assignedDeviceID: assignedDeviceID)
        else { return nil }
        return RecordingAssignmentChange(
            id: id,
            parentIDs: parentIDs,
            revision: revision,
            issuedAt: issuedAt,
            issuedByDeviceID: issuedByDeviceID,
            effectiveAt: effectiveAt,
            assignedDeviceID: assignedDeviceID,
            reason: reason,
        )
    }

    public static func resolve(
        _ changes: [RecordingAssignmentChange],
    ) -> RecordingAssignmentResolution {
        resolveValidated(changes)
    }

    public static func resolve(
        _ changes: [RecordingAssignmentChange],
        at date: Date,
    ) -> RecordingAssignmentResolution {
        guard changes.isEmpty || causalGraph(in: changes) != nil else { return .invalid }
        return resolveValidated(changes.filter { $0.effectiveAt <= date })
    }

    public static func maximalHeads(
        in changes: [RecordingAssignmentChange],
    ) -> [RecordingAssignmentChange]? {
        guard changes.isEmpty == false else { return [] }
        return causalGraph(in: changes)?.heads.sorted(by: isOrderedBefore)
    }

    /// Stable acknowledgement identity for the complete maximal frontier.
    static func frontierToken(in changes: [RecordingAssignmentChange]) -> UUID? {
        guard let heads = maximalHeads(in: changes), heads.isEmpty == false else { return nil }
        guard heads.count > 1 else { return heads[0].id }
        var hasher = SHA256()
        hasher.update(data: Data("com.stuff.where.recording-assignment-frontier.v1".utf8))
        for head in heads {
            hasher.update(data: Data("\n\(head.id.uuidString)".utf8))
        }
        let digest = Array(hasher.finalize().prefix(16))
        return UUID(uuid: (
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
        ))
    }

    public static func appendingCommand(
        to changes: [RecordingAssignmentChange],
        assignment: RecordingAssignment,
        issuedAt: Date,
        issuedByDeviceID: RecordingDeviceID,
        effectiveAt: Date,
        reason: RecordingAssignmentReason,
    ) throws -> RecordingAssignmentChange {
        guard let heads = maximalHeads(in: changes) else {
            throw RecordingPersistenceError.incompleteAssignmentHistory
        }
        let revision: Int64
        if let maximumRevision = heads.map(\.revision).max() {
            let (next, overflow) = maximumRevision.addingReportingOverflow(1)
            guard overflow == false else {
                throw RecordingPersistenceError.assignmentRevisionExhausted
            }
            revision = next
        } else {
            revision = 0
        }
        return RecordingAssignmentChange(
            id: UUID(),
            parentIDs: heads.map(\.id),
            revision: revision,
            issuedAt: issuedAt,
            issuedByDeviceID: issuedByDeviceID,
            effectiveAt: heads.reduce(effectiveAt) { max($0, $1.effectiveAt) },
            assignedDeviceID: assignment.deviceID,
            reason: reason,
        )
    }

    static func formValidPersistedTimeline(_ changes: [RecordingAssignmentChange]) -> Bool {
        changes.isEmpty || causalGraph(in: changes) != nil
    }

    static func isCanonicalBefore(
        _ lhs: RecordingAssignmentChange,
        _ rhs: RecordingAssignmentChange,
    ) -> Bool {
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
        if lhs.assignedDeviceID != rhs.assignedDeviceID {
            return (lhs.assignedDeviceID?.storeURL.absoluteString ?? "")
                < (rhs.assignedDeviceID?.storeURL.absoluteString ?? "")
        }
        return lhs.reason.rawValue < rhs.reason.rawValue
    }

    private static func resolveValidated(
        _ changes: [RecordingAssignmentChange],
    ) -> RecordingAssignmentResolution {
        guard changes.isEmpty == false else { return .unconfigured }
        guard let heads = causalGraph(in: changes)?.heads else { return .invalid }
        if heads.contains(where: { $0.assignedDeviceID == nil }) {
            return .resolved(.off)
        }
        let targets = Set(heads.compactMap(\.assignedDeviceID))
        guard targets.count == 1, let target = targets.first else {
            return .conflict(targets)
        }
        return .resolved(.device(target))
    }

    private static func causalGraph(
        in changes: [RecordingAssignmentChange],
    ) -> CausalGraph? {
        let groupedByID = Dictionary(grouping: changes, by: \.id)
        guard groupedByID.values.allSatisfy({ $0.count == 1 }) else { return nil }
        let byID = groupedByID.compactMapValues(\.first)
        var parentIDs = Set<UUID>()
        for change in changes {
            guard change.revision >= 0,
                  isValid(reason: change.reason, assignedDeviceID: change.assignedDeviceID)
            else { return nil }
            if change.revision == 0 {
                guard change.parentIDs.isEmpty else { return nil }
                continue
            }
            guard change.parentIDs.isEmpty == false,
                  change.parentIDs == change.parentIDs
                  .sorted(by: { $0.uuidString < $1.uuidString }),
                  Set(change.parentIDs).count == change.parentIDs.count,
                  change.parentIDs.contains(change.id) == false
            else { return nil }
            let parents = change.parentIDs.compactMap { byID[$0] }
            guard parents.count == change.parentIDs.count,
                  let maximumRevision = parents.map(\.revision).max(),
                  maximumRevision < Int64.max,
                  change.revision == maximumRevision + 1,
                  parents.allSatisfy({ change.effectiveAt >= $0.effectiveAt })
            else { return nil }
            parentIDs.formUnion(change.parentIDs)
        }
        let heads = changes.filter { parentIDs.contains($0.id) == false }
        return heads.isEmpty ? nil : CausalGraph(heads: heads)
    }

    private static func isValid(
        reason: RecordingAssignmentReason,
        assignedDeviceID: RecordingDeviceID?,
    ) -> Bool {
        switch reason {
            case .onboarding, .userCommand, .backupMerge: true
            case .accountReset, .backupReplace: assignedDeviceID == nil
        }
    }

    private static func isOrderedBefore(
        _ lhs: RecordingAssignmentChange,
        _ rhs: RecordingAssignmentChange,
    ) -> Bool {
        if lhs.revision != rhs.revision { return lhs.revision < rhs.revision }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
